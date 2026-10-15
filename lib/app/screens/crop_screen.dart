import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

enum _Grip { move, tl, tr, bl, br }

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
    _left = photo.cropLeft;
    _top = photo.cropTop;
    _width = photo.cropWidth.clamp(0.08, 1);
    _height = photo.cropHeight.clamp(0.08, 1);
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
      nh = 1;
      nw = ratio / imgAspect;
    } else {
      nw = 1;
      nh = imgAspect / ratio;
    }
    nw = nw.clamp(0.08, 1);
    nh = nh.clamp(0.08, 1);
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
        );
      }
    }
    context.pop();
  }

  Offset _toImage(Offset delta) => delta;

  _Grip? _hit(Offset local) {
    final rect = Rect.fromLTWH(
      _left * _boxW,
      _top * _boxH,
      _width * _boxW,
      _height * _boxH,
    );
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
        _left = (_left + dx).clamp(0.0, 1 - _width);
        _top = (_top + dy).clamp(0.0, 1 - _height);
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
    if (grip == _Grip.tl || grip == _Grip.bl) l += dx;
    if (grip == _Grip.tr || grip == _Grip.br) r += dx;
    if (grip == _Grip.tl || grip == _Grip.tr) t += dy;
    if (grip == _Grip.bl || grip == _Grip.br) b += dy;
    l = l.clamp(0.0, r - 0.08);
    r = r.clamp(l + 0.08, 1.0);
    t = t.clamp(0.0, b - 0.08);
    b = b.clamp(t + 0.08, 1.0);
    _left = l;
    _top = t;
    _width = r - l;
    _height = b - t;
  }

  void _resizeLocked(_Grip grip, double dx, double dy) {
    final aspect = _aspect;
    if (aspect == null) return;
    final anchorRight = grip == _Grip.tl || grip == _Grip.bl;
    final anchorBottom = grip == _Grip.tl || grip == _Grip.tr;
    final ax = anchorRight ? _left + _width : _left;
    final ay = anchorBottom ? _top + _height : _top;
    final imgAspect = _imgW / _imgH;
    var nw = _width + (anchorRight ? -dx : dx);
    var nh = _height + (anchorBottom ? -dy : dy);
    if (dx.abs() >= dy.abs()) {
      nw = nw.clamp(0.08, 1.0);
      nh = nw * imgAspect / aspect;
    } else {
      nh = nh.clamp(0.08, 1.0);
      nw = nh * aspect / imgAspect;
    }
    if (nh > 1) {
      nh = 1;
      nw = nh * aspect / imgAspect;
    }
    if (nw > 1) {
      nw = 1;
      nh = nw * imgAspect / aspect;
    }
    var l = anchorRight ? ax - nw : ax;
    var t = anchorBottom ? ay - nh : ay;
    if (l < 0 || t < 0 || l + nw > 1 || t + nh > 1) {
      l = l.clamp(0.0, 1.0);
      t = t.clamp(0.0, 1.0);
      nw = math.min(nw, 1 - l);
      nh = nw * imgAspect / aspect;
      if (t + nh > 1) {
        nh = 1 - t;
        nw = nh * aspect / imgAspect;
        if (anchorRight) l = ax - nw;
      }
      if (l < 0 || t < 0 || l + nw > 1.001 || t + nh > 1.001 || nw < 0.08) {
        return;
      }
    }
    _left = l;
    _top = t;
    _width = nw;
    _height = nh;
  }

  Rect _imageBox(Size space) {
    final aspect = _imgW / _imgH;
    var w = space.width;
    var h = w / aspect;
    if (h > space.height) {
      h = space.height;
      w = h * aspect;
    }
    return Rect.fromLTWH((space.width - w) / 2, (space.height - h) / 2, w, h);
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
                          final box = _imageBox(space)
                              .shift(const Offset(18, 18));
                          _boxW = box.width;
                          _boxH = box.height;
                          return Stack(
                            children: [
                              Positioned.fromRect(
                                rect: box,
                                child: GestureDetector(
                                  onPanStart: _onPanStart,
                                  onPanUpdate: _onPanUpdate,
                                  onPanEnd: (_) => _grip = null,
                                  child: _cropStage(path, box.size),
                                ),
                              ),
                            ],
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

  Widget _cropStage(String path, Size size) {
    final crop = Rect.fromLTWH(
      _left * size.width,
      _top * size.height,
      _width * size.width,
      _height * size.height,
    );
    final turned = Transform.rotate(
      angle: _degrees * math.pi / 180,
      child: Image.file(
        File(path),
        width: size.width,
        height: size.height,
        fit: BoxFit.fill,
        gaplessPlayback: true,
      ),
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          turned,
          Positioned.fill(
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.55)),
          ),
          ClipRect(
            clipper: _RectClipper(crop),
            child: Transform.rotate(
              angle: _degrees * math.pi / 180,
              child: Image.file(
                File(path),
                width: size.width,
                height: size.height,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
          ),
          CustomPaint(size: size, painter: _CropGridPainter(crop)),
          for (final corner in <Alignment>[
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ])
            Positioned(
              left: corner.x < 0 ? crop.left - 7 : crop.right - 7,
              top: corner.y < 0 ? crop.top - 7 : crop.bottom - 7,
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
      ),
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
  });

  final SlideshowPhoto photo;
  final BoxFit fit;

  bool get _hasCrop {
    return photo.cropLeft > 0.001 ||
        photo.cropTop > 0.001 ||
        photo.cropWidth < 0.999 ||
        photo.cropHeight < 0.999 ||
        photo.cropDegrees.abs() > 0.05;
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCrop) {
      return Image.file(
        File(photo.path),
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }
    Widget image = Image.file(
      File(photo.path),
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
    if (photo.cropDegrees.abs() > 0.05) {
      image = Transform.rotate(
        angle: photo.cropDegrees * math.pi / 180,
        child: image,
      );
    }
    image = ClipRect(
      child: Align(
        alignment: Alignment(
          ((photo.cropLeft + photo.cropWidth / 2) * 2 - 1).clamp(-1.0, 1.0),
          ((photo.cropTop + photo.cropHeight / 2) * 2 - 1).clamp(-1.0, 1.0),
        ),
        widthFactor: photo.cropWidth.clamp(0.02, 1.0),
        heightFactor: photo.cropHeight.clamp(0.02, 1.0),
        child: image,
      ),
    );
    return FittedBox(fit: fit, child: image);
  }
}
