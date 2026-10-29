import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import 'text_overlay_paint.dart';

enum TextToolsMainTab { fontStyle, colorStyle }

enum TextColorSubTab { text, stroke, bg, shadow, alignment }

/// CapCut-style text tools: input bar + Font Style / Color Style.
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
  TextToolsMainTab _mainTab = TextToolsMainTab.fontStyle;
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

  bool get _isTyping {
    return widget.focusNode.hasFocus ||
        MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  void _commitTextIfNeeded() {
    final value = widget.controller.text.trim();
    if (value.isEmpty && _selected == null) return;
    _ensureOverlay(text: value.isEmpty ? 'Photo Editor' : value);
    if (widget.controller.text.trim().isEmpty) {
      widget.controller.text = 'Photo Editor';
    }
  }

  /// Keyboard open: hide keyboard only; keep text bottom sheet + show tools.
  void _onKeyboardDone() {
    _commitTextIfNeeded();
    if (widget.controller.text.trim().isEmpty && _selected == null) {
      widget.onClose();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.focusNode.unfocus();
    setState(() => _showTabs = true);
    widget.onConfirm();
  }

  /// Style panel: same as AppBar Done — hide text bottom sheet.
  void _onCheck() {
    if (_isTyping) {
      _onKeyboardDone();
      return;
    }
    _commitTextIfNeeded();
    if (widget.controller.text.trim().isEmpty && _selected == null) {
      widget.onClose();
      return;
    }
    widget.focusNode.unfocus();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.project, widget.focusNode]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            // Parent AnimatedContainer may still be mid-size (64→280). Only
            // mount tabs once height can fit input + tabs + body.
            final tallEnough = constraints.maxHeight >= 160;
            final showPanel =
                _showTabs &&
                tallEnough &&
                !widget.compactKeyboardPhase &&
                !keyboardOpen &&
                !widget.focusNode.hasFocus;
            return ColoredBox(
              color: Colors.white,
              child: Column(
                children: [
                  _inputBar(typing: keyboardOpen || widget.focusNode.hasFocus),
                  if (showPanel) ...[_mainTabs(), Expanded(child: _tabBody())],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _inputBar({required bool typing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textInputAction: TextInputAction.done,
              onChanged: (v) {
                final o = _selected;
                if (o != null) {
                  widget.project.updateOverlay(o.copyWith(text: v));
                }
              },
              onSubmitted: (_) => _onKeyboardDone(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Enter text',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: const Color(0xFFF0F1F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          if (typing)
            // Keyboard-done key style (hide keyboard, keep sheet).
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Material(
                color: const Color(0xFF1A73E8),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _onKeyboardDone,
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.keyboard_alt_outlined,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _onCheck,
              icon: const Icon(Icons.check_rounded, size: 28),
              color: Colors.black87,
              tooltip: 'Done',
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
                padding: const EdgeInsets.symmetric(vertical: 5),
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
          tab(TextToolsMainTab.fontStyle, 'Font Style'),
          tab(TextToolsMainTab.colorStyle, 'Color Style'),
        ],
      ),
    );
  }

  Widget _tabBody() {
    return switch (_mainTab) {
      TextToolsMainTab.fontStyle => _fontGrid(),
      TextToolsMainTab.colorStyle => _colorStyleBody(),
    };
  }

  Widget _fontGrid() {
    final family = _selected?.fontFamily ?? '';
    final weight = _selected?.fontWeight ?? 700;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.25,
      ),
      itemCount: TextToolCatalog.fonts.length,
      itemBuilder: (context, i) {
        final f = TextToolCatalog.fonts[i];
        final on =
            (family == f.family && weight == f.weight) ||
            (i == 0 && family.isEmpty && (_selected == null || weight == 700));
        final previewFamily = TextOverlayPaint.resolvedFamily(
          f.family,
          weight: f.weight,
        );
        return GestureDetector(
          onTap: () {
            _ensureOverlay();
            _patch(
              (o) => o.copyWith(fontFamily: f.family, fontWeight: f.weight),
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              // color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: on ? textToolAccent : AppColors.border,
                width: on ? 2 : 1,
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  f.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: previewFamily,
                    fontWeight: TextOverlayPaint.weightOf(f.weight),
                    fontSize: 13,
                    color: on ? textToolAccent : AppColors.textDark,
                  ),
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
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: TextToolCatalog.colorPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = TextToolCatalog.colorPresets[i];
              final isNone = i == 0 || p.id == 'preset_none';
              return GestureDetector(
                onTap: () {
                  _ensureOverlay();
                  _patch(
                    (cur) => cur.copyWith(
                      colorArgb: p.colorArgb,
                      strokeColorArgb: isNone ? null : p.strokeColorArgb,
                      strokeWidth: isNone ? 0 : p.strokeWidth,
                      strokeDoubleColorArgb: null,
                      // Clear BG / shadow; apply gradient only when preset has one.
                      bgColorArgb: null,
                      bgOpacity: 0.15,
                      shadowColorArgb: null,
                      shadowBlur: 0,
                      shadowDistance: 0,
                      shadowOpacity: 0,
                      gradientEndArgb: isNone ? null : p.gradientEndArgb,
                      fontWeight: p.fontWeight,
                    ),
                  );
                },
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: isNone
                      ? const Icon(Icons.block, size: 26, color: Colors.black45)
                      : TextOverlayPaint.styledText(
                          p.copyWith(text: 'T'),
                          fontSize: 22,
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
                (cur) => cur.copyWith(colorArgb: c, gradientEndArgb: null),
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
                      (cur) =>
                          cur.copyWith(colorArgb: g.$1, gradientEndArgb: g.$2),
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
                              o?.colorArgb == g.$1 && o?.gradientEndArgb == g.$2
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
    final hasSingle = o?.strokeColorArgb != null && (o?.strokeWidth ?? 0) > 0.1;
    // CapCut thickness UI is 0–100; paint width = value / 10.
    final thicknessUi = ((o?.strokeWidth ?? 0) * 10).round().clamp(0, 100);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      children: [
        _strokeModeRow(
          label: 'Single',
          doubleMode: false,
          enabled: true,
          selectedColor: hasSingle ? o!.strokeColorArgb : null,
          noneSelected: !hasSingle,
        ),
        const SizedBox(height: 10),
        // Double unlocks only after Single color is chosen.
        _strokeModeRow(
          label: 'Double',
          doubleMode: true,
          enabled: hasSingle,
          selectedColor: hasSingle ? o!.strokeDoubleColorArgb : null,
          noneSelected: hasSingle && o!.strokeDoubleColorArgb == null,
        ),
        const SizedBox(height: 12),
        _sliderRow(
          'Thickness',
          thicknessUi,
          0,
          100,
          (v) => _patch(
            (cur) => cur.copyWith(
              strokeWidth: v / 10.0,
              strokeColorArgb:
                  cur.strokeColorArgb ?? (v > 0 ? 0xFF000000 : null),
            ),
          ),
        ),
      ],
    );
  }

  Widget _strokeModeRow({
    required String label,
    required bool doubleMode,
    required bool enabled,
    required int? selectedColor,
    required bool noneSelected,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 2),
                  _strokeModeGlyph(doubleMode: doubleMode),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _strokeSwatch(
                      child: const Icon(
                        Icons.block,
                        size: 18,
                        color: Colors.black45,
                      ),
                      selected: noneSelected,
                      onTap: () {
                        if (doubleMode) {
                          // Clear only outer (Double) layer.
                          _patch(
                            (cur) => cur.copyWith(strokeDoubleColorArgb: null),
                          );
                        } else {
                          // Clear Single + Double together.
                          _patch(
                            (cur) => cur.copyWith(
                              strokeColorArgb: null,
                              strokeDoubleColorArgb: null,
                              strokeWidth: 0,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _strokeSwatch(
                      child: const Icon(
                        Icons.colorize_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      gradient: true,
                      selected: false,
                      onTap: () {
                        const pick = 0xFFF44336;
                        if (doubleMode) {
                          _patch(
                            (cur) => cur.copyWith(
                              strokeDoubleColorArgb: pick,
                              strokeWidth: math.max(cur.strokeWidth, 4),
                            ),
                          );
                        } else {
                          _patch(
                            (cur) => cur.copyWith(
                              strokeColorArgb: pick,
                              strokeWidth: math.max(cur.strokeWidth, 4),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    for (final c in TextToolCatalog.strokeSwatches) ...[
                      _strokeSwatch(
                        color: Color(c),
                        selected: selectedColor == c,
                        onTap: () {
                          if (doubleMode) {
                            // Outer layer on top of existing Single color.
                            _patch(
                              (cur) => cur.copyWith(
                                strokeDoubleColorArgb: c,
                                strokeWidth: math.max(cur.strokeWidth, 4),
                              ),
                            );
                          } else {
                            // Inner Single layer (keeps Double if already set).
                            _patch(
                              (cur) => cur.copyWith(
                                strokeColorArgb: c,
                                strokeWidth: math.max(cur.strokeWidth, 4),
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strokeModeGlyph({required bool doubleMode}) {
    if (!doubleMode) {
      return const Text(
        'A',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Colors.black87,
        ),
      );
    }
    return SizedBox(
      width: 16,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'A',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.4
                ..color = Colors.black87,
            ),
          ),
          Text(
            'A',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.3
                ..color = Colors.white,
            ),
          ),
          const Text(
            'A',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _strokeSwatch({
    Color? color,
    Widget? child,
    bool gradient = false,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        _ensureOverlay();
        onTap();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient ? null : (color ?? Colors.white),
          gradient: gradient
              ? const SweepGradient(
                  colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ],
                )
              : null,
          border: Border.all(
            color: selected
                ? const Color(0xFFFF5CA8)
                : (color == const Color(0xFFFFFFFF)
                      ? AppColors.border
                      : Colors.black12),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: child,
      ),
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
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
        // const SizedBox(height: 10),
        // _labeledRow(
        //   'Alignment',
        //   Row(
        //     children: [
        //       for (final a in TextAlignMode.values)
        //         Padding(
        //           padding: const EdgeInsets.only(right: 8),
        //           child: _squareToggle(
        //             selected: (o?.align ?? TextAlignMode.center) == a,
        //             onTap: () => _patch((cur) => cur.copyWith(align: a)),
        //             child: Icon(switch (a) {
        //               TextAlignMode.left => Icons.format_align_left,
        //               TextAlignMode.center => Icons.format_align_center,
        //               TextAlignMode.right => Icons.format_align_right,
        //             }, size: 18),
        //           ),
        //         ),
        //     ],
        //   ),
        // ),
        const SizedBox(height: 8),
        // CapCut-style: center 0 = straight, ±100 = full circle. Snaps to 0 near center.
        _curveSliderRow(
          (o?.curve ?? 0).round().clamp(-100, 100),
          (v) => _patch((cur) => cur.copyWith(curve: v.toDouble())),
        ),
        _sliderRow(
          'Size',
          (o?.fontSize ?? 20).round().clamp(12, 96),
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
        // _sliderRow(
        //   'Line',
        //   (((o?.lineHeight ?? 1.2) - 0.8) * 50).round().clamp(0, 100),
        //   0,
        //   100,
        //   (v) => _patch((cur) => cur.copyWith(lineHeight: 0.8 + (v / 50))),
        // ),
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

  Widget _curveSliderRow(int value, ValueChanged<int> onChanged) {
    const snapZone = 6; // |v| <= 6 → lock to exact 0
    int snap(int v) => v.abs() <= snapZone ? 0 : v;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 72,
            child: Text(
              'Curve',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Visual center mark at 0.
                  IgnorePointer(
                    child: Container(
                      width: 2,
                      height: 12,
                      color: textToolAccent.withValues(alpha: 0.45),
                    ),
                  ),
                  Slider(
                    value: value.clamp(-100, 100).toDouble(),
                    min: -100,
                    max: 100,
                    onChanged: (v) {
                      _ensureOverlay();
                      final next = snap(v.round());
                      if (next == 0 && value != 0) {
                        HapticFeedback.selectionClick();
                      }
                      onChanged(next);
                    },
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: GestureDetector(
              onTap: () {
                _ensureOverlay();
                HapticFeedback.selectionClick();
                onChanged(0);
              },
              child: Text(
                '$value',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: value == 0 ? textToolAccent : AppColors.textDark,
                ),
              ),
            ),
          ),
        ],
      ),
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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
    this.onEditOverlay,
  });

  final SlideshowProject project;
  final String? selectedOverlayId;
  final ValueChanged<String?> onSelectedOverlayId;
  /// True while text bottom sheet is open.
  final bool editing;
  /// Opens text tools for the selected overlay (Edit handle).
  final ValueChanged<String>? onEditOverlay;

  @override
  State<LiveTextOverlaysLayer> createState() => _LiveTextOverlaysLayerState();
}

class _LiveTextOverlaysLayerState extends State<LiveTextOverlaysLayer> {
  String? _handleGestureId;
  Offset? _rotatePivotGlobal;
  double? _rotateStartAngle;
  double? _rotateStartRotation;
  double? _scaleStart;
  double? _scaleStartDist;

  SlideOverlay? _latest(String id) {
    return widget.project.overlays.where((e) => e.id == id).firstOrNull;
  }

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
                // Tap empty canvas → hide selection border (idle only).
                if (!widget.editing && widget.selectedOverlayId != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => widget.onSelectedOverlayId(null),
                    ),
                  ),
                for (final o in texts)
                  _positionedText(
                    o,
                    canvasW: w,
                    canvasH: h,
                    selected: widget.selectedOverlayId == o.id,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // Must keep handles inside Stack layout bounds — Flutter ignores taps on
  // children painted outside the Stack's size (clipBehavior does not help hits).
  static const _handleSlot = 36.0;

  Widget _positionedText(
    SlideOverlay o, {
    required double canvasW,
    required double canvasH,
    required bool selected,
  }) {
    final fontSize = o.fontSize * o.scale;
    final sheetOpen = widget.editing;
    final edge = selected ? _handleSlot / 2 : 0.0;
    return Positioned(
      left: o.nx * canvasW,
      top: o.ny * canvasH,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: o.rotation,
          child: Stack(
            children: [
              // Padding is the sizing child → Stack grows so corner slots hit-test.
              Padding(
                padding: EdgeInsets.all(edge),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onSelectedOverlayId(o.id),
                  onPanUpdate: selected
                      ? (d) {
                          if (_handleGestureId != null) return;
                          final latest = _latest(o.id);
                          if (latest == null) return;
                          widget.project.updateOverlay(
                            latest.copyWith(
                              nx: (latest.nx + d.delta.dx / canvasW)
                                  .clamp(0.05, 0.95),
                              ny: (latest.ny + d.delta.dy / canvasH)
                                  .clamp(0.05, 0.95),
                            ),
                          );
                        }
                      : null,
                  child: Container(
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
                ),
              ),
              if (selected) ...[
                // Idle selection: close + edit. Sheet open: hide those two.
                if (!sheetOpen) ...[
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _handleSlot,
                    height: _handleSlot,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.project.removeOverlay(o.id);
                          widget.onSelectedOverlayId(null);
                        },
                        child: _handleBtn(Icons.close_rounded),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    width: _handleSlot,
                    height: _handleSlot,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onEditOverlay?.call(o.id),
                        child: _handleBtn(Icons.edit_rounded),
                      ),
                    ),
                  ),
                ],
                Positioned(
                  left: 0,
                  bottom: 0,
                  width: _handleSlot,
                  height: _handleSlot,
                  child: Center(
                    child: _rotateHandle(
                      o.id,
                      canvasW: canvasW,
                      canvasH: canvasH,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: _handleSlot,
                  height: _handleSlot,
                  child: Center(
                    child: _resizeHandle(
                      o.id,
                      canvasW: canvasW,
                      canvasH: canvasH,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rotateHandle(
    String id, {
    required double canvasW,
    required double canvasH,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        final latest = _latest(id);
        if (latest == null) return;
        _handleGestureId = id;
        _rotateStartRotation = latest.rotation;
        _rotatePivotGlobal = Offset(
          latest.nx * canvasW,
          latest.ny * canvasH,
        );
        // Convert local handle drag start to angle around text center.
        // Use global position vs pivot approximated in overlay parent space.
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final globalPivot = box.localToGlobal(_rotatePivotGlobal!);
        _rotateStartAngle = math.atan2(
          d.globalPosition.dy - globalPivot.dy,
          d.globalPosition.dx - globalPivot.dx,
        );
      },
      onPanUpdate: (d) {
        final latest = _latest(id);
        if (latest == null ||
            _rotateStartAngle == null ||
            _rotateStartRotation == null ||
            _rotatePivotGlobal == null) {
          return;
        }
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final globalPivot = box.localToGlobal(_rotatePivotGlobal!);
        final angle = math.atan2(
          d.globalPosition.dy - globalPivot.dy,
          d.globalPosition.dx - globalPivot.dx,
        );
        final delta = angle - _rotateStartAngle!;
        widget.project.updateOverlay(
          latest.copyWith(rotation: _rotateStartRotation! + delta),
        );
      },
      onPanEnd: (_) => _clearHandleGesture(),
      onPanCancel: _clearHandleGesture,
      child: _handleBtn(Icons.rotate_right_rounded),
    );
  }

  Widget _resizeHandle(
    String id, {
    required double canvasW,
    required double canvasH,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) {
        final latest = _latest(id);
        if (latest == null) return;
        _handleGestureId = id;
        _scaleStart = latest.scale;
        final pivot = Offset(latest.nx * canvasW, latest.ny * canvasH);
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final globalPivot = box.localToGlobal(pivot);
        _scaleStartDist = (d.globalPosition - globalPivot).distance
            .clamp(12.0, 10000.0);
      },
      onPanUpdate: (d) {
        final latest = _latest(id);
        if (latest == null ||
            _scaleStart == null ||
            _scaleStartDist == null) {
          return;
        }
        final pivot = Offset(latest.nx * canvasW, latest.ny * canvasH);
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final globalPivot = box.localToGlobal(pivot);
        final dist = (d.globalPosition - globalPivot).distance
            .clamp(12.0, 10000.0);
        final next = (_scaleStart! * (dist / _scaleStartDist!))
            .clamp(0.35, 5.0)
            .toDouble();
        widget.project.updateOverlay(latest.copyWith(scale: next));
      },
      onPanEnd: (_) => _clearHandleGesture(),
      onPanCancel: _clearHandleGesture,
      child: _handleBtn(Icons.open_in_full_rounded),
    );
  }

  void _clearHandleGesture() {
    _handleGestureId = null;
    _rotatePivotGlobal = null;
    _rotateStartAngle = null;
    _rotateStartRotation = null;
    _scaleStart = null;
    _scaleStartDist = null;
  }

  Widget _handleBtn(IconData icon) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}
