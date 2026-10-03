import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/models.dart';

/// Bakes filters, letterbox BG, frame overlay, text & stickers into frames.
class FrameCompositor {
  static img.Image applyFilter(img.Image src, PhotoFilterPreset preset) {
    if (preset == PhotoFilterPreset.original) return src;
    final out = src.clone();
    switch (preset) {
      case PhotoFilterPreset.vivid:
        img.adjustColor(out, saturation: 1.35, contrast: 1.1);
      case PhotoFilterPreset.warm:
        img.adjustColor(out, saturation: 1.1);
        _tint(out, 1.08, 1.02, 0.92);
      case PhotoFilterPreset.cold:
        img.adjustColor(out, saturation: 0.95);
        _tint(out, 0.92, 1.0, 1.1);
      case PhotoFilterPreset.mono:
        img.grayscale(out);
      case PhotoFilterPreset.fade:
        img.adjustColor(out, contrast: 0.85, brightness: 1.08, saturation: 0.7);
      case PhotoFilterPreset.original:
        break;
    }
    return out;
  }

  static void _tint(img.Image image, double rM, double gM, double bM) {
    for (final p in image) {
      p
        ..r = (p.r * rM).clamp(0, 255).round()
        ..g = (p.g * gM).clamp(0, 255).round()
        ..b = (p.b * bM).clamp(0, 255).round();
    }
  }

  /// Places [src] into [w]x[h] canvas with [bgArgb], cover-fit.
  static img.Image placeOnCanvas({
    required img.Image src,
    required int w,
    required int h,
    required int bgArgb,
  }) {
    final canvas = img.Image(width: w, height: h);
    final a = (bgArgb >> 24) & 0xFF;
    final r = (bgArgb >> 16) & 0xFF;
    final g = (bgArgb >> 8) & 0xFF;
    final b = bgArgb & 0xFF;
    img.fill(
      canvas,
      color: img.ColorRgba8(r, g, b, a == 0 ? 255 : a),
    );

    final scale = (w / src.width > h / src.height)
        ? w / src.width
        : h / src.height;
    final nw = (src.width * scale).round();
    final nh = (src.height * scale).round();
    final resized = img.copyResize(src, width: nw, height: nh);
    final dx = ((w - nw) / 2).round();
    final dy = ((h - nh) / 2).round();
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
    return canvas;
  }

  static Future<img.Image> bakeOverlays({
    required img.Image base,
    String? frameAsset,
    required List<SlideOverlay> overlays,
  }) async {
    var result = base;

    if (frameAsset != null) {
      final data = await rootBundle.load(frameAsset);
      final frame = img.decodeImage(data.buffer.asUint8List());
      if (frame != null) {
        final resized = img.copyResize(
          frame,
          width: base.width,
          height: base.height,
        );
        img.compositeImage(result, resized);
      }
    }

    if (overlays.isEmpty) return result;

    // Draw text/stickers via Flutter canvas → PNG → composite
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(base.width.toDouble(), base.height.toDouble());
    // Transparent layer
    final paint = ui.Paint()..color = const ui.Color(0x00000000);
    canvas.drawRect(ui.Offset.zero & size, paint);

    for (final o in overlays) {
      final cx = o.nx * size.width;
      final cy = o.ny * size.height;
      if (o.kind == OverlayKind.text && (o.text?.isNotEmpty ?? false)) {
        final color = Color(o.colorArgb);
        final tp = TextPainter(
          text: TextSpan(
            text: o.text,
            style: TextStyle(
              color: color,
              fontSize: 36 * o.scale,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(blurRadius: 6, color: Color(0x88000000)),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width * 0.9);
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, cy - tp.height / 2),
        );
      } else if (o.kind == OverlayKind.sticker &&
          (o.stickerEmoji?.isNotEmpty ?? false)) {
        final tp = TextPainter(
          text: TextSpan(
            text: o.stickerEmoji,
            style: TextStyle(fontSize: 56 * o.scale),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(cx - tp.width / 2, cy - tp.height / 2),
        );
      }
    }

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(base.width, base.height);
    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return result;
    final overlayImg = img.decodePng(byteData.buffer.asUint8List());
    if (overlayImg != null) {
      img.compositeImage(result, overlayImg);
    }
    return result;
  }

  static Future<img.Image> makeTitleCard({
    required TitleCard card,
    required int w,
    required int h,
  }) async {
    final bg = card.backgroundArgb;
    final canvas = img.Image(width: w, height: h);
    img.fill(
      canvas,
      color: img.ColorRgba8(
        (bg >> 16) & 0xFF,
        (bg >> 8) & 0xFF,
        bg & 0xFF,
        255,
      ),
    );

    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    final size = ui.Size(w.toDouble(), h.toDouble());
    c.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = ui.Color(bg | 0xFF000000),
    );

    final title = TextPainter(
      text: TextSpan(
        text: card.title,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.85);

    title.paint(
      c,
      Offset(
        (size.width - title.width) / 2,
        size.height * 0.42 - title.height / 2,
      ),
    );

    if (card.subtitle.isNotEmpty) {
      final sub = TextPainter(
        text: TextSpan(
          text: card.subtitle,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * 0.85);
      sub.paint(
        c,
        Offset(
          (size.width - sub.width) / 2,
          size.height * 0.42 + title.height / 2 + 12,
        ),
      );
    }

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(w, h);
    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return canvas;
    final drawn = img.decodePng(Uint8List.view(byteData.buffer));
    return drawn ?? canvas;
  }
}
