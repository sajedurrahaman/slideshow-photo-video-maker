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
    img.Image? underlay,
  }) {
    if (type == PhotoAnimationType.none) return image;
    final p = progress.clamp(0.0, 1.0);
    final t = reverse ? 1.0 - p : p;
    final w = image.width;
    final h = image.height;
    final plate = underlay;

    switch (type) {
      case PhotoAnimationType.none:
        return image;
      case PhotoAnimationType.fade:
        if (plate != null) {
          return _place(
            _fadeSubjectAlpha(image, t),
            w,
            h,
            0,
            0,
            backgroundArgb,
            underlay: plate,
          );
        }
        return _fade(image, t, backgroundArgb);
      case PhotoAnimationType.slightZoom:
        return _zoom(image, 1.12 - 0.12 * t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.zoomIn:
        return _zoom(image, 0.78 + 0.22 * t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.zoomOut:
        return _zoom(image, 1.22 - 0.22 * t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.shake:
        return _spin(
          image,
          math.sin(t * math.pi * 8) * 8,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.shake2:
        final sx = (math.sin(t * math.pi * 12) * w * 0.05).round();
        final sy = (math.cos(t * math.pi * 10) * h * 0.02).round();
        return _place(image, w, h, sx, sy, backgroundArgb, underlay: plate);
      case PhotoAnimationType.slideLeft:
        return _place(
          image,
          w,
          h,
          -((1 - t) * w).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.slideUp:
        return _place(
          image,
          w,
          h,
          0,
          ((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.slideRight:
        return _place(
          image,
          w,
          h,
          ((1 - t) * w).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.slideDown:
        return _place(
          image,
          w,
          h,
          0,
          -((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.dynamicZoom:
        return _wiper(image, t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.wiper:
        return _swing(
          image,
          math.sin(t * math.pi * 2) * 14,
          fromTop: false,
          scale: 1.34 - 0.34 * t,
          underlay: plate,
        );
      case PhotoAnimationType.dynamicZoomAlt:
        return _zoom(image, 1.28 - 0.28 * t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.pendulum:
        return _swing(
          image,
          math.sin(t * math.pi * 2) * 14,
          fromTop: true,
          underlay: plate,
        );
      case PhotoAnimationType.upAndDown:
        final bob = (math.sin(t * math.pi * 2) * h * 0.06).round();
        return _place(image, w, h, 0, bob, backgroundArgb, underlay: plate);
      case PhotoAnimationType.mirror:
      case PhotoAnimationType.mirrorOutside:
        return _mirrorOpen(image, t, underlay: plate);
      case PhotoAnimationType.leftAndRight:
        final sway = (math.sin(t * math.pi * 2) * (1 - t * 0.35) * w * 0.1)
            .round();
        return _place(image, w, h, sway, 0, backgroundArgb, underlay: plate);
      case PhotoAnimationType.spinRight:
        return _spinTravel(
          image,
          (1 - t) * 180,
          ((1 - t) * w * 1.15).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.spinLeft:
        return _spinTravel(
          image,
          -(1 - t) * 180,
          -((1 - t) * w * 1.15).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.spinUpper:
        return _spinTravel(
          image,
          -(1 - t) * 180,
          0,
          -((1 - t) * h * 1.15).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.bottomOut:
        return _place(
          image,
          w,
          h,
          0,
          ((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.leftOut:
        return _place(
          image,
          w,
          h,
          -((1 - t) * w).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.rightOut:
        return _place(
          image,
          w,
          h,
          ((1 - t) * w).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.topOut:
        return _place(
          image,
          w,
          h,
          0,
          -((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.dynamicZoomOut:
        return _wiper(image, t, backgroundArgb, underlay: plate);
      case PhotoAnimationType.flipLeft:
        return _spinTravel(
          image,
          -(1 - t) * 180,
          -((1 - t) * w * 1.15).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.flipRight:
        return _spinTravel(
          image,
          (1 - t) * 180,
          ((1 - t) * w * 1.15).round(),
          0,
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.flipLower:
        return _spinTravel(
          image,
          (1 - t) * 180,
          0,
          ((1 - t) * h * 1.15).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.slideOutTop:
        return _place(
          plate != null
              ? _fadeSubjectAlpha(image, 0.2 + 0.8 * t)
              : _fade(image, 0.2 + 0.8 * t, backgroundArgb),
          w,
          h,
          0,
          -((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.slideOutBottom:
        return _place(
          plate != null
              ? _fadeSubjectAlpha(image, 0.2 + 0.8 * t)
              : _fade(image, 0.2 + 0.8 * t, backgroundArgb),
          w,
          h,
          0,
          ((1 - t) * h).round(),
          backgroundArgb,
          underlay: plate,
        );
      case PhotoAnimationType.rotateFade:
        return _spin(
          plate != null
              ? _fadeSubjectAlpha(image, t)
              : _fade(image, t, backgroundArgb),
          (1 - t) * 160,
          backgroundArgb,
          underlay: plate ?? _lightBlur(image),
        );
      case PhotoAnimationType.flyOutLeft:
        return _flySpin(
          image,
          t,
          backgroundArgb,
          spinSign: -1,
          x: -1,
          y: -1,
          underlay: plate,
        );
      case PhotoAnimationType.flyOutRight:
        return _flySpin(
          image,
          t,
          backgroundArgb,
          spinSign: 1,
          x: 1,
          y: -1,
          underlay: plate,
        );
      case PhotoAnimationType.flyOutUp:
        return _flySpin(
          image,
          t,
          backgroundArgb,
          spinSign: -1,
          x: 0,
          y: -1,
          yTravel: 0.42,
          underlay: plate,
        );
    }
  }

  /// Animates [subject] on a fixed [background] (editor live preview behavior).
  static img.Image applyLayered({
    required img.Image background,
    required img.Image subject,
    required int subjectDx,
    required int subjectDy,
    required PhotoAnimationType type,
    required double progress,
    required int backgroundArgb,
    bool reverse = false,
  }) {
    if (type == PhotoAnimationType.none) {
      final out = img.Image.from(background);
      img.compositeImage(out, subject, dstX: subjectDx, dstY: subjectDy);
      return out;
    }
    final layer = img.Image(
      width: background.width,
      height: background.height,
      numChannels: 4,
    );
    img.fill(layer, color: img.ColorRgba8(0, 0, 0, 0));
    img.compositeImage(layer, subject, dstX: subjectDx, dstY: subjectDy);
    return apply(
      image: layer,
      type: type,
      progress: progress,
      backgroundArgb: backgroundArgb,
      reverse: reverse,
      underlay: background,
    );
  }

  /// Spins around the center, then shifts off the frame.
  static img.Image _spinTravel(
    img.Image image,
    double degrees,
    int dx,
    int dy,
    int backgroundArgb, {
    img.Image? underlay,
  }) {
    if (degrees.abs() < 0.5 && dx == 0 && dy == 0) {
      return underlay == null
          ? image
          : _place(image, image.width, image.height, 0, 0, backgroundArgb,
              underlay: underlay);
    }
    final spun = degrees.abs() < 0.5
        ? image
        : img.copyRotate(image, angle: degrees);
    return _place(
      spun,
      image.width,
      image.height,
      dx + (image.width - spun.width) ~/ 2,
      dy + (image.height - spun.height) ~/ 2,
      backgroundArgb,
      underlay: underlay ?? _lightBlur(image),
    );
  }

  /// Spins, pinches through an edge, then shrinks along [x] and [y].
  static img.Image _flySpin(
    img.Image image,
    double t,
    int backgroundArgb, {
    required double spinSign,
    required double x,
    required double y,
    double xTravel = 0.36,
    double yTravel = 0.2,
    img.Image? underlay,
  }) {
    final exit = (1 - t).clamp(0.0, 1.0);
    final spin = 1 - math.pow(1 - math.min(exit / 0.5, 1.0), 1.8).toDouble();
    final flip = math.min(exit / 0.62, 1.0);
    final pinch = math.cos(flip * math.pi).abs().clamp(0.012, 1.0);
    final scale = 1 - math.pow(exit, 1.05).toDouble() * 0.84;
    final drift = math.pow(math.max(exit - 0.28, 0) / 0.72, 1.35).toDouble();
    final degrees = spinSign * spin * 52;
    final w = image.width;
    final h = image.height;
    final sw = math.max(1, (w * scale).round());
    final sh = math.max(1, (h * scale * pinch).round());
    var frame = img.copyResize(
      image,
      width: sw,
      height: sh,
      interpolation: img.Interpolation.linear,
    );
    if (degrees.abs() > 0.4) {
      frame = img.copyRotate(frame, angle: degrees);
    }
    return _place(
      frame,
      w,
      h,
      ((w - frame.width) / 2 + x * drift * w * xTravel).round(),
      ((h - frame.height) / 2 + y * drift * h * yTravel).round(),
      backgroundArgb,
      underlay: underlay ?? _lightBlur(image),
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
  static img.Image _mirrorOpen(
    img.Image image,
    double t, {
    img.Image? underlay,
  }) {
    final scale = math.cos((1 - t) * math.pi / 2).clamp(0.0, 1.0);
    if (scale >= 0.995) {
      return underlay == null
          ? image
          : _place(image, image.width, image.height, 0, 0, 0, underlay: underlay);
    }
    final plate = underlay ?? _blurredOriginal(image);
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
    _compositeOpaque(out, left, mid - leftW, 0);
    _compositeOpaque(out, right, mid, 0);
    return out;
  }

  static void _compositeOpaque(
    img.Image dst,
    img.Image src,
    int dstX,
    int dstY,
  ) {
    for (var y = 0; y < src.height; y++) {
      final dy = dstY + y;
      if (dy < 0 || dy >= dst.height) continue;
      for (var x = 0; x < src.width; x++) {
        final dx = dstX + x;
        if (dx < 0 || dx >= dst.width) continue;
        final pixel = src.getPixel(x, y);
        if (pixel.a < 8) continue;
        dst.setPixel(dx, dy, pixel);
      }
    }
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

  /// [fromTop] keeps the top center fixed. Otherwise the bottom center stays fixed.
  static img.Image _swing(
    img.Image image,
    double degrees, {
    required bool fromTop,
    double scale = 1,
    img.Image? underlay,
  }) {
    final zoom = scale < 0.02 ? 0.02 : scale;
    if (degrees.abs() < 0.4 && (zoom - 1).abs() < 0.01) {
      return underlay == null
          ? image
          : _place(image, image.width, image.height, 0, 0, 0, underlay: underlay);
    }
    final angle = degrees * math.pi / 180;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final w = image.width;
    final h = image.height;
    final out = img.Image.from(underlay ?? _lightBlur(image));
    final px = (w - 1) / 2;
    final py = fromTop ? 0.0 : (h - 1).toDouble();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x - px;
        final dy = y - py;
        final sx = px + (dx * cosA + dy * sinA) / zoom;
        final sy = py + (-dx * sinA + dy * cosA) / zoom;
        final ix = sx.round();
        final iy = sy.round();
        if (ix < 0 || iy < 0 || ix >= w || iy >= h) continue;
        final pixel = image.getPixel(ix, iy);
        if (pixel.a < 8) continue;
        out.setPixel(x, y, pixel);
      }
    }
    return out;
  }

  static img.Image _spin(
    img.Image image,
    double degrees,
    int backgroundArgb, {
    img.Image? underlay,
  }) {
    if (degrees.abs() < 0.5) {
      return underlay == null
          ? image
          : _place(image, image.width, image.height, 0, 0, backgroundArgb,
              underlay: underlay);
    }
    final rotated = img.copyRotate(image, angle: degrees);
    return _place(
      rotated,
      image.width,
      image.height,
      (image.width - rotated.width) ~/ 2,
      (image.height - rotated.height) ~/ 2,
      backgroundArgb,
      underlay: underlay ?? _lightBlur(image),
    );
  }

  /// Keeps letterbox transparent; scales subject opacity for layered fades.
  static img.Image _fadeSubjectAlpha(img.Image image, double amount) {
    final a = amount.clamp(0.0, 1.0);
    final out = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 4,
    );
    img.fill(out, color: img.ColorRgba8(0, 0, 0, 0));
    for (final pixel in image) {
      if (pixel.a < 8) continue;
      out.setPixelRgba(
        pixel.x,
        pixel.y,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
        (pixel.a * a).round().clamp(0, 255),
      );
    }
    return out;
  }

  static img.Image _fade(img.Image image, double amount, int backgroundArgb) {
    final plate = _lightBlur(image);
    final out = image.clone();
    for (final pixel in out) {
      final bg = plate.getPixel(pixel.x, pixel.y);
      final br = bg.r.toInt();
      final bgc = bg.g.toInt();
      final bb = bg.b.toInt();
      pixel
        ..r = (br + (pixel.r - br) * amount).round().clamp(0, 255)
        ..g = (bgc + (pixel.g - bgc) * amount).round().clamp(0, 255)
        ..b = (bb + (pixel.b - bb) * amount).round().clamp(0, 255);
    }
    return out;
  }

  /// Zoomed crop sweeps up from the bottom, with a sideways smear, then settles sharp.
  static img.Image _wiper(
    img.Image image,
    double t,
    int backgroundArgb, {
    img.Image? underlay,
  }) {
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
    var frame = _place(
      resized,
      w,
      h,
      dx,
      dy,
      backgroundArgb,
      underlay: underlay ?? _lightBlur(image),
    );
    final blur = 1 - p;
    if (blur > 0.12 && underlay == null) {
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

  static img.Image _zoom(
    img.Image image,
    double scale,
    int backgroundArgb, {
    img.Image? underlay,
  }) {
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
    return _place(
      resized,
      w,
      h,
      (w - sw) ~/ 2,
      (h - sh) ~/ 2,
      backgroundArgb,
      underlay: underlay ?? _lightBlur(image),
    );
  }

  static img.Image _place(
    img.Image source,
    int width,
    int height,
    int dx,
    int dy,
    int backgroundArgb, {
    img.Image? underlay,
  }) {
    img.Image? plate;
    if (underlay != null) {
      plate = underlay.width == width && underlay.height == height
          ? underlay
          : img.copyResize(
              underlay,
              width: width,
              height: height,
              interpolation: img.Interpolation.linear,
            );
    } else if (source.width == width && source.height == height) {
      plate = _lightBlur(source);
    }
    final out = plate != null
        ? img.Image.from(plate)
        : img.Image(width: width, height: height, numChannels: 4);
    if (plate == null) {
      img.fill(
        out,
        color: img.ColorRgba8(
          (backgroundArgb >> 16) & 0xFF,
          (backgroundArgb >> 8) & 0xFF,
          backgroundArgb & 0xFF,
          255,
        ),
      );
    }
    final blendAlpha = underlay != null || source.numChannels >= 4;
    for (var y = 0; y < height; y++) {
      final sy = y - dy;
      if (sy < 0 || sy >= source.height) continue;
      for (var x = 0; x < width; x++) {
        final sx = x - dx;
        if (sx < 0 || sx >= source.width) continue;
        final pixel = source.getPixel(sx, sy);
        if (!blendAlpha) {
          out.setPixel(x, y, pixel);
          continue;
        }
        final a = pixel.a.toInt();
        if (a < 8) continue;
        if (a >= 250) {
          out.setPixel(x, y, pixel);
          continue;
        }
        final dst = out.getPixel(x, y);
        final t = a / 255.0;
        out.setPixelRgba(
          x,
          y,
          (dst.r + (pixel.r - dst.r) * t).round().clamp(0, 255),
          (dst.g + (pixel.g - dst.g) * t).round().clamp(0, 255),
          (dst.b + (pixel.b - dst.b) * t).round().clamp(0, 255),
          255,
        );
      }
    }
    return out;
  }
}
