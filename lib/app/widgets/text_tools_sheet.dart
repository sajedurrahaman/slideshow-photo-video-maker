import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import 'text_overlay_paint.dart';

enum TextToolsMainTab { template, fontStyle, colorStyle }

enum TextColorSubTab { text, stroke, bg, shadow, alignment }

/// CapCut-style text tools: input bar + Template / Font Style / Color Style.
class TextToolsSheet extends StatefulWidget {
  const TextToolsSheet({
    super.key,
    required this.project,
    required this.controller,
    required this.focusNode,
    required this.selectedOverlayId,
    required this.onSelectedOverlayId,
    required this.onClose,
    required this.onConfirm,
    this.compactKeyboardPhase = false,
  });

  final SlideshowProject project;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? selectedOverlayId;
  final ValueChanged<String?> onSelectedOverlayId;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  /// First phase: only input row (keyboard open). After check → full tabs.
  final bool compactKeyboardPhase;

  static const sheetBodyHeight = 280.0;

  @override
  State<TextToolsSheet> createState() => _TextToolsSheetState();
}

class _TextToolsSheetState extends State<TextToolsSheet> {
  TextToolsMainTab _mainTab = TextToolsMainTab.template;
  TextColorSubTab _colorSub = TextColorSubTab.text;
  bool _showTabs = false;

  SlideOverlay? get _selected {
    final id = widget.selectedOverlayId;
    if (id == null) return null;
    try {
      return widget.project.overlays.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _showTabs = !widget.compactKeyboardPhase && _selected != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_showTabs) {
        widget.focusNode.requestFocus();
      }
    });
  }

  void _ensureOverlay({String? text}) {
    final value = (text ?? widget.controller.text).trim();
    final existing = _selected;
    if (existing != null) {
      if (value.isNotEmpty && existing.text != value) {
        widget.project.updateOverlay(existing.copyWith(text: value));
      }
      return;
    }
    if (value.isEmpty) return;
    final id = 'text_${DateTime.now().millisecondsSinceEpoch}';
    final overlay = SlideOverlay(
      id: id,
      kind: OverlayKind.text,
      text: value,
      colorArgb: 0xFFFFFFFF,
      ny: 0.35,
      nx: 0.5,
      shadowColorArgb: 0xFF000000,
      shadowOpacity: 0.55,
      shadowBlur: 6,
      shadowDistance: 2,
    );
    widget.project.addOverlay(overlay);
    widget.onSelectedOverlayId(id);
  }

  void _patch(SlideOverlay Function(SlideOverlay o) fn) {
    final o = _selected;
    if (o == null) {
      _ensureOverlay();
    }
    final cur = _selected;
    if (cur == null) return;
    widget.project.updateOverlay(fn(cur));
  }

  void _onCheck() {
    final value = widget.controller.text.trim();
    if (value.isEmpty && _selected == null) {
      widget.onClose();
      return;
    }
    _ensureOverlay(text: value.isEmpty ? 'Photo Editor' : value);
    if (widget.controller.text.trim().isEmpty) {
      widget.controller.text = 'Photo Editor';
    }
    widget.focusNode.unfocus();
    setState(() => _showTabs = true);
    widget.onConfirm();
  }

  void _applyTemplate(({String id, String label, SlideOverlay style}) t) {
    _ensureOverlay(
      text: widget.controller.text.trim().isEmpty
          ? t.label
          : widget.controller.text.trim(),
    );
    _patch((o) {
      final s = t.style;
      if (widget.controller.text.trim().isEmpty) {
        widget.controller.text = t.label;
      }
      return o.copyWith(
        text: widget.controller.text.trim().isEmpty ? t.label : o.text,
        colorArgb: s.colorArgb,
        opacity: s.opacity,
        fontFamily: s.fontFamily,
        fontWeight: s.fontWeight,
        strokeColorArgb: s.strokeColorArgb,
        strokeWidth: s.strokeWidth,
        bgColorArgb: s.bgColorArgb,
        bgOpacity: s.bgOpacity,
        bgCorner: s.bgCorner,
        shadowColorArgb: s.shadowColorArgb,
        shadowDistance: s.shadowDistance,
        shadowAngle: s.shadowAngle,
        shadowOpacity: s.shadowOpacity,
        shadowBlur: s.shadowBlur,
        gradientEndArgb: s.gradientEndArgb,
        textCase: s.textCase,
        templateId: t.id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.project,
      builder: (context, _) {
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              _inputBar(),
              if (_showTabs) ...[
                _mainTabs(),
                Expanded(child: _tabBody()),
              ] else
                const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: (v) {
                final o = _selected;
                if (o != null) {
                  widget.project.updateOverlay(o.copyWith(text: v));
                }
              },
              onSubmitted: (_) => _onCheck(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: 'Enter text',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: const Color(0xFFF0F1F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _onCheck,
            icon: const Icon(Icons.check_rounded, size: 28),
            color: Colors.black87,
          ),
        ],
      ),
    );
  }

  Widget _mainTabs() {
    Widget tab(TextToolsMainTab t, String label) {
      final on = _mainTab == t;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _mainTab = t),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: on ? textToolAccent : AppColors.textMuted,
                  ),
                ),
              ),
              Container(
                height: 2.5,
                color: on ? textToolAccent : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          tab(TextToolsMainTab.template, 'Template'),
          tab(TextToolsMainTab.fontStyle, 'Font Style'),
          tab(TextToolsMainTab.colorStyle, 'Color Style'),
        ],
      ),
    );
  }

  Widget _tabBody() {
    return switch (_mainTab) {
      TextToolsMainTab.template => _templateGrid(),
      TextToolsMainTab.fontStyle => _fontGrid(),
      TextToolsMainTab.colorStyle => _colorStyleBody(),
    };
  }

  Widget _templateGrid() {
    final sel = _selected?.templateId ?? 'default';
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: TextToolCatalog.templates.length,
      itemBuilder: (context, i) {
        final t = TextToolCatalog.templates[i];
        final on = sel == t.id;
        return GestureDetector(
          onTap: () => _applyTemplate(t),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: on ? textToolAccent : AppColors.border,
                width: on ? 2 : 1,
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: t.id == 'default'
                    ? Text(
                        'Default',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: on ? textToolAccent : AppColors.textDark,
                          fontSize: 12,
                        ),
                      )
                    : FittedBox(
                        child: TextOverlayPaint.styledText(
                          t.style.copyWith(text: t.label),
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fontGrid() {
    final family = _selected?.fontFamily ?? '';
    final weight = _selected?.fontWeight ?? 700;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: TextToolCatalog.fonts.length,
      itemBuilder: (context, i) {
        final f = TextToolCatalog.fonts[i];
        final on = family == f.family && weight == f.weight ||
            (i == 0 && family.isEmpty && (_selected == null || weight == 700));
        return GestureDetector(
          onTap: () {
            _ensureOverlay();
            _patch(
              (o) => o.copyWith(fontFamily: f.family, fontWeight: f.weight),
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: on ? textToolAccent : AppColors.border,
                width: on ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                i == 0 ? 'Default' : 'Font Style',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: f.family.isEmpty ? null : f.family,
                  fontWeight: TextOverlayPaint.weightOf(f.weight),
                  fontSize: 12,
                  color: on ? textToolAccent : AppColors.textDark,
                  fontStyle: f.id == 'italic' ? FontStyle.italic : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _colorStyleBody() {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in TextColorSubTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_subLabel(s)),
                    selected: _colorSub == s,
                    onSelected: (_) => setState(() => _colorSub = s),
                    selectedColor: textToolAccent,
                    labelStyle: TextStyle(
                      color: _colorSub == s ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    backgroundColor: const Color(0xFFEEF1F5),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (_colorSub) {
            TextColorSubTab.text => _textColorPane(),
            TextColorSubTab.stroke => _strokePane(),
            TextColorSubTab.bg => _bgPane(),
            TextColorSubTab.shadow => _shadowPane(),
            TextColorSubTab.alignment => _alignPane(),
          },
        ),
      ],
    );
  }

  String _subLabel(TextColorSubTab s) => switch (s) {
    TextColorSubTab.text => 'Text',
    TextColorSubTab.stroke => 'Stroke',
    TextColorSubTab.bg => 'BG',
    TextColorSubTab.shadow => 'Shadow',
    TextColorSubTab.alignment => 'Alignment',
  };

  Widget _textColorPane() {
    final o = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: TextToolCatalog.colorPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = TextToolCatalog.colorPresets[i];
              return GestureDetector(
                onTap: () {
                  _ensureOverlay();
                  _patch(
                    (cur) => cur.copyWith(
                      colorArgb: p.colorArgb,
                      strokeColorArgb: p.strokeColorArgb,
                      strokeWidth: p.strokeWidth,
                      bgColorArgb: p.bgColorArgb,
                      bgOpacity: p.bgOpacity,
                      bgCorner: p.bgCorner,
                      shadowColorArgb: p.shadowColorArgb,
                      shadowBlur: p.shadowBlur,
                      shadowDistance: p.shadowDistance,
                      shadowOpacity: p.shadowOpacity,
                      gradientEndArgb: p.gradientEndArgb,
                      fontWeight: p.fontWeight,
                    ),
                  );
                },
                child: Container(
                  width: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextOverlayPaint.styledText(
                    p.copyWith(text: 'Aa'),
                    fontSize: 18,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _labeledRow(
          'Color',
          _colorRow(
            selected: o?.colorArgb,
            includeNone: false,
            includeRainbow: true,
            onPick: (c) {
              if (c == null) return;
              _patch(
                (cur) => cur.copyWith(
                  colorArgb: c,
                  gradientEndArgb: null,
                ),
              );
            },
            onRainbow: () {
              _patch(
                (cur) => cur.copyWith(
                  colorArgb: 0xFFF44336,
                  gradientEndArgb: 0xFFFFEB3B,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _labeledRow(
          'Gradient',
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _rainbowChip(
                  onTap: () {
                    _patch(
                      (cur) => cur.copyWith(
                        colorArgb: 0xFFF44336,
                        gradientEndArgb: 0xFFFFEB3B,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                for (final g in TextToolCatalog.gradients) ...[
                  GestureDetector(
                    onTap: () => _patch(
                      (cur) => cur.copyWith(
                        colorArgb: g.$1,
                        gradientEndArgb: g.$2,
                      ),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(g.$1), Color(g.$2)],
                        ),
                        border: Border.all(
                          color:
                              o?.colorArgb == g.$1 &&
                                  o?.gradientEndArgb == g.$2
                              ? textToolAccent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sliderRow(
          'Opacity',
          ((o?.opacity ?? 1) * 100).round(),
          0,
          100,
          (v) => _patch((cur) => cur.copyWith(opacity: v / 100)),
        ),
      ],
    );
  }

  Widget _strokePane() {
    final o = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _colorRow(
          selected: o?.strokeColorArgb,
          includeNone: true,
          includeRainbow: true,
          onPick: (c) => _patch(
            (cur) => cur.copyWith(
              strokeColorArgb: c,
              strokeWidth: c == null ? 0 : math.max(cur.strokeWidth, 2),
            ),
          ),
          onRainbow: () => _patch(
            (cur) => cur.copyWith(
              strokeColorArgb: 0xFFF44336,
              strokeWidth: math.max(cur.strokeWidth, 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _colorRow(
          selected: o?.strokeColorArgb,
          includeNone: true,
          includeRainbow: false,
          onPick: (c) => _patch(
            (cur) => cur.copyWith(
              strokeColorArgb: c,
              strokeWidth: c == null ? 0 : math.max(cur.strokeWidth, 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sliderRow(
          'Thickness',
          (o?.strokeWidth ?? 0).round().clamp(0, 20),
          0,
          20,
          (v) => _patch((cur) => cur.copyWith(strokeWidth: v.toDouble())),
        ),
      ],
    );
  }

  Widget _bgPane() {
    final o = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _labeledRow(
          'Color',
          _colorRow(
            selected: o?.bgColorArgb,
            includeNone: true,
            includeRainbow: true,
            onPick: (c) => _patch((cur) => cur.copyWith(bgColorArgb: c)),
            onRainbow: () =>
                _patch((cur) => cur.copyWith(bgColorArgb: 0xFFF44336)),
          ),
        ),
        const SizedBox(height: 10),
        _sliderRow(
          'Opacity',
          ((o?.bgOpacity ?? 0.15) * 100).round(),
          0,
          100,
          (v) => _patch((cur) => cur.copyWith(bgOpacity: v / 100)),
        ),
        _sliderRow(
          'Corner',
          (o?.bgCorner ?? 10).round(),
          0,
          40,
          (v) => _patch((cur) => cur.copyWith(bgCorner: v.toDouble())),
        ),
      ],
    );
  }

  Widget _shadowPane() {
    final o = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _colorRow(
          selected: o?.shadowColorArgb,
          includeNone: true,
          includeRainbow: true,
          onPick: (c) => _patch(
            (cur) => cur.copyWith(
              shadowColorArgb: c,
              shadowOpacity: c == null ? 0 : math.max(cur.shadowOpacity, 0.4),
            ),
          ),
          onRainbow: () => _patch(
            (cur) => cur.copyWith(
              shadowColorArgb: 0xFFF44336,
              shadowOpacity: math.max(cur.shadowOpacity, 0.4),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sliderRow(
          'Distance',
          (o?.shadowDistance ?? 4).round(),
          0,
          40,
          (v) => _patch((cur) => cur.copyWith(shadowDistance: v.toDouble())),
        ),
        _sliderRow(
          'Angle',
          (o?.shadowAngle ?? 45).round() % 360,
          0,
          360,
          (v) => _patch((cur) => cur.copyWith(shadowAngle: v.toDouble())),
        ),
        _sliderRow(
          'Opacity',
          ((o?.shadowOpacity ?? 0.6) * 100).round(),
          0,
          100,
          (v) => _patch((cur) => cur.copyWith(shadowOpacity: v / 100)),
        ),
        _sliderRow(
          'Blur',
          (o?.shadowBlur ?? 6).round(),
          0,
          40,
          (v) => _patch((cur) => cur.copyWith(shadowBlur: v.toDouble())),
        ),
      ],
    );
  }

  Widget _alignPane() {
    final o = _selected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _labeledRow(
          'Case',
          Row(
            children: [
              for (final c in TextCaseMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _squareToggle(
                    selected: (o?.textCase ?? TextCaseMode.none) == c,
                    onTap: () => _patch((cur) => cur.copyWith(textCase: c)),
                    child: Text(
                      switch (c) {
                        TextCaseMode.none => '⊘',
                        TextCaseMode.sentence => 'Aa',
                        TextCaseMode.upper => 'AA',
                        TextCaseMode.lower => 'aa',
                      },
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _labeledRow(
          'Alignment',
          Row(
            children: [
              for (final a in TextAlignMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _squareToggle(
                    selected: (o?.align ?? TextAlignMode.center) == a,
                    onTap: () => _patch((cur) => cur.copyWith(align: a)),
                    child: Icon(
                      switch (a) {
                        TextAlignMode.left => Icons.format_align_left,
                        TextAlignMode.center => Icons.format_align_center,
                        TextAlignMode.right => Icons.format_align_right,
                      },
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _sliderRow(
          'Curve',
          (o?.curve ?? 0).round(),
          0,
          100,
          (v) => _patch((cur) => cur.copyWith(curve: v.toDouble())),
        ),
        _sliderRow(
          'Size',
          (o?.fontSize ?? 36).round().clamp(12, 96),
          12,
          96,
          (v) => _patch((cur) => cur.copyWith(fontSize: v.toDouble())),
        ),
        _sliderRow(
          'Letter',
          (o?.letterSpacing ?? 0).round().clamp(-5, 40),
          -5,
          40,
          (v) => _patch((cur) => cur.copyWith(letterSpacing: v.toDouble())),
        ),
        _sliderRow(
          'Line',
          (((o?.lineHeight ?? 1.2) - 0.8) * 50).round().clamp(0, 100),
          0,
          100,
          (v) =>
              _patch((cur) => cur.copyWith(lineHeight: 0.8 + (v / 50))),
        ),
      ],
    );
  }

  Widget _labeledRow(String label, Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textDark,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _sliderRow(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: textToolAccent,
                inactiveTrackColor: textToolAccent.withValues(alpha: 0.2),
                thumbColor: textToolAccent,
                overlayColor: textToolAccent.withValues(alpha: 0.12),
                trackHeight: 4,
              ),
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                onChanged: (v) {
                  _ensureOverlay();
                  onChanged(v.round());
                },
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(
              value.toString().padLeft(2, '0'),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow({
    required int? selected,
    required bool includeNone,
    required bool includeRainbow,
    required ValueChanged<int?> onPick,
    VoidCallback? onRainbow,
  }) {
    final colors = TextToolCatalog.solidColors
        .where((c) => includeNone || c != null)
        .toList();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (includeRainbow) ...[
            _rainbowChip(onTap: onRainbow ?? () {}),
            const SizedBox(width: 8),
          ],
          for (final c in colors) ...[
            GestureDetector(
              onTap: () {
                _ensureOverlay();
                onPick(c);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c == null ? Colors.transparent : Color(c),
                  border: Border.all(
                    color: selected == c
                        ? const Color(0xFFFF5CA8)
                        : AppColors.border,
                    width: selected == c ? 2.5 : 1,
                  ),
                ),
                child: c == null
                    ? const Icon(Icons.block, size: 18, color: Colors.black45)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _rainbowChip({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        _ensureOverlay();
        onTap();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
        ),
      ),
    );
  }

  Widget _squareToggle({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: () {
        _ensureOverlay();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? textToolAccent.withValues(alpha: 0.15)
              : const Color(0xFFEEF1F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? textToolAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Live text overlays on the preview canvas with CapCut-style handles.
class LiveTextOverlaysLayer extends StatefulWidget {
  const LiveTextOverlaysLayer({
    super.key,
    required this.project,
    required this.selectedOverlayId,
    required this.onSelectedOverlayId,
    required this.editing,
  });

  final SlideshowProject project;
  final String? selectedOverlayId;
  final ValueChanged<String?> onSelectedOverlayId;
  final bool editing;

  @override
  State<LiveTextOverlaysLayer> createState() => _LiveTextOverlaysLayerState();
}

class _LiveTextOverlaysLayerState extends State<LiveTextOverlaysLayer> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.project,
      builder: (context, _) {
        final texts = widget.project.overlays
            .where((o) => o.kind == OverlayKind.text)
            .toList();
        if (texts.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final o in texts)
                  _positionedText(
                    o,
                    canvasW: w,
                    canvasH: h,
                    selected: widget.editing && widget.selectedOverlayId == o.id,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _positionedText(
    SlideOverlay o, {
    required double canvasW,
    required double canvasH,
    required bool selected,
  }) {
    final fontSize = o.fontSize * o.scale;
    return Positioned(
      left: o.nx * canvasW,
      top: o.ny * canvasH,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: o.rotation,
          child: GestureDetector(
            onTap: () {
              if (!widget.editing) return;
              widget.onSelectedOverlayId(o.id);
            },
            onPanUpdate: selected
                ? (d) {
                    widget.project.updateOverlay(
                      o.copyWith(
                        nx: (o.nx + d.delta.dx / canvasW).clamp(0.05, 0.95),
                        ny: (o.ny + d.delta.dy / canvasH).clamp(0.05, 0.95),
                      ),
                    );
                  }
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: selected
                      ? BoxDecoration(
                          border: Border.all(
                            color: textToolAccent,
                            width: 1.5,
                          ),
                        )
                      : null,
                  child: TextOverlayPaint.styledText(o, fontSize: fontSize),
                ),
                if (selected) ...[
                  Positioned(
                    left: -14,
                    top: -14,
                    child: _handleBtn(
                      Icons.close_rounded,
                      () {
                        widget.project.removeOverlay(o.id);
                        widget.onSelectedOverlayId(null);
                      },
                    ),
                  ),
                  Positioned(
                    left: -14,
                    bottom: -14,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        final next = o.rotation + d.delta.dx * 0.01;
                        widget.project.updateOverlay(
                          o.copyWith(rotation: next),
                        );
                      },
                      child: _handleBtn(Icons.rotate_right_rounded, null),
                    ),
                  ),
                  Positioned(
                    right: -14,
                    bottom: -14,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        final next = (o.scale + d.delta.dx * 0.01)
                            .clamp(0.4, 4.0)
                            .toDouble();
                        widget.project.updateOverlay(o.copyWith(scale: next));
                      },
                      child: _handleBtn(Icons.open_in_full_rounded, null),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handleBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Colors.black87,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
}
