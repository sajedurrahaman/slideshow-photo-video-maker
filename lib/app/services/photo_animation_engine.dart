import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/models.dart';

class PhotoAnimationEngine {
  PhotoAnimationEngine._();

  static img.Image apply({
    required img.Image image,
    required PhotoAnimationType type,
    required double progress,
    required int backgroundArgb,
    bool reverse = false,
  }) {
    if (type == PhotoAnimationType.none) return image;
    final p = progress.clamp(0.0, 1.0);
    final t = reverse ? 1.0 - p : p;
    final w = image.width;
    final h = image.height;

    switch (type) {
      case PhotoAnimationType.none:
        return image;
      case PhotoAnimationType.fade:
        return _fade(image, t, backgroundArgb);
      case PhotoAnimationType.slightZoom:
        return _zoom(image, 1.12 - 0.12 * t, backgroundArgb);
      case PhotoAnimationType.zoomIn:
        return _zoom(image, 0.78 + 0.22 * t, backgroundArgb);
      case PhotoAnimationType.zoomOut:
        return _zoom(image, 1.22 - 0.22 * t, backgroundArgb);
      case PhotoAnimationType.shake:
        return _spin(
          image,
          math.sin(t * math.pi * 8) * 8,
          backgroundArgb,
        );
      case PhotoAnimationType.shake2:
        final sx = (math.sin(t * math.pi * 12) * w * 0.05).round();
        final sy = (math.cos(t * math.pi * 10) * h * 0.02).round();
        return _place(image, w, h, sx, sy, backgroundArgb);
      case PhotoAnimationType.slideLeft:
        return _place(image, w, h, -((1 - t) * w).round(), 0, backgroundArgb);
      case PhotoAnimationType.slideUp:
        return _place(image, w, h, 0, ((1 - t) * h).round(), backgroundArgb);
      case PhotoAnimationType.slideRight:
        return _place(image, w, h, ((1 - t) * w).round(), 0, backgroundArgb);
      case PhotoAnimationType.slideDown:
        return _place(image, w, h, 0, -((1 - t) * h).round(), backgroundArgb);
      case PhotoAnimationType.dynamicZoom:
        return _zoom(image, 1.0 + 0.28 * t, backgroundArgb);
      case PhotoAnimationType.dynamicZoomAlt:
        return _zoom(image, 1.28 - 0.28 * t, backgroundArgb);
      case PhotoAnimationType.wiper:
        return _wiper(image, t, backgroundArgb);
      case PhotoAnimationType.pendulum:
        return _pendulum(image, math.sin(t * math.pi * 2) * 14);
      case PhotoAnimationType.upAndDown:
        final bob = (math.sin(t * math.pi * 2) * h * 0.06).round();
        return _place(image, w, h, 0, bob, backgroundArgb);
      case PhotoAnimationType.mirror:
      case PhotoAnimationType.mirrorOutside:
        return _mirrorOpen(image, t);
      case PhotoAnimationType.leftAndRight:
        final sway = (math.sin(t * math.pi * 2) * (1 - t * 0.35) * w * 0.1)
            .round();
        return _place(image, w, h, sway, 0, backgroundArgb);
      case PhotoAnimationType.spinRight:
        return _spin(image, (1 - t) * 70, backgroundArgb);
      case PhotoAnimationType.spinLeft:
        return _spin(image, -(1 - t) * 70, backgroundArgb);
      case PhotoAnimationType.spinUpper:
        final scale = 0.15 + 0.85 * t;
        final sh = math.max(1, (h * scale).round());
        final resized = img.copyResize(
          image,
          width: w,
          height: sh,
          interpolation: img.Interpolation.linear,
        );
        return _place(resized, w, h, 0, 0, backgroundArgb);
      case PhotoAnimationType.bottomOut:
        return _place(image, w, h, 0, ((1 - t) * h).round(), backgroundArgb);
      case PhotoAnimationType.leftOut:
        return _place(image, w, h, -((1 - t) * w).round(), 0, backgroundArgb);
      case PhotoAnimationType.rightOut:
        return _place(image, w, h, ((1 - t) * w).round(), 0, backgroundArgb);
      case PhotoAnimationType.topOut:
        return _place(image, w, h, 0, -((1 - t) * h).round(), backgroundArgb);
      case PhotoAnimationType.dynamicZoomOut:
        return _zoom(image, 0.42 + 0.58 * t, backgroundArgb);
      case PhotoAnimationType.flipLeft:
        return _hinge(
          image,
          t,
          1,
          alignRight: false,
          alignBottom: false,
          backgroundArgb: backgroundArgb,
        );
      case PhotoAnimationType.flipRight:
        return _hinge(
          image,
          t,
          1,
          alignRight: true,
          alignBottom: false,
          backgroundArgb: backgroundArgb,
        );
      case PhotoAnimationType.flipLower:
        return _hinge(
          image,
          1,
          t,
          alignRight: false,
          alignBottom: true,
          backgroundArgb: backgroundArgb,
        );
      case PhotoAnimationType.slideOutTop:
        return _place(
          _fade(image, 0.2 + 0.8 * t, backgroundArgb),
          w,
          h,
          0,
          -((1 - t) * h).round(),
          backgroundArgb,
        );
      case PhotoAnimationType.slideOutBottom:
        return _place(
          _fade(image, 0.2 + 0.8 * t, backgroundArgb),
          w,
          h,
          0,
          ((1 - t) * h).round(),
          backgroundArgb,
        );
      case PhotoAnimationType.rotateFade:
        return _spin(
          _fade(image, t, backgroundArgb),
          (1 - t) * 160,
          backgroundArgb,
        );
      case PhotoAnimationType.flyOutLeft:
        return _fly(image, t, -1, 0, backgroundArgb);
      case PhotoAnimationType.flyOutRight:
        return _fly(image, t, 1, 0, backgroundArgb);
      case PhotoAnimationType.flyOutUp:
        return _fly(image, t, 0, -1, backgroundArgb);
    }
  }

  static img.Image _hinge(
    img.Image image,
    double scaleX,
    double scaleY, {
    required bool alignRight,
    required bool alignBottom,
    required int backgroundArgb,
  }) {
    final w = image.width;
    final h = image.height;
    final sx = scaleX.clamp(0.02, 1.0);
    final sy = scaleY.clamp(0.02, 1.0);
    final sw = math.max(1, (w * sx).round());
    final sh = math.max(1, (h * sy).round());
    final resized = img.copyResize(
      image,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.linear,
    );
    final dx = alignRight ? w - sw : 0;
    final dy = alignBottom ? h - sh : (h - sh) ~/ 2;
    return _place(resized, w, h, dx, dy, backgroundArgb);
  }

  static img.Image _fly(
    img.Image image,
    double t,
    int xDir,
    int yDir,
    int backgroundArgb,
  ) {
    final faded = _fade(image, t, backgroundArgb);
    final scaled = _zoom(faded, 0.35 + 0.65 * t, backgroundArgb);
    final w = image.width;
    final h = image.height;
    return _place(
      scaled,
      w,
      h,
      (xDir * (1 - t) * w * 0.9).round(),
      (yDir * (1 - t) * h * 0.9).round(),
      backgroundArgb,
    );
  }

  static final Expando<img.Image> _blurredOriginals = Expando<img.Image>();

  static img.Image _blurredOriginal(img.Image image) {
    final cached = _blurredOriginals[image];
    if (cached != null) return cached;
    final w = image.width;
    final h = image.height;
    final tiny = img.copyResize(
      image,
      width: math.max(6, w ~/ 28),
      height: math.max(6, h ~/ 28),
      interpolation: img.Interpolation.average,
    );
    final plate = img.copyResize(
      tiny,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    _blurredOriginals[image] = plate;
    return plate;
  }

  /// Left and right halves swing open over the blurred original.
  static img.Image _mirrorOpen(img.Image image, double t) {
    final scale = math.cos((1 - t) * math.pi / 2).clamp(0.0, 1.0);
    if (scale >= 0.995) return image;
    final plate = _blurredOriginal(image);
    if (scale <= 0.02) return img.Image.from(plate);
    final w = image.width;
    final h = image.height;
    final out = img.Image.from(plate);
    final mid = w ~/ 2;
    final leftW = math.max(1, (mid * scale).round());
    final rightSrcW = w - mid;
    final rightW = math.max(1, (rightSrcW * scale).round());
    final left = img.copyResize(
      img.copyCrop(image, x: 0, y: 0, width: mid, height: h),
      width: leftW,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    final right = img.copyResize(
      img.copyCrop(image, x: mid, y: 0, width: rightSrcW, height: h),
      width: rightW,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    img.compositeImage(out, left, dstX: mid - leftW, dstY: 0);
    img.compositeImage(out, right, dstX: mid, dstY: 0);
    return out;
  }

  static final Expando<img.Image> _lightBlurs = Expando<img.Image>();

  /// Soft blur of the original, still recognizable.
  static img.Image _lightBlur(img.Image image) {
    final cached = _lightBlurs[image];
    if (cached != null) return cached;
    final w = image.width;
    final h = image.height;
    final tiny = img.copyResize(
      image,
      width: math.max(18, w ~/ 6),
      height: math.max(18, h ~/ 6),
      interpolation: img.Interpolation.average,
    );
    final plate = img.copyResize(
      tiny,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
    _lightBlurs[image] = plate;
    return plate;
  }

  /// Top-center stays fixed. The bottom swings left and right.
  static img.Image _pendulum(img.Image image, double degrees) {
    if (degrees.abs() < 0.4) return image;
    final angle = degrees * math.pi / 180;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final w = image.width;
    final h = image.height;
    final out = img.Image.from(_lightBlur(image));
    final px = (w - 1) / 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x - px;
        final dy = y.toDouble();
        final sx = px + dx * cosA + dy * sinA;
        final sy = -dx * sinA + dy * cosA;
        final ix = sx.round();
        final iy = sy.round();
        if (ix < 0 || iy < 0 || ix >= w || iy >= h) continue;
        out.setPixel(x, y, image.getPixel(ix, iy));
      }
    }
    return out;
  }

  static img.Image _spin(img.Image image, double degrees, int backgroundArgb) {
    if (degrees.abs() < 0.5) return image;
    final rotated = img.copyRotate(image, angle: degrees);
    return _place(
      rotated,
      image.width,
      image.height,
      (image.width - rotated.width) ~/ 2,
      (image.height - rotated.height) ~/ 2,
      backgroundArgb,
    );
  }

  static img.Image _fade(img.Image image, double amount, int backgroundArgb) {
    final out = image.clone();
    final br = (backgroundArgb >> 16) & 0xFF;
    final bg = (backgroundArgb >> 8) & 0xFF;
    final bb = backgroundArgb & 0xFF;
    for (final pixel in out) {
      pixel
        ..r = (br + (pixel.r - br) * amount).round().clamp(0, 255)
        ..g = (bg + (pixel.g - bg) * amount).round().clamp(0, 255)
        ..b = (bb + (pixel.b - bb) * amount).round().clamp(0, 255);
    }
    return out;
  }

  /// Zoomed crop sweeps up from the bottom, with a sideways smear, then settles sharp.
  static img.Image _wiper(img.Image image, double t, int backgroundArgb) {
    final p = 1 - math.pow(1 - t, 2.4).toDouble();
    final scale = 1.7 - 0.7 * p;
    final w = image.width;
    final h = image.height;
    final sw = math.max(1, (w * scale).round());
    final sh = math.max(1, (h * scale).round());
    final resized = img.copyResize(
      image,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.linear,
    );
    final dx = ((w - sw) / 2 - 0.14 * math.sin((1 - p) * math.pi) * w).round();
    final dy = ((h - sh) / 2 - 0.24 * (1 - p) * h).round();
    var frame = _place(resized, w, h, dx, dy, backgroundArgb);
    final blur = 1 - p;
    if (blur > 0.12) {
      final narrow = math.max(8, (w * (1 - 0.62 * blur)).round());
      final squeezed = img.copyResize(
        frame,
        width: narrow,
        height: h,
        interpolation: img.Interpolation.average,
      );
      frame = img.copyResize(
        squeezed,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    }
    return frame;
  }

  static img.Image _zoom(img.Image image, double scale, int backgroundArgb) {
    final w = image.width;
    final h = image.height;
    final sw = (w * scale).round().clamp(1, w * 2);
    final sh = (h * scale).round().clamp(1, h * 2);
    final resized = img.copyResize(
      image,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.linear,
    );
    return _place(resized, w, h, (w - sw) ~/ 2, (h - sh) ~/ 2, backgroundArgb);
  }

  static img.Image _place(
    img.Image source,
    int width,
    int height,
    int dx,
    int dy,
    int backgroundArgb,
  ) {
    final out = img.Image(width: width, height: height, numChannels: 4);
    img.fill(
      out,
      color: img.ColorRgba8(
        (backgroundArgb >> 16) & 0xFF,
        (backgroundArgb >> 8) & 0xFF,
        backgroundArgb & 0xFF,
        255,
      ),
    );
    for (var y = 0; y < height; y++) {
      final sy = y - dy;
      if (sy < 0 || sy >= source.height) continue;
      for (var x = 0; x < width; x++) {
        final sx = x - dx;
        if (sx < 0 || sx >= source.width) continue;
        out.setPixel(x, y, source.getPixel(sx, sy));
      }
    }
    return out;
  }
}
