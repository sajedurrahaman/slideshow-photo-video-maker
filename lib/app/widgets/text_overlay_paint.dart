import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
    return c.withValues(alpha: (c.a / 255.0) * opacity.clamp(0.0, 1.0));
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

  static TextStyle baseStyle(SlideOverlay o, {required double fontSize}) {
    final family = o.fontFamily.trim().isEmpty ? null : o.fontFamily;
    final fill = withOpacityArgb(o.colorArgb, o.opacity);
    return TextStyle(
      color: fill,
      fontSize: fontSize,
      fontWeight: weightOf(o.fontWeight),
      fontFamily: family,
      letterSpacing: o.letterSpacing,
      height: o.lineHeight,
      shadows: shadowsFor(o),
      foreground: o.gradientEndArgb != null
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

  /// Paint stroke (optional) then fill at [origin] (top-left of text).
  static void paint(
    Canvas canvas,
    SlideOverlay o, {
    required Offset origin,
    required double fontSize,
    double maxWidth = double.infinity,
  }) {
    if (o.strokeColorArgb != null && o.strokeWidth > 0.1) {
      final stroke = _painterForStyle(
        o,
        fontSize: fontSize,
        maxWidth: maxWidth,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weightOf(o.fontWeight),
          fontFamily: o.fontFamily.trim().isEmpty ? null : o.fontFamily,
          letterSpacing: o.letterSpacing,
          height: o.lineHeight,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = o.strokeWidth
            ..color = withOpacityArgb(o.strokeColorArgb!, o.opacity),
        ),
      );
      stroke.paint(canvas, origin);
    }
    painter(o, fontSize: fontSize, maxWidth: maxWidth).paint(canvas, origin);
  }

  /// Live / bake widget for one overlay (no selection chrome).
  static Widget styledText(SlideOverlay o, {required double fontSize}) {
    final text = o.displayText;
    if (text.isEmpty) return const SizedBox.shrink();

    Widget label = Text(
      text,
      textAlign: alignOf(o.align),
      style: baseStyle(o, fontSize: fontSize).copyWith(
        // Prefer solid color in widget path; gradient via ShaderMask.
        foreground: null,
        color: o.gradientEndArgb == null
            ? withOpacityArgb(o.colorArgb, o.opacity)
            : Colors.white,
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
      label = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            textAlign: alignOf(o.align),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: weightOf(o.fontWeight),
              fontFamily: o.fontFamily.trim().isEmpty ? null : o.fontFamily,
              letterSpacing: o.letterSpacing,
              height: o.lineHeight,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = o.strokeWidth
                ..color = withOpacityArgb(o.strokeColorArgb!, o.opacity),
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

/// Catalog used by Template / Font Style pickers.
class TextToolCatalog {
  static const fonts = <({String id, String label, String family, int weight})>[
    (id: 'default', label: 'Default', family: '', weight: 700),
    (id: 'serif', label: 'Font Style', family: 'serif', weight: 700),
    (id: 'mono', label: 'Font Style', family: 'monospace', weight: 600),
    (id: 'cursive', label: 'Font Style', family: 'cursive', weight: 500),
    (id: 'sans', label: 'Font Style', family: 'sans-serif', weight: 800),
    (id: 'light', label: 'Font Style', family: '', weight: 300),
    (id: 'black', label: 'Font Style', family: '', weight: 900),
    (id: 'italic', label: 'Font Style', family: 'serif', weight: 500),
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

  static const gradients = <(int, int)>[
    (0xFFF44336, 0xFFFFEB3B),
    (0xFF2196F3, 0xFFE91E63),
    (0xFF00BCD4, 0xFF4CAF50),
    (0xFFFF9800, 0xFFF44336),
    (0xFF9C27B0, 0xFF00BCD4),
    (0xFFFFEB3B, 0xFF4CAF50),
  ];

  static const colorPresets = <SlideOverlay>[
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      fontWeight: 800,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFEB3B,
      strokeColorArgb: 0xFFF44336,
      strokeWidth: 3,
      fontWeight: 800,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFFFFFF,
      bgColorArgb: 0xFFF44336,
      bgOpacity: 0.95,
      fontWeight: 800,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF00E5FF,
      shadowColorArgb: 0xFF00E5FF,
      shadowBlur: 10,
      shadowDistance: 0,
      fontWeight: 800,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFFFF4081,
      gradientEndArgb: 0xFFFFEB3B,
      fontWeight: 900,
    ),
    SlideOverlay(
      id: '_',
      kind: OverlayKind.text,
      colorArgb: 0xFF000000,
      bgColorArgb: 0xFFFFFFFF,
      bgOpacity: 0.9,
      bgCorner: 8,
      fontWeight: 700,
    ),
  ];
}

/// Accent used across text-tool chrome (matches screenshots).
const textToolAccent = AppColors.primary;
