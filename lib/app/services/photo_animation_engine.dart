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
        final dx = (math.sin(t * math.pi * 8) * w * 0.035).round();
        return _place(image, w, h, dx, 0, backgroundArgb);
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
        return _place(
          image,
          w,
          h,
          ((0.5 - t) * w * 0.35).round(),
          0,
          backgroundArgb,
        );
      case PhotoAnimationType.pendulum:
        final swing = (math.sin(t * math.pi) * w * 0.12).round();
        return _place(image, w, h, swing, 0, backgroundArgb);
      case PhotoAnimationType.upAndDown:
        final bob = (math.sin(t * math.pi * 2) * h * 0.06).round();
        return _place(image, w, h, 0, bob, backgroundArgb);
      case PhotoAnimationType.mirror:
        final flipped = img.flipHorizontal(image);
        return t < 0.5 ? image : flipped;
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
      case PhotoAnimationType.mirrorOutside:
        final shown = t < 0.5 ? img.flipHorizontal(image) : image;
        return _place(
          shown,
          w,
          h,
          ((1 - t) * w * 0.55).round(),
          0,
          backgroundArgb,
        );
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
        return _hinge(image, t, 1, alignRight: false, alignBottom: false, backgroundArgb: backgroundArgb);
      case PhotoAnimationType.flipRight:
        return _hinge(image, t, 1, alignRight: true, alignBottom: false, backgroundArgb: backgroundArgb);
      case PhotoAnimationType.flipLower:
        return _hinge(image, 1, t, alignRight: false, alignBottom: true, backgroundArgb: backgroundArgb);
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
