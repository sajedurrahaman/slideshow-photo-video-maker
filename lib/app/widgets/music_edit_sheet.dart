import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'editTool_sheet.dart';

/// CapCut-style music cut sheet (waveform + Fade In/Out) — slideshow parity.
class MusicEditSheet extends StatefulWidget {
  const MusicEditSheet({
    super.key,
    required this.music,
    required this.onClose,
    required this.onSave,
  });

  final MusicTrack music;
  final VoidCallback onClose;
  final void Function(MusicTrack updated) onSave;

  @override
  State<MusicEditSheet> createState() => _MusicEditSheetState();
}

class _MusicEditSheetState extends State<MusicEditSheet> {
  static const _peach = ui.Color(0xFFD5D2CF);
  static const _waveHMax = 44.0;
  static const _minClip = 1.0;
  static const _handleHit = 28.0;
  static const _titleH = 34.0;

  late double _clipStart;
  late double _clipEnd;
  late bool _fadeIn;
  late bool _fadeOut;
  late bool _hadCustomClipEnd;
  double _trackDur = 0;
  bool _loadingDur = true;

  @override
  void initState() {
    super.initState();
    final m = widget.music;
    _clipStart = m.clipStartSec;
    _fadeIn = m.fadeIn;
    _fadeOut = m.fadeOut;
    _hadCustomClipEnd = m.clipEndSec != null;
    final known = m.duration?.inMilliseconds;
    if (known != null && known > 0) {
      _trackDur = known / 1000.0;
      _clipEnd = (m.clipEndSec ?? _trackDur).clamp(
        _clipStart + _minClip,
        _trackDur,
      );
      _loadingDur = false;
    } else {
      _clipEnd = m.clipEndSec ?? 0;
    }
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final m = widget.music;
    final player = AudioPlayer();
    try {
      final Duration? d = m.isAsset
          ? await player.setAsset(m.path)
          : await player.setFilePath(m.path);
      final resolved = d ?? player.duration;
      if (resolved != null && resolved.inMilliseconds > 0 && mounted) {
        setState(() {
          _trackDur = resolved.inMilliseconds / 1000.0;
          if (!_hadCustomClipEnd) {
            _clipEnd = _trackDur;
          } else {
            _clipEnd = _clipEnd.clamp(_clipStart + _minClip, _trackDur);
          }
          _clipStart = _clipStart.clamp(
            0.0,
            math.max(0.0, _clipEnd - _minClip),
          );
          _loadingDur = false;
        });
      } else if (mounted) {
        setState(() {
          if (_trackDur <= 0) _trackDur = 60;
          if (!_hadCustomClipEnd) _clipEnd = _trackDur;
          _loadingDur = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_trackDur <= 0) _trackDur = 60;
          if (!_hadCustomClipEnd) _clipEnd = _trackDur;
          _loadingDur = false;
        });
      }
    } finally {
      await player.dispose();
    }
  }

  String _fmt(double sec) {
    final s = sec.clamp(0, 35999).floor();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  void _commit() {
    widget.onSave(
      widget.music.copyWith(
        clipStartSec: _clipStart,
        clipEndSec: _clipEnd,
        fadeIn: _fadeIn,
        fadeOut: _fadeOut,
        duration: Duration(milliseconds: (_trackDur * 1000).round()),
      ),
    );
  }

  double _secToX(double sec, double width) {
    if (_trackDur <= 0) return 0;
    return (sec / _trackDur) * width;
  }

  void _dragHandle({
    required bool isStart,
    required double dx,
    required double width,
  }) {
    if (width <= 0 || _trackDur <= 0) return;
    final dSec = (dx / width) * _trackDur;
    setState(() {
      if (isStart) {
        _clipStart = (_clipStart + dSec).clamp(0.0, _clipEnd - _minClip);
      } else {
        _clipEnd = (_clipEnd + dSec).clamp(_clipStart + _minClip, _trackDur);
      }
    });
  }

  Widget _fadeToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 24,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: value ? AppColors.primaryGradient : null,
              color: value ? null : const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value ? AppColors.primaryEnd : const Color(0xFFD0D0D0),
              ),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: value ? AppColors.primaryEnd : const Color(0xFFBFBFBF),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cutHandle({
    required bool isStart,
    required double width,
    required double waveH,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) =>
          _dragHandle(isStart: isStart, dx: d.delta.dx, width: width),
      child: SizedBox(
        width: _handleHit,
        height: waveH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 2, height: waveH, color: Colors.white),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.primaryGradient,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cutContainer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const timeH = 14.0;
        const gap = 2.0;
        final maxWave = constraints.hasBoundedHeight
            ? (constraints.maxHeight - timeH - gap).clamp(24.0, _waveHMax)
            : _waveHMax;
        final waveH = maxWave.toDouble();
        final startX = _secToX(_clipStart, w);
        final endX = _secToX(_clipEnd, w);
        const timeStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
          height: 1.0,
        );

        return SizedBox(
          width: w,
          height: timeH + gap + waveH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: timeH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (startX - 16).clamp(0.0, math.max(0.0, w - 36)),
                      child: Text(_fmt(_clipStart), style: timeStyle),
                    ),
                    Positioned(
                      left: (endX - 16).clamp(0.0, math.max(0.0, w - 36)),
                      child: Text(_fmt(_clipEnd), style: timeStyle),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              SizedBox(
                height: waveH,
                width: w,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _peach,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CustomPaint(
                          painter: _MusicEditWavePainter(
                            startSec: _clipStart,
                            endSec: _clipEnd,
                            totalSec: _trackDur,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: startX - _handleHit / 2,
                      top: 0,
                      bottom: 0,
                      child: _cutHandle(isStart: true, width: w, waveH: waveH),
                    ),
                    Positioned(
                      left: endX - _handleHit / 2,
                      top: 0,
                      bottom: 0,
                      child: _cutHandle(isStart: false, width: w, waveH: waveH),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: _titleH,
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                ),
                Expanded(child: SheetTitle(music.title)),
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
                  child: TealPillButton(label: 'Save', onPressed: _commit),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Column(
                children: [
                  Expanded(
                    child: _loadingDur
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _cutContainer(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _fadeToggle(
                        label: 'Fade In',
                        value: _fadeIn,
                        onChanged: (v) => setState(() => _fadeIn = v),
                      ),
                      _fadeToggle(
                        label: 'Fade Out',
                        value: _fadeOut,
                        onChanged: (v) => setState(() => _fadeOut = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicEditWavePainter extends CustomPainter {
  _MusicEditWavePainter({
    required this.startSec,
    required this.endSec,
    required this.totalSec,
  });

  final double startSec;
  final double endSec;
  final double totalSec;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSec <= 0 || size.width <= 0) return;
    final startX = (startSec / totalSec) * size.width;
    final endX = (endSec / totalSec) * size.width;
    final bars = math.max(40, (size.width / 4).floor());
    final inactive = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars; i++) {
      final t = bars == 1 ? 0.0 : i / (bars - 1);
      final x = t * size.width;
      final wave =
          math.sin(t * math.pi * 9.5) * 0.38 +
          math.sin(t * math.pi * 3.1 + 0.6) * 0.32 +
          math.sin(t * math.pi * 15 + 1.2) * 0.12 +
          0.48;
      final h = (8.0 + wave.clamp(0.2, 1.0) * (size.height - 16)).clamp(
        8.0,
        size.height - 6,
      );
      final y0 = (size.height - h) / 2;
      final y1 = (size.height + h) / 2;
      final active = x >= startX && x <= endX;
      if (active) {
        final paint = Paint()
          ..shader = AppColors.primaryGradient.createShader(
            Rect.fromLTWH(x - 1, y0, 3, h),
          )
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y0), Offset(x, y1), paint);
      } else {
        canvas.drawLine(Offset(x, y0), Offset(x, y1), inactive);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MusicEditWavePainter old) =>
      old.startSec != startSec ||
      old.endSec != endSec ||
      old.totalSec != totalSec;
}
