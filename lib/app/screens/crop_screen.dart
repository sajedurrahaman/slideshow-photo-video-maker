import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _RatioMark { free, square, fourFive, story, wide, threeFour, fourThree }

class _RatioChoice {
  const _RatioChoice(this.id, this.label, this.ratio, this.mark);
  final String id;
  final String label;
  final double? ratio;
  final _RatioMark mark;
}

const _ratios = <_RatioChoice>[
  _RatioChoice('free', 'Free', null, _RatioMark.free),
  _RatioChoice('1-1', '1:1', 1, _RatioMark.square),
  _RatioChoice('4-5', '4:5', 4 / 5, _RatioMark.fourFive),
  _RatioChoice('9-16', '9:16', 9 / 16, _RatioMark.story),
  _RatioChoice('16-9', '16:9', 16 / 9, _RatioMark.wide),
  _RatioChoice('3-4', '3:4', 3 / 4, _RatioMark.threeFour),
  _RatioChoice('4-3', '4:3', 4 / 3, _RatioMark.fourThree),
  _RatioChoice('2-3', '2:3', 2 / 3, _RatioMark.threeFour),
  _RatioChoice('3-2', '3:2', 3 / 2, _RatioMark.fourThree),
  _RatioChoice('1-2', '1:2', 0.5, _RatioMark.story),
  _RatioChoice('2-1', '2:1', 2, _RatioMark.wide),
];

const _cyan = Color(0xFF00C6D7);
const _scaleYellow = Color(0xFFD6E04A);

enum _Grip { move, tl, tr, bl, br, top, right, bottom, left }

class _CropScreenState extends State<CropScreen> {
  String? _path;
  int? _index;
  double _imgW = 1;
  double _imgH = 1;
  bool _ready = false;

  double _left = 0;
  double _top = 0;
  double _width = 1;
  double _height = 1;
  double _degrees = 0;
  double? _aspect;
  double? _pendingAspect;
  String _presetId = 'free';

  double _boxW = 1;
  double _boxH = 1;
  Rect _cropView = Rect.zero;
  _Grip? _grip;

  @override
  void initState() {
    super.initState();
    final project = context.read<SlideshowProject>();
    final index = project.selectedPhotoIndex;
    if (index == null || index >= project.photos.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
      return;
    }
    final photo = project.photos[index];
    _index = index;
    _path = photo.path;
    _left = photo.cropLeft.clamp(-2.0, 2.0);
    _top = photo.cropTop.clamp(-2.0, 2.0);
    _width = photo.cropWidth.clamp(0.12, 4.0);
    _height = photo.cropHeight.clamp(0.12, 4.0);
    _degrees = photo.cropDegrees.clamp(-45, 45);
    if (photo.cropWidth > 0.999 &&
        photo.cropHeight > 0.999 &&
        photo.cropAspectRatio != null) {
      _pendingAspect = photo.cropAspectRatio;
    }
    _loadSize(photo.path);
  }

  _RatioChoice? _presetForRatio(double ratio) {
    for (final choice in _ratios) {
      final value = choice.ratio;
      if (value != null && (value - ratio).abs() < 0.04) return choice;
    }
    return null;
  }

  Future<void> _loadSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _imgW = image.width.toDouble();
        _imgH = image.height.toDouble();
        _ready = true;
        final pending = _pendingAspect;
        if (pending != null) {
          _select(_presetForRatio(pending) ?? _ratios.first);
        } else if (_width < 0.999 || _height < 0.999) {
          final pixel = (_width * _imgW) / (_height * _imgH);
          final match = _presetForRatio(pixel);
          _presetId = match?.id ?? 'free';
          _aspect = match?.ratio;
        }
      });
      image.dispose();
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _select(_RatioChoice choice) {
    _presetId = choice.id;
    _aspect = choice.ratio;
    final ratio = choice.ratio;
    if (ratio == null || _imgW <= 0 || _imgH <= 0) return;
    final imgAspect = _imgW / _imgH;
    late double nw;
    late double nh;
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
  }

  void _reset() {
    setState(() {
      _left = 0;
      _top = 0;
      _width = 1;
      _height = 1;
      _degrees = 0;
      _aspect = null;
      _presetId = 'free';
    });
  }

  void _confirm() {
    final index = _index;
    if (index != null) {
      final project = context.read<SlideshowProject>();
      if (index < project.photos.length) {
        // Bake in background on Crop Done — final timeline Done stays fast.
        project.updatePhoto(
          index,
          project.photos[index].copyWith(
            cropLeft: _left,
            cropTop: _top,
            cropWidth: _width,
            cropHeight: _height,
            cropDegrees: _degrees,
            clearCropAspectRatio: true,
          ),
          bakePreview: true,
        );
      }
    }
    context.pop();
  }

  Offset _toImage(Offset delta) => delta;

  _Grip? _hit(Offset local) {
    final rect = _cropView;
    const reach = 28.0;
    final corners = <_Grip, Offset>{
      _Grip.tl: rect.topLeft,
      _Grip.tr: rect.topRight,
      _Grip.bl: rect.bottomLeft,
      _Grip.br: rect.bottomRight,
    };
    for (final entry in corners.entries) {
      if ((local - entry.value).distance <= reach) return entry.key;
    }
    const edge = 24.0;
    final insideX =
        local.dx >= rect.left - edge && local.dx <= rect.right + edge;
    final insideY =
        local.dy >= rect.top - edge && local.dy <= rect.bottom + edge;
    if ((local.dy - rect.top).abs() <= edge && insideX) return _Grip.top;
    if ((local.dy - rect.bottom).abs() <= edge && insideX) return _Grip.bottom;
    if ((local.dx - rect.left).abs() <= edge && insideY) return _Grip.left;
    if ((local.dx - rect.right).abs() <= edge && insideY) return _Grip.right;
    if (rect.inflate(6).contains(local)) return _Grip.move;
    return null;
  }

  void _onPanStart(DragStartDetails details) {
    _grip = _hit(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final grip = _grip;
    if (grip == null || _boxW <= 0 || _boxH <= 0) return;
    final local = _toImage(details.delta);
    final dx = local.dx / _boxW;
    final dy = local.dy / _boxH;
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
    if (grip == _Grip.top ||
        grip == _Grip.bottom ||
        grip == _Grip.left ||
        grip == _Grip.right) {
      _resizeLockedEdge(grip, dx, dy, aspect);
      return;
    }
    final anchorRight = grip == _Grip.tl || grip == _Grip.bl;
    final anchorBottom = grip == _Grip.tl || grip == _Grip.tr;
    final ax = anchorRight ? _left + _width : _left;
    final ay = anchorBottom ? _top + _height : _top;
    final imgAspect = _imgW / _imgH;
    var nw = _width + (anchorRight ? -dx : dx);
    var nh = _height + (anchorBottom ? -dy : dy);
    if (dx.abs() >= dy.abs()) {
      nw = nw.clamp(0.12, 4.0);
      nh = nw * imgAspect / aspect;
    } else {
      nh = nh.clamp(0.12, 4.0);
      nw = nh * aspect / imgAspect;
    }
    if (nh > 4) {
      nh = 4;
      nw = nh * aspect / imgAspect;
    }
    if (nw > 4) {
      nw = 4;
      nh = nw * imgAspect / aspect;
    }
    var l = anchorRight ? ax - nw : ax;
    var t = anchorBottom ? ay - nh : ay;
    if (l < -2) l = -2;
    if (t < -2) t = -2;
    if (l + nw > 3) l = 3 - nw;
    if (t + nh > 3) t = 3 - nh;
    _left = l;
    _top = t;
    _width = nw;
    _height = nh;
  }

  void _resizeLockedEdge(_Grip grip, double dx, double dy, double aspect) {
    final imgAspect = _imgW / _imgH;
    final horizontal = grip == _Grip.left || grip == _Grip.right;
    var nw = _width;
    var nh = _height;
    if (horizontal) {
      nw = (_width + (grip == _Grip.left ? -dx : dx)).clamp(0.12, 4.0);
      nh = nw * imgAspect / aspect;
    } else {
      nh = (_height + (grip == _Grip.top ? -dy : dy)).clamp(0.12, 4.0);
      nw = nh * aspect / imgAspect;
    }
    if (nh > 4) {
      nh = 4;
      nw = nh * aspect / imgAspect;
    }
    if (nw > 4) {
      nw = 4;
      nh = nw * imgAspect / aspect;
    }
    final l = switch (grip) {
      _Grip.left => _left + _width - nw,
      _Grip.right => _left,
      _ => _left + (_width - nw) / 2,
    };
    final t = switch (grip) {
      _Grip.top => _top + _height - nh,
      _Grip.bottom => _top,
      _ => _top + (_height - nh) / 2,
    };
    _left = l.clamp(-2.0, 3.0 - nw);
    _top = t.clamp(-2.0, 3.0 - nh);
    _width = nw;
    _height = nh;
  }

  double _coverScale() {
    final rad = _degrees.abs() * math.pi / 180;
    final c = math.cos(rad);
    final s = math.sin(rad);
    final w = _imgW;
    final h = _imgH;
    if (w <= 0 || h <= 0) return 1;
    final scaleW = (w * c + h * s) / w;
    final scaleH = (w * s + h * c) / h;
    return math.max(scaleW, scaleH);
  }

  Rect _fittedCrop(Size space) {
    final cropPxW = math.max(_width * _imgW, 1);
    final cropPxH = math.max(_height * _imgH, 1);
    var w = space.width;
    var h = w * cropPxH / cropPxW;
    if (h > space.height) {
      h = space.height;
      w = h * cropPxW / cropPxH;
    }
    return Rect.fromLTWH((space.width - w) / 2, (space.height - h) / 2, w, h);
  }

  Rect _imageInside(Rect crop, double imageW, double imageH) {
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

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: path == null
                  ? const SizedBox.shrink()
                  : ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final space = Size(
                            math.max(constraints.maxWidth - 36, 1),
                            math.max(constraints.maxHeight - 36, 1),
                          );
                          final crop = _fittedCrop(space)
                              .shift(const Offset(18, 18));
                          final imageW = crop.width / _width;
                          final imageH = crop.height / _height;
                          final image = _imageInside(crop, imageW, imageH);
                          _boxW = imageW;
                          _boxH = imageH;
                          _cropView = crop;
                          return GestureDetector(
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: (_) => _grip = null,
                            child: _cropStage(path, crop, image),
                          );
                        },
                      ),
                    ),
            ),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _cropStage(String path, Rect crop, Rect image) {
    final photo = Transform.scale(
      scale: _coverScale(),
      child: Transform.rotate(
        angle: _degrees * math.pi / 180,
        child: Image.file(
          File(path),
          width: image.width,
          height: image.height,
          filterQuality: FilterQuality.high,
          fit: BoxFit.fill,
          gaplessPlayback: true,
        ),
      ),
    );
    return Stack(
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
            children: [Positioned.fromRect(rect: image, child: photo)],
          ),
        ),
        CustomPaint(painter: _CropGridPainter(crop)),
        for (final corner in <Offset>[
          crop.topLeft,
          crop.topRight,
          crop.bottomLeft,
          crop.bottomRight,
        ])
          Positioned(
            left: corner.dx - 7,
            top: corner.dy - 7,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _controls() {
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Crop',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      SizedBox(
                        width: 36,
                        height: 2.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textDark,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _ready ? _confirm : null,
                        icon: const Icon(
                          Icons.check,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ColoredBox(
          color: Colors.white,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Column(
                  children: [
                    Text(
                      '${_degrees.round()}°',
                      style: const TextStyle(
                        color: _scaleYellow,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 10,
                        right: 10,
                        bottom: 12,
                      ),
                      child: SizedBox(
                        height: 22,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final pxPerDegree = constraints.maxWidth / 90;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                if (pxPerDegree <= 0) return;
                                final next =
                                    (_degrees - details.delta.dx / pxPerDegree)
                                        .clamp(-45.0, 45.0);
                                setState(() => _degrees = next.roundToDouble());
                              },
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  CustomPaint(
                                    size: Size(constraints.maxWidth, 28),
                                    painter: _TickPainter(degrees: _degrees),
                                  ),
                                  const SizedBox(
                                    width: 2,
                                    height: 20,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: _scaleYellow,
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(1),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  itemCount: _ratios.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final choice = _ratios[index];
                    final selected = choice.id == _presetId;
                    final color = selected
                        ? AppColors.primary
                        : const Color(0xFF8E8E8E);
                    return GestureDetector(
                      onTap: () => setState(() => _select(choice)),
                      child: SizedBox(
                        width: 44,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CustomPaint(
                                painter: _RatioMarkPainter(choice.mark, color),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              choice.label,
                              maxLines: 1,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ],
    );
  }
}

class _RatioMarkPainter extends CustomPainter {
  _RatioMarkPainter(this.mark, this.color);

  final _RatioMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final center = Offset(size.width / 2, size.height / 2);
    void frame(double w, double h, {double radius = 3}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: h),
          Radius.circular(radius),
        ),
        paint,
      );
    }

    switch (mark) {
      case _RatioMark.free:
        frame(16, 26, radius: 3);
      case _RatioMark.square:
        frame(22, 22, radius: 4);
        canvas.drawCircle(center, 5, paint);
        canvas.drawCircle(
          center + const Offset(5.5, -5.5),
          1.1,
          Paint()..color = color,
        );
      case _RatioMark.fourFive:
        frame(18, 24);
      case _RatioMark.story:
        frame(15, 28, radius: 3);
        final note = TextPainter(
          text: TextSpan(
            text: '♪',
            style: TextStyle(color: color, fontSize: 12, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        note.paint(canvas, center - Offset(note.width / 2, note.height / 2));
      case _RatioMark.wide:
        frame(28, 16, radius: 3);
        final play = Path()
          ..moveTo(center.dx - 3, center.dy - 4)
          ..lineTo(center.dx + 4, center.dy)
          ..lineTo(center.dx - 3, center.dy + 4)
          ..close();
        canvas.drawPath(play, Paint()..color = color);
      case _RatioMark.threeFour:
        frame(17, 24);
      case _RatioMark.fourThree:
        frame(26, 18);
    }
  }

  @override
  bool shouldRepaint(covariant _RatioMarkPainter oldDelegate) =>
      oldDelegate.mark != mark || oldDelegate.color != color;
}

class _RectClipper extends CustomClipper<Rect> {
  _RectClipper(this.rect);
  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _RectClipper oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CropGridPainter extends CustomPainter {
  _CropGridPainter(this.crop);
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = _cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final grid = Paint()
      ..color = _cyan.withValues(alpha: 0.85)
      ..strokeWidth = 0.8;
    canvas.drawRect(crop, border);
    for (var i = 1; i <= 2; i++) {
      final dx = crop.left + crop.width * i / 3;
      final dy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(dx, crop.top), Offset(dx, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, dy), Offset(crop.right, dy), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) =>
      oldDelegate.crop != crop;
}

class _TickPainter extends CustomPainter {
  const _TickPainter({required this.degrees});

  final double degrees;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final px = size.width / 60;
    for (var deg = -45; deg <= 45; deg++) {
      final x = center + (deg - degrees) * px;
      if (x < -2 || x > size.width + 2) continue;
      final major = deg % 5 == 0;
      final paint = Paint()
        ..color = major ? Colors.black : const Color(0xFF5C5C5C)
        ..strokeWidth = major ? 1.6 : 1
        ..strokeCap = StrokeCap.round;
      final h = major ? 16.0 : 11.0;
      final y = size.height - 1;
      canvas.drawLine(Offset(x, y - h), Offset(x, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TickPainter oldDelegate) =>
      oldDelegate.degrees != degrees;
}

/// Shows a photo the way the crop page saved it: the frame stays upright and the picture is rotated inside it.
class CroppedPhotoView extends StatelessWidget {
  const CroppedPhotoView({
    super.key,
    required this.photo,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
    this.cacheWidth,
  });

  final SlideshowPhoto photo;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final int? cacheWidth;

  bool get _hasCrop {
    return photo.cropLeft.abs() > 0.001 ||
        photo.cropTop.abs() > 0.001 ||
        (photo.cropWidth - 1).abs() > 0.001 ||
        (photo.cropHeight - 1).abs() > 0.001 ||
        photo.cropDegrees.abs() > 0.05;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCrop) {
      return Image.file(
        File(photo.path),
        fit: fit,
        gaplessPlayback: true,
        filterQuality: filterQuality,
        cacheWidth: cacheWidth,
      );
    }
    return FittedBox(
      fit: fit,
      child: _CropFrame(
        left: photo.cropLeft,
        top: photo.cropTop,
        width: photo.cropWidth.clamp(0.05, 8),
        height: photo.cropHeight.clamp(0.05, 8),
        radians: photo.cropDegrees * math.pi / 180,
        child: Image.file(
          File(photo.path),
          gaplessPlayback: true,
          filterQuality: filterQuality,
          cacheWidth: cacheWidth,
        ),
      ),
    );
  }
}

class _CropFrame extends SingleChildRenderObjectWidget {
  const _CropFrame({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.radians,
    required super.child,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double radians;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCropFrame(
      left: left,
      top: top,
      width: width,
      height: height,
      radians: radians,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderCropFrame renderObject) {
    renderObject
      ..left = left
      ..top = top
      ..width = width
      ..height = height
      ..radians = radians;
  }
}

class _RenderCropFrame extends RenderProxyBox {
  _RenderCropFrame({
    required this._left,
    required this._top,
    required this._width,
    required this._height,
    required this._radians,
  });

  double _left;
  double _top;
  double _width;
  double _height;
  double _radians;

  set left(double value) {
    if (_left == value) return;
    _left = value;
    markNeedsLayout();
  }

  set top(double value) {
    if (_top == value) return;
    _top = value;
    markNeedsLayout();
  }

  set width(double value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  set radians(double value) {
    if (_radians == value) return;
    _radians = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      return;
    }
    child.layout(const BoxConstraints(), parentUsesSize: true);
    size = Size(
      math.max(child.size.width * _width, 1),
      math.max(child.size.height * _height, 1),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || child.size.width <= 0 || child.size.height <= 0) {
      return;
    }
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xFF000000),
    );
    final image = child.size;
    final c = math.cos(_radians.abs());
    final s = math.sin(_radians.abs());
    final cover = math.max(
      (image.width * c + image.height * s) / image.width,
      (image.width * s + image.height * c) / image.height,
    );
    final zoom = math.max(_width, _height);
    final fitted = zoom > 1.001;
    final scale = cover * (fitted ? zoom : 1);
    final center = fitted
        ? Offset(size.width / 2, size.height / 2)
        : Offset(
            -_left * image.width + image.width / 2,
            -_top * image.height + image.height / 2,
          );
    final matrix = Matrix4.identity()
      ..translateByDouble(offset.dx + center.dx, offset.dy + center.dy, 0, 1)
      ..rotateZ(_radians)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-image.width / 2, -image.height / 2, 0, 1);
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      _,
    ) {
      context.pushTransform(needsCompositing, Offset.zero, matrix, (
        context,
        _,
      ) {
        child.paint(context, Offset.zero);
      });
    });
  }
}
