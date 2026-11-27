import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_theme.dart';

/// Per-clip crop/rotate from CapCut-style Resize page.
class VideoClipCrop {
  const VideoClipCrop({
    this.left = 0,
    this.top = 0,
    this.width = 1,
    this.height = 1,
    this.degrees = 0,
    this.aspectRatio,
    this.presetId = 'custom',
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double degrees;
  final double? aspectRatio;
  final String presetId;

  bool get isIdentity =>
      left.abs() < 0.001 &&
      top.abs() < 0.001 &&
      (width - 1).abs() < 0.001 &&
      (height - 1).abs() < 0.001 &&
      degrees.abs() < 0.5;

  VideoClipCrop copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
    double? degrees,
    double? aspectRatio,
    bool clearAspect = false,
    String? presetId,
  }) {
    return VideoClipCrop(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      degrees: degrees ?? this.degrees,
      aspectRatio: clearAspect ? null : (aspectRatio ?? this.aspectRatio),
      presetId: presetId ?? this.presetId,
    );
  }
}

enum _Grip { move, tl, tr, bl, br, top, right, bottom, left }

class _RatioChoice {
  const _RatioChoice(this.id, this.label, this.ratio);
  final String id;
  final String label;
  final double? ratio;
}

const _ratios = <_RatioChoice>[
  _RatioChoice('custom', 'Custom', null),
  _RatioChoice('9-16', '9:16', 9 / 16),
  _RatioChoice('16-9', '16:9', 16 / 9),
  _RatioChoice('1-1', '1:1', 1),
  _RatioChoice('4-3', '4:3', 4 / 3),
  _RatioChoice('3-4', '3:4', 3 / 4),
];

/// CapCut-style dark Resize page for a video clip.
class VideoResizeScreen extends StatefulWidget {
  const VideoResizeScreen({
    super.key,
    required this.videoPath,
    this.initial,
  });

  final String videoPath;
  final VideoClipCrop? initial;

  @override
  State<VideoResizeScreen> createState() => _VideoResizeScreenState();
}

class _VideoResizeScreenState extends State<VideoResizeScreen> {
  static const _previewBg = Color(0xFF1C1C1E);
  static const _chip = Color(0xFFF2F2F7);
  static const _teal = AppColors.primary;

  VideoPlayerController? _controller;
  bool _ready = false;
  double _videoW = 1;
  double _videoH = 1;

  double _left = 0;
  double _top = 0;
  double _width = 1;
  double _height = 1;
  double _degrees = 0;
  double? _aspect;
  String _presetId = 'custom';

  _Grip? _grip;

  double _boxW = 1;
  double _boxH = 1;
  Rect _cropView = Rect.zero;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _left = init.left;
      _top = init.top;
      _width = init.width;
      _height = init.height;
      _degrees = init.degrees;
      _aspect = init.aspectRatio;
      _presetId = init.presetId;
    }
    unawaited(_openPlayer());
  }

  Future<void> _openPlayer() async {
    final c = VideoPlayerController.file(File(widget.videoPath));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      c.addListener(_onTick);
      setState(() {
        _videoW = c.value.size.width <= 0 ? 1 : c.value.size.width;
        _videoH = c.value.size.height <= 0 ? 1 : c.value.size.height;
        _duration = c.value.duration;
        _position = c.value.position;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _onTick() {
    final c = _controller;
    if (!mounted || c == null || _scrubbing) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    if (pos != _position || dur != _duration) {
      setState(() {
        _position = pos;
        _duration = dur;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _selectRatio(_RatioChoice choice) {
    setState(() {
      _presetId = choice.id;
      _aspect = choice.ratio;
      final ratio = choice.ratio;
      if (ratio == null || _videoW <= 0 || _videoH <= 0) return;
      final imgAspect = _videoW / _videoH;
      late final double nw;
      late final double nh;
      if (imgAspect > ratio) {
        nw = 1;
        nh = imgAspect / ratio;
      } else {
        nh = 1;
        nw = ratio / imgAspect;
      }
      _left = (1 - nw) / 2;
      _top = (1 - nh) / 2;
      _width = nw;
      _height = nh;
    });
  }

  void _reset() {
    setState(() {
      _left = 0;
      _top = 0;
      _width = 1;
      _height = 1;
      _degrees = 0;
      _aspect = null;
      _presetId = 'custom';
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      VideoClipCrop(
        left: _left,
        top: _top,
        width: _width,
        height: _height,
        degrees: _degrees,
        aspectRatio: _aspect,
        presetId: _presetId,
      ),
    );
  }

  _Grip? _hit(Offset local) {
    final rect = _cropView;
    const reach = 28.0;
    final corners = <_Grip, Offset>{
      _Grip.tl: rect.topLeft,
      _Grip.tr: rect.topRight,
      _Grip.bl: rect.bottomLeft,
      _Grip.br: rect.bottomRight,
    };
    for (final e in corners.entries) {
      if ((local - e.value).distance <= reach) return e.key;
    }
    const edge = 22.0;
    final insideX =
        local.dx >= rect.left - edge && local.dx <= rect.right + edge;
    final insideY =
        local.dy >= rect.top - edge && local.dy <= rect.bottom + edge;
    if ((local.dy - rect.top).abs() <= edge && insideX) return _Grip.top;
    if ((local.dy - rect.bottom).abs() <= edge && insideX) {
      return _Grip.bottom;
    }
    if ((local.dx - rect.left).abs() <= edge && insideY) return _Grip.left;
    if ((local.dx - rect.right).abs() <= edge && insideY) return _Grip.right;
    if (rect.inflate(6).contains(local)) return _Grip.move;
    return null;
  }

  void _onPanStart(DragStartDetails d) => _grip = _hit(d.localPosition);

  void _onPanUpdate(DragUpdateDetails d) {
    final grip = _grip;
    if (grip == null || _boxW <= 0 || _boxH <= 0) return;
    final dx = d.delta.dx / _boxW;
    final dy = d.delta.dy / _boxH;
    setState(() {
      if (grip == _Grip.move) {
        _left = (_left + dx).clamp(-2.0, 3.0 - _width);
        _top = (_top + dy).clamp(-2.0, 3.0 - _height);
      } else if (_aspect == null) {
        _resizeFree(grip, dx, dy);
      } else {
        _resizeLocked(grip, dx, dy);
      }
    });
  }

  void _resizeFree(_Grip grip, double dx, double dy) {
    var l = _left;
    var t = _top;
    var r = _left + _width;
    var b = _top + _height;
    if (grip == _Grip.tl || grip == _Grip.bl || grip == _Grip.left) l += dx;
    if (grip == _Grip.tr || grip == _Grip.br || grip == _Grip.right) r += dx;
    if (grip == _Grip.tl || grip == _Grip.tr || grip == _Grip.top) t += dy;
    if (grip == _Grip.bl || grip == _Grip.br || grip == _Grip.bottom) b += dy;
    l = l.clamp(-2.0, r - 0.12);
    r = r.clamp(l + 0.12, 3.0);
    t = t.clamp(-2.0, b - 0.12);
    b = b.clamp(t + 0.12, 3.0);
    _left = l;
    _top = t;
    _width = r - l;
    _height = b - t;
  }

  void _resizeLocked(_Grip grip, double dx, double dy) {
    final aspect = _aspect;
    if (aspect == null) return;
    final imgAspect = _videoW / _videoH;
    final anchorRight =
        grip == _Grip.tl || grip == _Grip.bl || grip == _Grip.left;
    final anchorBottom =
        grip == _Grip.tl || grip == _Grip.tr || grip == _Grip.top;
    final ax = anchorRight ? _left + _width : _left;
    final ay = anchorBottom ? _top + _height : _top;
    var nw = _width + (anchorRight ? -dx : dx);
    var nh = _height + (anchorBottom ? -dy : dy);
    if (dx.abs() >= dy.abs()) {
      nw = nw.clamp(0.12, 4.0);
      nh = nw * imgAspect / aspect;
    } else {
      nh = nh.clamp(0.12, 4.0);
      nw = nh * aspect / imgAspect;
    }
    nw = nw.clamp(0.12, 4.0);
    nh = nh.clamp(0.12, 4.0);
    var l = anchorRight ? ax - nw : ax;
    var t = anchorBottom ? ay - nh : ay;
    l = l.clamp(-2.0, 3.0 - nw);
    t = t.clamp(-2.0, 3.0 - nh);
    _left = l;
    _top = t;
    _width = nw;
    _height = nh;
  }

  double _coverScale() {
    final rad = _degrees.abs() * math.pi / 180;
    final c = math.cos(rad);
    final s = math.sin(rad);
    final w = _videoW;
    final h = _videoH;
    if (w <= 0 || h <= 0) return 1;
    return math.max((w * c + h * s) / w, (w * s + h * c) / h);
  }

  Rect _fittedCrop(Size space) {
    final cropPxW = math.max(_width * _videoW, 1);
    final cropPxH = math.max(_height * _videoH, 1);
    var w = space.width;
    var h = w * cropPxH / cropPxW;
    if (h > space.height) {
      h = space.height;
      w = h * cropPxW / cropPxH;
    }
    return Rect.fromLTWH((space.width - w) / 2, (space.height - h) / 2, w, h);
  }

  Rect _videoInside(Rect crop, double imageW, double imageH) {
    final zoom = math.max(_width, _height);
    if (zoom <= 1.001) {
      return Rect.fromLTWH(
        crop.left - _left * imageW,
        crop.top - _top * imageH,
        imageW,
        imageH,
      );
    }
    final fittedW = imageW * zoom;
    final fittedH = imageH * zoom;
    return Rect.fromLTWH(
      crop.left + (crop.width - fittedW) / 2,
      crop.top + (crop.height - fittedH) / 2,
      fittedW,
      fittedH,
    );
  }

  String _fmt(Duration d) {
    final s = d.inMilliseconds ~/ 1000;
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  Future<void> _seekFrac(double t) async {
    final c = _controller;
    if (c == null || !_ready) return;
    final ms = (c.value.duration.inMilliseconds * t.clamp(0.0, 1.0)).round();
    await c.seekTo(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(child: _previewStage()),
              // App-theme white bottom sheet (rotate / ratio / reset).
              Material(
                color: Colors.white,
                elevation: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1, color: AppColors.border),
                    _scrubber(),
                    _rotateRow(),
                    _aspectRow(),
                    _bottomReset(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Material(
      color: Colors.white,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: AppColors.textDark),
            ),
            const Expanded(
              child: Text(
                'Crop',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: _ready ? _confirm : null,
              icon: Icon(
                Icons.check,
                color: _ready ? _teal : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewStage() {
    final c = _controller;
    if (!_ready || c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: _previewBg,
        child: Center(
          child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
        ),
      );
    }
    return ColoredBox(
      color: _previewBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final space = Size(
            math.max(constraints.maxWidth - 28, 1),
            math.max(constraints.maxHeight - 28, 1),
          );
          final crop = _fittedCrop(space).shift(const Offset(14, 14));
          final imageW = crop.width / _width;
          final imageH = crop.height / _height;
          final image = _videoInside(crop, imageW, imageH);
          _boxW = imageW;
          _boxH = imageH;
          _cropView = crop;

          return GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: (_) => _grip = null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: crop,
                  child: const ColoredBox(color: Colors.black),
                ),
                ClipRect(
                  clipper: _RectClipper(crop),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fromRect(
                        rect: image,
                        child: Transform.scale(
                          scale: _coverScale(),
                          child: Transform.rotate(
                            angle: _degrees * math.pi / 180,
                            child: VideoPlayer(c),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                CustomPaint(painter: _CropGridPainter(crop)),
                for (final corner in [
                  (crop.topLeft, Alignment.topLeft),
                  (crop.topRight, Alignment.topRight),
                  (crop.bottomLeft, Alignment.bottomLeft),
                  (crop.bottomRight, Alignment.bottomRight),
                ])
                  Positioned(
                    left: corner.$1.dx - 14,
                    top: corner.$1.dy - 14,
                    child: CustomPaint(
                      size: const Size(28, 28),
                      painter: _CornerHandlePainter(corner.$2),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scrubber() {
    final totalMs = math.max(1, _duration.inMilliseconds);
    final t = (_position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Text(
            _fmt(_position),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: _teal,
                inactiveTrackColor: AppColors.border,
                thumbColor: _teal,
              ),
              child: Slider(
                value: t.toDouble(),
                onChangeStart: (_) {
                  _scrubbing = true;
                  unawaited(_controller?.pause());
                },
                onChanged: (v) {
                  setState(() {
                    _position = Duration(milliseconds: (totalMs * v).round());
                  });
                },
                onChangeEnd: (v) async {
                  await _seekFrac(v);
                  _scrubbing = false;
                },
              ),
            ),
          ),
          Text(
            _fmt(_duration),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _rotateRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Rotate',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_degrees.round()}°',
                style: const TextStyle(
                  color: _teal,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pxPerDegree = constraints.maxWidth / 90;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    if (pxPerDegree <= 0) return;
                    final next = (_degrees - d.delta.dx / pxPerDegree)
                        .clamp(-45.0, 45.0);
                    setState(() => _degrees = next.roundToDouble());
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(constraints.maxWidth, 44),
                        painter: _RotateRulerPainter(degrees: _degrees),
                      ),
                      Container(
                        width: 2,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _teal,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _aspectRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Aspect ratio',
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _ratios.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final choice = _ratios[i];
                final selected = choice.id == _presetId;
                return GestureDetector(
                  onTap: () => _selectRatio(choice),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _chip,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? _teal : AppColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: _RatioIcon(
                            ratio: choice.ratio,
                            color: selected
                                ? AppColors.textDark
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        choice.label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textDark
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomReset() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _reset,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Reset',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RectClipper extends CustomClipper<Rect> {
  _RectClipper(this.rect);
  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _RectClipper oldClipper) => oldClipper.rect != rect;
}

class _CropGridPainter extends CustomPainter {
  _CropGridPainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, p);
    // Rule of thirds
    final dx = rect.width / 3;
    final dy = rect.height / 3;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(
        Offset(rect.left + dx * i, rect.top),
        Offset(rect.left + dx * i, rect.bottom),
        p,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top + dy * i),
        Offset(rect.right, rect.top + dy * i),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CornerHandlePainter extends CustomPainter {
  _CornerHandlePainter(this.corner);
  final Alignment corner;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    const arm = 12.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    if (corner == Alignment.topLeft) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm, cy), p);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm), p);
    } else if (corner == Alignment.topRight) {
      canvas.drawLine(Offset(cx, cy), Offset(cx - arm, cy), p);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + arm), p);
    } else if (corner == Alignment.bottomLeft) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + arm, cy), p);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy - arm), p);
    } else {
      canvas.drawLine(Offset(cx, cy), Offset(cx - arm, cy), p);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy - arm), p);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerHandlePainter oldDelegate) =>
      oldDelegate.corner != corner;
}

class _RotateRulerPainter extends CustomPainter {
  _RotateRulerPainter({required this.degrees});
  final double degrees;

  @override
  void paint(Canvas canvas, Size size) {
    final major = Paint()
      ..color = const Color(0xFFB0B0B5)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = const Color(0xFFD0D0D5)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // Visible window ±45° around current; center needle = current degrees.
    const range = 45.0;
    final pxPerDegree = size.width / (range * 2);
    final cy = size.height * 0.35;

    for (var d = -90; d <= 90; d++) {
      final x = size.width / 2 + (d - degrees) * pxPerDegree;
      if (x < -4 || x > size.width + 4) continue;
      final isMajor = d % 10 == 0;
      final h = isMajor ? 16.0 : (d % 5 == 0 ? 11.0 : 7.0);
      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        isMajor ? major : minor,
      );
      if (isMajor && d.abs() <= 45) {
        final tp = TextPainter(
          text: TextSpan(text: '${d.abs()}°', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, cy + 12));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RotateRulerPainter oldDelegate) =>
      oldDelegate.degrees != degrees;
}

class _RatioIcon extends StatelessWidget {
  const _RatioIcon({required this.ratio, required this.color});
  final double? ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (ratio == null) {
      // Custom — four corner brackets
      return SizedBox(
        width: 22,
        height: 22,
        child: CustomPaint(painter: _CustomRatioPainter(color)),
      );
    }
    const max = 22.0;
    late final double w;
    late final double h;
    if (ratio! >= 1) {
      w = max;
      h = max / ratio!;
    } else {
      h = max;
      w = max * ratio!;
    }
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.6),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _CustomRatioPainter extends CustomPainter {
  _CustomRatioPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    const a = 7.0;
    // TL
    canvas.drawLine(Offset.zero, const Offset(a, 0), p);
    canvas.drawLine(Offset.zero, const Offset(0, a), p);
    // TR
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - a, 0), p);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, a), p);
    // BL
    canvas.drawLine(Offset(0, size.height), Offset(a, size.height), p);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - a), p);
    // BR
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - a, size.height),
      p,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - a),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _CustomRatioPainter oldDelegate) =>
      oldDelegate.color != color;
}
