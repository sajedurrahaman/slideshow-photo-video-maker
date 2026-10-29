import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';

/// Shared text-overlay styling for live preview + export bake.
class TextOverlayPaint {
  static TextAlign alignOf(TextAlignMode m) => switch (m) {
    TextAlignMode.left => TextAlign.left,
    TextAlignMode.center => TextAlign.center,
    TextAlignMode.right => TextAlign.right,
  };

  static FontWeight weightOf(int w) {
    final clamped = w.clamp(100, 900);
    return FontWeight.values.firstWhere(
      (e) => e.value == ((clamped / 100).round() * 100).clamp(100, 900),
      orElse: () => FontWeight.w700,
    );
  }

  static Color withOpacityArgb(int argb, double opacity) {
    final c = Color(argb);
    // Color.a is already 0..1 on modern Flutter — do not divide by 255.
    return c.withValues(alpha: c.a * opacity.clamp(0.0, 1.0));
  }

  static List<Shadow> shadowsFor(SlideOverlay o) {
    if (o.shadowColorArgb == null || o.shadowOpacity <= 0.001) {
      return const [];
    }
    final rad = o.shadowAngle * math.pi / 180;
    final dx = math.cos(rad) * o.shadowDistance;
    final dy = math.sin(rad) * o.shadowDistance;
    return [
      Shadow(
        color: withOpacityArgb(o.shadowColorArgb!, o.shadowOpacity),
        offset: Offset(dx, dy),
        blurRadius: o.shadowBlur,
      ),
    ];
  }

  /// Resolve Google Font family name into a registered [fontFamily], if any.
  static String? resolvedFamily(String family, {int weight = 700}) {
    final name = family.trim();
    if (name.isEmpty) return null;
    try {
      return GoogleFonts.getFont(
        name,
        fontWeight: weightOf(weight),
      ).fontFamily;
    } catch (_) {
      return name;
    }
  }

  /// Prefetch Google Fonts used by overlays (needed before canvas bake).
  static Future<void> ensureFontsLoaded(Iterable<SlideOverlay> overlays) async {
    final pending = <TextStyle>[];
    for (final o in overlays) {
      final name = o.fontFamily.trim();
      if (name.isEmpty) continue;
      try {
        pending.add(
          GoogleFonts.getFont(name, fontWeight: weightOf(o.fontWeight)),
        );
      } catch (_) {}
    }
    if (pending.isNotEmpty) {
      await GoogleFonts.pendingFonts(pending);
    }
  }

  static TextStyle baseStyle(SlideOverlay o, {required double fontSize}) {
    final fill = withOpacityArgb(o.colorArgb, o.opacity);
    final hasGradient = o.gradientEndArgb != null;
    final family = resolvedFamily(o.fontFamily, weight: o.fontWeight);
    // Flutter asserts if both color and foreground are set.
    return TextStyle(
      color: hasGradient ? null : fill,
      fontSize: fontSize,
      fontWeight: weightOf(o.fontWeight),
      fontFamily: family,
      letterSpacing: o.letterSpacing,
      height: o.lineHeight,
      shadows: shadowsFor(o),
      foreground: hasGradient
          ? (Paint()
              ..shader = ui.Gradient.linear(
                Offset.zero,
                Offset(fontSize * 4, fontSize),
                [
                  withOpacityArgb(o.colorArgb, o.opacity),
                  withOpacityArgb(o.gradientEndArgb!, o.opacity),
                ],
              ))
          : null,
    );
  }

  static TextPainter _painterForStyle(
    SlideOverlay o, {
    required double fontSize,
    required TextStyle style,
    double maxWidth = double.infinity,
  }) {
    return TextPainter(
      text: TextSpan(text: o.displayText, style: style),
      textAlign: alignOf(o.align),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
  }

  static TextPainter painter(
    SlideOverlay o, {
    required double fontSize,
    double maxWidth = double.infinity,
  }) {
    return _painterForStyle(
      o,
      fontSize: fontSize,
      style: baseStyle(o, fontSize: fontSize),
      maxWidth: maxWidth,
    );
  }

  static TextStyle _strokeStyle(
    SlideOverlay o, {
    required double fontSize,
    required String? family,
    required double width,
    required Color color,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weightOf(o.fontWeight),
      fontFamily: family,
      letterSpacing: o.letterSpacing,
      height: o.lineHeight,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  /// Bounding size for straight or curved text (used by export + selection).
  static Size layoutSize(
    SlideOverlay o, {
    required double fontSize,
    double maxWidth = double.infinity,
  }) {
    if (o.displayText.isEmpty) return Size.zero;
    if (o.curve.abs() < 0.5) {
      final tp = painter(o, fontSize: fontSize, maxWidth: maxWidth);
      return Size(tp.width, tp.height);
    }
    return _curveMetrics(o, fontSize: fontSize).size;
  }

  static _CurveMetrics _curveMetrics(
    SlideOverlay o, {
    required double fontSize,
  }) {
    final family = resolvedFamily(o.fontFamily, weight: o.fontWeight);
    final chars = o.displayText.characters.toList();
    final widths = <double>[];
    var totalW = 0.0;
    for (var i = 0; i < chars.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: chars[i],
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: weightOf(o.fontWeight),
            fontFamily: family,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      widths.add(tp.width);
      totalW += tp.width;
      if (i < chars.length - 1) {
        totalW += o.letterSpacing;
      }
    }
    totalW = math.max(totalW, 1.0);
    // CapCut-style: |curve| 100 → full circle (2π).
    final t = (o.curve / 100.0).clamp(-1.0, 1.0);
    final sign = t >= 0 ? 1.0 : -1.0;
    final angleSpan = t.abs() * 2 * math.pi;
    final radius = math.max(totalW / math.max(angleSpan, 0.001), fontSize);
    final pad = fontSize * 1.35 + (o.strokeWidth * 2.5);
    final Size size;
    final Offset circleCenter;
    if (angleSpan >= math.pi) {
      final diam = radius * 2 + pad;
      size = Size(diam, diam);
      circleCenter = Offset(diam / 2, diam / 2);
    } else {
      final half = angleSpan / 2;
      final w = 2 * radius * math.sin(half) + pad;
      final h = radius * (1 - math.cos(half)) + pad;
      size = Size(w, h);
      // +curve: bulge up (circle center below). -curve: bulge down.
      circleCenter = sign > 0
          ? Offset(w / 2, radius)
          : Offset(w / 2, h - radius);
    }
    return _CurveMetrics(
      chars: chars,
      widths: widths,
      totalW: totalW,
      radius: radius,
      angleSpan: angleSpan,
      sign: sign,
      size: size,
      circleCenter: circleCenter,
    );
  }

  /// Paint stroke (optional) then fill at [origin] (top-left of text box).
  static void paint(
    Canvas canvas,
    SlideOverlay o, {
    required Offset origin,
    required double fontSize,
    double maxWidth = double.infinity,
  }) {
    if (o.curve.abs() >= 0.5) {
      final m = _curveMetrics(o, fontSize: fontSize);
      final center = origin + m.circleCenter;
      _paintCurved(canvas, o, fontSize: fontSize, center: center, metrics: m);
      return;
    }

    if (o.strokeColorArgb != null && o.strokeWidth > 0.1) {
      final family = resolvedFamily(o.fontFamily, weight: o.fontWeight);
      final single = withOpacityArgb(o.strokeColorArgb!, o.opacity);
      final w = o.strokeWidth;
      final layers = <(double, Color)>[
        if (o.strokeDoubleColorArgb != null)
          (w * 2.15, withOpacityArgb(o.strokeDoubleColorArgb!, o.opacity)),
        (o.strokeDoubleColorArgb != null ? w * 0.9 : w, single),
      ];
      for (final layer in layers) {
        _painterForStyle(
          o,
          fontSize: fontSize,
          maxWidth: maxWidth,
          style: _strokeStyle(
            o,
            fontSize: fontSize,
            family: family,
            width: layer.$1,
            color: layer.$2,
          ),
        ).paint(canvas, origin);
      }
    }
    painter(o, fontSize: fontSize, maxWidth: maxWidth).paint(canvas, origin);
  }

  static void _paintCurved(
    Canvas canvas,
    SlideOverlay o, {
    required double fontSize,
    required Offset center,
    required _CurveMetrics metrics,
  }) {
    final family = resolvedFamily(o.fontFamily, weight: o.fontWeight);
    final fill = o.gradientEndArgb == null
        ? withOpacityArgb(o.colorArgb, o.opacity)
        : withOpacityArgb(o.colorArgb, o.opacity);
    final strokeLayers = <(double, Color)>[
      if (o.strokeColorArgb != null && o.strokeWidth > 0.1) ...[
        if (o.strokeDoubleColorArgb != null)
          (
            o.strokeWidth * 2.15,
            withOpacityArgb(o.strokeDoubleColorArgb!, o.opacity),
          ),
        (
          o.strokeDoubleColorArgb != null
              ? o.strokeWidth * 0.9
              : o.strokeWidth,
          withOpacityArgb(o.strokeColorArgb!, o.opacity),
        ),
      ],
    ];

    var distance = 0.0;
    for (var i = 0; i < metrics.chars.length; i++) {
      final ch = metrics.chars[i];
      final cw = metrics.widths[i];
      final mid = distance + cw / 2;
      final theta =
          -metrics.angleSpan / 2 + (mid / metrics.totalW) * metrics.angleSpan;
      final x = metrics.radius * math.sin(theta);
      // +sign: sit on lower arc (bulge up). -sign: upper arc (bulge down).
      final y = -metrics.sign * metrics.radius * math.cos(theta);
      final rot = theta;

      void paintStyled(TextStyle style) {
        final tp = TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(center.dx + x, center.dy + y);
        canvas.rotate(rot);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }

      for (final layer in strokeLayers) {
        paintStyled(
          _strokeStyle(
            o,
            fontSize: fontSize,
            family: family,
            width: layer.$1,
            color: layer.$2,
          ),
        );
      }
      paintStyled(
        TextStyle(
          color: fill,
          fontSize: fontSize,
          fontWeight: weightOf(o.fontWeight),
          fontFamily: family,
          shadows: shadowsFor(o),
        ),
      );

      distance += cw + o.letterSpacing;
    }
  }

  /// Live / bake widget for one overlay (no selection chrome).
  static Widget styledText(SlideOverlay o, {required double fontSize}) {
    final text = o.displayText;
    if (text.isEmpty) return const SizedBox.shrink();

    if (o.curve.abs() >= 0.5) {
      final m = _curveMetrics(o, fontSize: fontSize);
      Widget curved = CustomPaint(
        size: m.size,
        painter: _CurvedTextPainter(overlay: o, fontSize: fontSize, metrics: m),
      );
      if (o.bgColorArgb != null && o.bgOpacity > 0.01) {
        curved = Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: withOpacityArgb(o.bgColorArgb!, o.bgOpacity),
            borderRadius: BorderRadius.circular(o.bgCorner),
          ),
          child: curved,
        );
      }
      return curved;
    }

    // Build style fresh — copyWith(foreground: null) does not clear foreground.
    final family = resolvedFamily(o.fontFamily, weight: o.fontWeight);
    Widget label = Text(
      text,
      textAlign: alignOf(o.align),
      style: TextStyle(
        // Solid fill here; gradient applied via ShaderMask below.
        color: o.gradientEndArgb == null
            ? withOpacityArgb(o.colorArgb, o.opacity)
            : Colors.white,
        fontSize: fontSize,
        fontWeight: weightOf(o.fontWeight),
        fontFamily: family,
        letterSpacing: o.letterSpacing,
        height: o.lineHeight,
        shadows: shadowsFor(o),
      ),
    );

    if (o.gradientEndArgb != null) {
      label = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [
            withOpacityArgb(o.colorArgb, o.opacity),
            withOpacityArgb(o.gradientEndArgb!, o.opacity),
          ],
        ).createShader(bounds),
        child: label,
      );
    }

    if (o.strokeColorArgb != null && o.strokeWidth > 0.1) {
      final single = withOpacityArgb(o.strokeColorArgb!, o.opacity);
      final w = o.strokeWidth;
      final layers = <(double, Color)>[
        if (o.strokeDoubleColorArgb != null)
          (w * 2.15, withOpacityArgb(o.strokeDoubleColorArgb!, o.opacity)),
        (o.strokeDoubleColorArgb != null ? w * 0.9 : w, single),
      ];
      label = Stack(
        alignment: Alignment.center,
        children: [
          for (final layer in layers)
            Text(
              text,
              textAlign: alignOf(o.align),
              style: _strokeStyle(
                o,
                fontSize: fontSize,
                family: family,
                width: layer.$1,
                color: layer.$2,
              ),
            ),
          label,
        ],
      );
    }

    if (o.bgColorArgb != null && o.bgOpacity > 0.01) {
      label = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: withOpacityArgb(o.bgColorArgb!, o.bgOpacity),
          borderRadius: BorderRadius.circular(o.bgCorner),
        ),
        child: label,
      );
    }

    return label;
  }
}

class _CurveMetrics {
  const _CurveMetrics({
    required this.chars,
    required this.widths,
    required this.totalW,
    required this.radius,
    required this.angleSpan,
    required this.sign,
    required this.size,
    required this.circleCenter,
  });

  final List<String> chars;
  final List<double> widths;
  final double totalW;
  final double radius;
  final double angleSpan;
  final double sign;
  final Size size;
  final Offset circleCenter;
}

class _CurvedTextPainter extends CustomPainter {
  _CurvedTextPainter({
    required this.overlay,
    required this.fontSize,
    required this.metrics,
  });

  final SlideOverlay overlay;
  final double fontSize;
  final _CurveMetrics metrics;

  @override
  void paint(Canvas canvas, Size size) {
    TextOverlayPaint._paintCurved(
      canvas,
      overlay,
      fontSize: fontSize,
      center: metrics.circleCenter,
      metrics: metrics,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvedTextPainter old) =>
      old.overlay != overlay ||
      old.fontSize != fontSize ||
      old.metrics.size != metrics.size;
}

/// Catalog used by Font Style picker.
/// Families are Google Fonts names (runtime-fetched via [google_fonts]).
/// Skipped from screenshots (not on Google Fonts / proprietary):
/// Billow, Nautilus Pompilius, Daniel, Chalk, Sunday Mood.
class TextToolCatalog {
  static const fonts = <({String id, String label, String family, int weight})>[
    (id: 'default', label: 'Default', family: '', weight: 700),
    (id: 'roboto', label: 'Roboto', family: 'Roboto', weight: 400),
    (id: 'roboto_bold', label: 'Roboto Bold', family: 'Roboto', weight: 700),
    (id: 'poppins', label: 'Poppins', family: 'Poppins', weight: 600),
    (id: 'rubik', label: 'Rubik', family: 'Rubik', weight: 500),
    (id: 'murecho', label: 'Murecho', family: 'Murecho', weight: 500),
    (id: 'marmelad', label: 'Marmelad', family: 'Marmelad', weight: 400),
    (id: 'nunito_sans', label: 'Nunito Sans', family: 'Nunito Sans', weight: 600),
    (id: 'noto_serif', label: 'Noto Serif', family: 'Noto Serif', weight: 600),
    (id: 'roboto_slab', label: 'Roboto Slab', family: 'Roboto Slab', weight: 600),
    (id: 'gabriela', label: 'Gabriela', family: 'Gabriela', weight: 400),
    (id: 'kurale', label: 'Kurale', family: 'Kurale', weight: 400),
    (id: 'abhaya', label: 'Abhaya Libre', family: 'Abhaya Libre', weight: 600),
    (id: 'geo', label: 'Geo', family: 'Geo', weight: 400),
    (id: 'limelight', label: 'Limelight', family: 'Limelight', weight: 400),
    (id: 'gorditas', label: 'Gorditas', family: 'Gorditas', weight: 700),
    (id: 'fascinate', label: 'Fascinate', family: 'Fascinate', weight: 400),
    (id: 'sigmar', label: 'Sigmar', family: 'Sigmar', weight: 400),
    (id: 'coiny', label: 'Coiny', family: 'Coiny', weight: 400),
    (id: 'nerko', label: 'Nerko One', family: 'Nerko One', weight: 400),
    (id: 'metal', label: 'Metal Mania', family: 'Metal Mania', weight: 400),
    (id: 'special_elite', label: 'Special Elite', family: 'Special Elite', weight: 400),
    (id: 'meddon', label: 'Meddon', family: 'Meddon', weight: 400),
    (id: 'bad_script', label: 'Bad Script', family: 'Bad Script', weight: 400),
    (id: 'caveat', label: 'Caveat', family: 'Caveat', weight: 500),
    (id: 'lobster', label: 'Lobster', family: 'Lobster', weight: 400),
    (id: 'yellowtail', label: 'Yellowtail', family: 'Yellowtail', weight: 400),
    (id: 'great_vibes', label: 'Great Vibes', family: 'Great Vibes', weight: 400),
    (id: 'montecarlo', label: 'MonteCarlo', family: 'MonteCarlo', weight: 400),
    (id: 'corinthia', label: 'Corinthia', family: 'Corinthia', weight: 400),
    (id: 'parisienne', label: 'Parisienne', family: 'Parisienne', weight: 400),
    (id: 'alex_brush', label: 'Alex Brush', family: 'Alex Brush', weight: 400),
    (id: 'dancing', label: 'Dancing Script', family: 'Dancing Script', weight: 500),
    (id: 'courgette', label: 'Courgette', family: 'Courgette', weight: 400),
    (id: 'vibur', label: 'Vibur', family: 'Vibur', weight: 400),
    (id: 'meow', label: 'Meow Script', family: 'Meow Script', weight: 400),
    (id: 'gamja', label: 'Gamja Flower', family: 'Gamja Flower', weight: 400),
    (id: 'walter', label: 'Walter Turncoat', family: 'Walter Turncoat', weight: 400),
  ];

  static const templates = <({String id, String label, SlideOverlay style})>[
    (
      id: 'default',
      label: 'Default',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFFFFFF,
        fontWeight: 700,
      ),
    ),
    (
      id: 'potato',
      label: 'POTATO',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFFC107,
        fontWeight: 900,
        strokeColorArgb: 0xFFE65100,
        strokeWidth: 3,
      ),
    ),
    (
      id: 'goodbye',
      label: 'Goodbye',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFFFFFF,
        bgColorArgb: 0xFF7C4DFF,
        bgOpacity: 0.95,
        bgCorner: 20,
        fontWeight: 700,
      ),
    ),
    (
      id: 'noway',
      label: 'no way!',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFF4081,
        fontWeight: 900,
        textCase: TextCaseMode.lower,
        strokeColorArgb: 0xFF000000,
        strokeWidth: 2,
      ),
    ),
    (
      id: 'loveyou',
      label: 'LOVE YOU!',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFF80AB,
        fontWeight: 900,
        textCase: TextCaseMode.upper,
        shadowColorArgb: 0xFFFF1744,
        shadowBlur: 8,
        shadowDistance: 2,
      ),
    ),
    (
      id: 'neon',
      label: 'NEON',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFF00E5FF,
        fontWeight: 800,
        shadowColorArgb: 0xFF00B0FF,
        shadowBlur: 12,
        shadowDistance: 0,
        shadowOpacity: 0.9,
      ),
    ),
    (
      id: 'outline',
      label: 'Outline',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0x00000000,
        opacity: 1,
        strokeColorArgb: 0xFFFFFFFF,
        strokeWidth: 2.5,
        fontWeight: 800,
      ),
    ),
    (
      id: 'shadow',
      label: 'Shadow',
      style: SlideOverlay(
        id: '_',
        kind: OverlayKind.text,
        colorArgb: 0xFFFFFFFF,
        shadowColorArgb: 0xFF000000,
        shadowDistance: 6,
        shadowAngle: 90,
        shadowBlur: 0,
        shadowOpacity: 0.85,
        fontWeight: 800,
      ),
    ),
  ];

  static const solidColors = <int?>[
    null, // none
    0xFF000000,
    0xFFFFFFFF,
    0xFF9E9E9E,
    0xFFF44336,
    0xFFCDDC39,
    0xFF2196F3,
    0xFF03A9F4,
    0xFF00BCD4,
    0xFF4CAF50,
    0xFFFFEB3B,
    0xFFFF9800,
    0xFFE91E63,
    0xFF9C27B0,
  ];

  /// Stroke Single / Double swatch row (screenshot order).
  static const strokeSwatches = <int>[
    0xFF000000,
    0xFFFFFFFF,
    0xFF9E9E9E,
    0xFFF44336,
    0xFFCDDC39,
    0xFF2196F3,
    0xFF03A9F4,
    0xFF00BCD4,
    0xFF4CAF50,
    0xFFFFEB3B,
  ];

  static const gradients = <(int, int)>[
    (0xFFF44336, 0xFFFFEB3B),
    (0xFF2196F3, 0xFFE91E63),
    (0xFF00BCD4, 0xFF4CAF50),
    (0xFFFF9800, 0xFFF44336),
    (0xFF9C27B0, 0xFF00BCD4),
    (0xFFFFEB3B, 0xFF4CAF50),
    // +7 more
    (0xFFFF4081, 0xFFFFEB3B),
    (0xFF00E5FF, 0xFF7C4DFF),
    (0xFFFF5722, 0xFFFFC107),
    (0xFF8BC34A, 0xFF00BCD4),
    (0xFFE91E63, 0xFF9C27B0),
    (0xFF3F51B5, 0xFF00E5FF),
    (0xFFFF9800, 0xFFE91E63),
  ];

  /// Ready fill+stroke styles (Color Style → Text row). First = none/default.
  static const colorPresets = <SlideOverlay>[
    // 1 Default / none — plain white, no stroke
    SlideOverlay(
      id: 'preset_none',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      strokeWidth: 0,
      fontWeight: 700,
    ),
    // 2 White + light grey outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      strokeColorArgb: 0xFFBDBDBD,
      strokeWidth: 3.5,
      fontWeight: 900,
    ),
    // 3 White + thick black outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 4 Yellow + thick black outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFEB3B,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 5 Red + thick black outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFF44336,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 6 White + thick magenta outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      strokeColorArgb: 0xFFE91E63,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 7 White + thick violet outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      strokeColorArgb: 0xFF7B1FA2,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 8 Brown + thick black outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF8D6E63,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 9 Light green + thick dark green outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFAED581,
      strokeColorArgb: 0xFF33691E,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 10 Cyan + thick navy outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF00E5FF,
      strokeColorArgb: 0xFF0D47A1,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 11 Orange + thick dark brown outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFF9800,
      strokeColorArgb: 0xFF4E342E,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 12 Hot pink + thick white outline
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFF4081,
      strokeColorArgb: 0xFFFFFFFF,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    // 13–20 Gradient fill + stroke
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFF44336,
      gradientEndArgb: 0xFFFFEB3B,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF2196F3,
      gradientEndArgb: 0xFFE91E63,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF00BCD4,
      gradientEndArgb: 0xFF4CAF50,
      strokeColorArgb: 0xFF004D40,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFF9800,
      gradientEndArgb: 0xFFF44336,
      strokeColorArgb: 0xFF3E2723,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF9C27B0,
      gradientEndArgb: 0xFF00BCD4,
      strokeColorArgb: 0xFFFFFFFF,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFEB3B,
      gradientEndArgb: 0xFF4CAF50,
      strokeColorArgb: 0xFF1B5E20,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFF4081,
      gradientEndArgb: 0xFFFFEB3B,
      strokeColorArgb: 0xFF880E4F,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF00E5FF,
      gradientEndArgb: 0xFF7C4DFF,
      strokeColorArgb: 0xFF000000,
      strokeWidth: 4.5,
      fontWeight: 900,
    ),
  ];
}

/// Accent used across text-tool chrome (matches screenshots).
const textToolAccent = AppColors.primary;
