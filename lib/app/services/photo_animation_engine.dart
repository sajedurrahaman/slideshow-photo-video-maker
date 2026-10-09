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
    }
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
