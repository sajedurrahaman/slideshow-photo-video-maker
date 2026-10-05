import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/models.dart';

/// Custom slide transition engine (Flutter port of MaskBitmap3D-style effects).
/// Generates blended frames between two images for preview/export.
class TransitionEngine {
  TransitionEngine._();

  static img.Image apply({
    required img.Image from,
    required img.Image to,
    required SlideTransitionType type,
    required double progress, // 0.0 -> 1.0
    int gridCols = 12,
    int gridRows = 20,
    bool reverseDiagonal = false,
    bool topToBottom = false,
    double pivotNx = 0.5,
    double pivotNy = 0.5,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final a = _ensureSameSize(from, to.width, to.height);
    final b = _ensureSameSize(to, to.width, to.height);

    switch (type) {
      case SlideTransitionType.none:
        // Hard cut — no blend between slides.
        return p < 1.0 ? a : b;
      case SlideTransitionType.crossfade:
      case SlideTransitionType.dipToColor:
      case SlideTransitionType.filterColor:
        return _crossfade(a, b, p);
      case SlideTransitionType.erase:
        // Native MaskBitmap3D.eraseDraw (EFFECT.Erase) — soft-edge L→R wipe.
        return _softEraseWipe(a, b, p);
      case SlideTransitionType.eraseSlide:
        // Erase_Slide: same wipe direction family, hard edge (no feather).
        return _wipe(a, b, p, horizontal: true);
      case SlideTransitionType.pixelEffect:
        return _diamondDissolve(
          a,
          b,
          p,
          cols: gridCols,
          rows: gridRows,
          reverseDiagonal: reverseDiagonal,
          topToBottom: topToBottom,
        );
      case SlideTransitionType.pixelScatter:
        // Scattered mosaic squares (slide_11 icon).
        return _randomPixelDissolve(a, b, p, cols: gridCols, rows: gridRows);
      case SlideTransitionType.pixelGrid:
        // Uniform grid cells (slide_12 icon) — solid squares, diagonal order.
        return _gridDissolve(a, b, p, cols: gridCols, rows: gridRows);
      case SlideTransitionType.bar:
        // Horizontal blinds (top → bottom within each row strip).
        return _blinds(a, b, p, verticalStrips: false, rightToLeft: false);
      case SlideTransitionType.jalousie:
        // Icon: vertical columns — wipe right → left (not top → bottom).
        return _blinds(a, b, p, verticalStrips: true, rightToLeft: true);
      case SlideTransitionType.crossMerge:
        return _crossMerge(a, b, p);
      case SlideTransitionType.rowColSplit:
        // Hinge at (pivotNx, pivotNy) — lines start together then split apart.
        return _rowColSplit(a, b, p, pivotNx: pivotNx, pivotNy: pivotNy);
      case SlideTransitionType.rectZoomIn:
        // Green-mark / slide_06: NEW expands from bottom-right over OLD.
        return _cornerExpandBr(a, b, p);
      case SlideTransitionType.rectZoomCenter:
      case SlideTransitionType.zoomIn:
        // Concentric icon / slide_09: NEW from border inward; center hole = shrinking OLD.
        return _rectZoom(a, b, p, zoomIn: true);
      case SlideTransitionType.rectZoomOut:
        // Center NEW rect grows; OLD zooms out behind.
        return _rectZoom(a, b, p, zoomIn: false);
      case SlideTransitionType.zoomOut:
        return _rectZoom(a, b, p, zoomIn: false);
      case SlideTransitionType.crossShutter:
        return _crossShutter(a, b, p);
      case SlideTransitionType.rowSplit:
        return _split(a, b, p, rows: true);
      case SlideTransitionType.colSplit:
        return _split(a, b, p, rows: false);
      case SlideTransitionType.flipPageRight:
        return _flipPage(a, b, p);
      case SlideTransitionType.curvedDown:
        return _wipe(a, b, p, horizontal: false, curved: true);
      case SlideTransitionType.tiltDrift:
        return _tiltDrift(a, b, p);
      case SlideTransitionType.whole3dTb:
        // Native drawRollWhole3D vertical TB — new swings in from top.
        return _whole3dFold(a, b, p, bottomToTop: false);
      case SlideTransitionType.whole3dBt:
        // Exact opposite of TB — new swings in from bottom.
        return _whole3dFold(a, b, p, bottomToTop: true);
    }
  }

  static img.Image _ensureSameSize(img.Image src, int w, int h) {
    if (src.width == w && src.height == h) return src;
    return img.copyResize(
      src,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }

  static img.Image _crossfade(img.Image a, img.Image b, double p) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final ca = a.getPixel(x, y);
        final cb = b.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          _lerp(ca.r.toInt(), cb.r.toInt(), p),
          _lerp(ca.g.toInt(), cb.g.toInt(), p),
          _lerp(ca.b.toInt(), cb.b.toInt(), p),
          255,
        );
      }
    }
    return out;
  }

  static img.Image _wipe(
    img.Image a,
    img.Image b,
    double p, {
    required bool horizontal,
    bool curved = false,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        double threshold;
        if (horizontal) {
          threshold = x / a.width;
        } else if (curved) {
          final nx = (x / a.width) - 0.5;
          threshold = (y / a.height) + nx * nx * 0.35;
        } else {
          threshold = y / a.height;
        }
        final useB = threshold < p;
        final c = useB ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Native Erase: full new image, keep old from wipeX→right, soft feather band
  /// of width ≈ VIDEO_WIDTH/8 before the wipe line (LinearGradient-like blend).
  static img.Image _softEraseWipe(
    img.Image oldImg,
    img.Image newImg,
    double progress,
  ) {
    final w = oldImg.width;
    final h = oldImg.height;
    final out = img.Image.from(newImg);
    final wipeX = (w * progress).round().clamp(0, w);
    final feather = math.max(1, w ~/ 8);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (x >= wipeX) {
          final c = oldImg.getPixel(x, y);
          out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
        } else if (wipeX > 0 && x >= wipeX - feather) {
          // Soft edge: old fades out toward wipe line (transparent→opaque on old).
          final t = ((wipeX - x) / feather).clamp(0.0, 1.0);
          final oc = oldImg.getPixel(x, y);
          final nc = newImg.getPixel(x, y);
          out.setPixelRgba(
            x,
            y,
            (oc.r * t + nc.r * (1 - t)).round(),
            (oc.g * t + nc.g * (1 - t)).round(),
            (oc.b * t + nc.b * (1 - t)).round(),
            255,
          );
        }
        // else: already new image from Image.from(newImg)
      }
    }
    return out;
  }

  /// Diamond/pixel dissolve: cells grow from a corner / edge.
  static img.Image _diamondDissolve(
    img.Image a,
    img.Image b,
    double t, {
    int cols = 12,
    int rows = 20,
    bool reverseDiagonal = false,
    bool topToBottom = false,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final cw = a.width / cols;
    final ch = a.height / rows;
    final maxD = (cols + rows - 2).toDouble().clamp(1, 9999);
    final rowMax = math.max(1, rows - 1).toDouble();

    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final c = (x / cw).floor().clamp(0, cols - 1);
        final r = (y / ch).floor().clamp(0, rows - 1);
        final delay = topToBottom
            ? r /
                  rowMax // top rows first → bottom
            : reverseDiagonal
            ? ((cols - 1 - c) + r) / maxD
            : (c + (rows - 1 - r)) / maxD;
        final cellP = ((t - delay * 0.6) / 0.4).clamp(0.0, 1.0);

        var useB = false;
        if (cellP > 0) {
          final cx = c * cw + cw / 2;
          final cy = r * ch + ch / 2;
          final hw = cw * cellP;
          final hh = ch * cellP;
          // Point-in-diamond: |dx|/hw + |dy|/hh <= 1
          useB = ((x - cx).abs() / hw) + ((y - cy).abs() / hh) <= 1.0;
        }

        final px = useB ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Random mosaic dissolve — cells flip in pseudo-random order.
  static img.Image _randomPixelDissolve(
    img.Image a,
    img.Image b,
    double t, {
    int cols = 22,
    int rows = 22,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final cw = a.width / cols;
    final ch = a.height / rows;

    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final c = (x / cw).floor().clamp(0, cols - 1);
        final r = (y / ch).floor().clamp(0, rows - 1);
        // Deterministic 0..1 threshold per cell (stable across frames).
        final hash =
            ((c * 73856093) ^ (r * 19349663) ^ (c * r * 83492791)) & 0x7fffffff;
        final thresh = (hash % 10000) / 10000.0;
        final useB = t >= thresh;
        final px = useB ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(x, y, px.r.toInt(), px.g.toInt(), px.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Grid mosaic (slide_12) — matches native ClipCraft preview/video:
  /// 1) Image slices into a grid with dark gaps
  /// 2) Solid cells flip OLD→NEW from bottom-right → top-left
  /// 3) Gaps close at the end
  static img.Image _gridDissolve(
    img.Image a,
    img.Image b,
    double t, {
    int cols = 8,
    int rows = 8,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final cw = a.width / cols;
    final ch = a.height / rows;
    final maxD = (cols + rows - 2).toDouble().clamp(1, 9999);

    // Gap opens quickly, stays through mid, closes at end.
    final gapOpen = (t / 0.18).clamp(0.0, 1.0);
    final gapClose = t > 0.82 ? (1.0 - (t - 0.82) / 0.18).clamp(0.0, 1.0) : 1.0;
    final gapFrac = 0.14 * gapOpen * gapClose; // inset as fraction of cell
    final gapX = cw * gapFrac * 0.5;
    final gapY = ch * gapFrac * 0.5;

    // Flip wave starts after initial slice; BR cells first.
    final revealT = ((t - 0.12) / 0.78).clamp(0.0, 1.0);

    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final c = (x / cw).floor().clamp(0, cols - 1);
        final r = (y / ch).floor().clamp(0, rows - 1);
        final cellLeft = c * cw;
        final cellTop = r * ch;

        // Dark gutter between tiles (native sliced-grid look).
        if (gapX > 0.5 &&
            (x < cellLeft + gapX ||
                x >= cellLeft + cw - gapX ||
                y < cellTop + gapY ||
                y >= cellTop + ch - gapY)) {
          out.setPixelRgba(x, y, 12, 16, 28, 255);
          continue;
        }

        // Bottom-right → top-left stagger (matches reference video).
        final delay = ((cols - 1 - c) + (rows - 1 - r)) / maxD;
        final useB = revealT >= (delay * 0.88);
        final px = useB ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          px.r.toInt(),
          px.g.toInt(),
          px.b.toInt(),
          255,
        );
      }
    }
    return out;
  }

  /// Blinds / jalousie.
  /// [verticalStrips] true = columns (slide_08 icon); false = horizontal rows.
  /// [rightToLeft] wipe + stagger from the right.
  static img.Image _blinds(
    img.Image a,
    img.Image b,
    double p, {
    required bool verticalStrips,
    bool rightToLeft = false,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    const strips = 8;
    final stripSize = (verticalStrips ? a.width : a.height) / strips;

    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final along = verticalStrips ? x : y;
        final strip = (along / stripSize).floor().clamp(0, strips - 1);
        final inStrip = (along - strip * stripSize) / stripSize;
        final local = (verticalStrips && rightToLeft)
            ? (1.0 - inStrip)
            : inStrip;
        final order = (verticalStrips && rightToLeft)
            ? (strips - 1 - strip)
            : strip;
        final open = (p * 1.25 - order * 0.04).clamp(0.0, 1.0);
        final c = (local < open) ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Native Cross_Merge (MaskBitmap3D.barDraw) — matches reference video.
  ///
  /// 1) NEW full underneath
  /// 2) OLD drawn on top with 4 growing corner holes (DST_OUT)
  /// → corners reveal NEW; center “+” of OLD shrinks until gone
  ///
  /// Native size ≈ W * (0.025 * frame + 0.1), frame 0…21
  static img.Image _crossMerge(img.Image oldImg, img.Image newImg, double p) {
    if (p <= 0.0) return img.Image.from(oldImg);
    if (p >= 1.0) return img.Image.from(newImg);

    final w = oldImg.width;
    final h = oldImg.height;
    final out = img.Image.from(newImg);

    final i = p * 21.0;
    // Grow until corners meet past center (full cover).
    var cw = (w * (0.025 * i + 0.1)).round();
    var ch = (h * (0.025 * i + 0.1)).round();
    // Ease last stretch so p→1 clears remaining OLD +
    if (p > 0.85) {
      final t = ((p - 0.85) / 0.15).clamp(0.0, 1.0);
      cw = (cw + ((w / 2 + 2) - cw) * t).round();
      ch = (ch + ((h / 2 + 2) - ch) * t).round();
    }
    cw = cw.clamp(0, w);
    ch = ch.clamp(0, h);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inTl = x < cw && y < ch;
        final inTr = x >= w - cw && y < ch;
        final inBl = x < cw && y >= h - ch;
        final inBr = x >= w - cw && y >= h - ch;
        if (inTl || inTr || inBl || inBr) {
          continue; // hole → NEW already in [out]
        }
        final c = oldImg.getPixel(x, y);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Row + Col split with hinge at [pivotNx],[pivotNy] (0–1).
  /// At p=0 both seams sit on the hinge (green-circle meet point);
  /// as p→1 seams move to the four edges → NEW fills the expanding “+”.
  static img.Image _rowColSplit(
    img.Image oldImg,
    img.Image newImg,
    double p, {
    double pivotNx = 0.5,
    double pivotNy = 0.5,
  }) {
    if (p <= 0.0) return img.Image.from(oldImg);
    if (p >= 1.0) return img.Image.from(newImg);

    final w = oldImg.width;
    final h = oldImg.height;
    final out = img.Image.from(newImg);

    final px = (pivotNx.clamp(0.05, 0.95) * w);
    final py = (pivotNy.clamp(0.05, 0.95) * h);

    // Seams start together at hinge, then move apart to edges.
    final leftEdge = (px * (1.0 - p)).round().clamp(0, w);
    final rightEdge = (px + (w - px) * p).round().clamp(0, w);
    final topEdge = (py * (1.0 - p)).round().clamp(0, h);
    final bottomEdge = (py + (h - py) * p).round().clamp(0, h);

    final slideXL = (px - leftEdge).round().clamp(0, w); // = px * p
    final slideXR = (rightEdge - px).round().clamp(0, w); // = (w-px) * p
    final slideYT = (py - topEdge).round().clamp(0, h);
    final slideYB = (bottomEdge - py).round().clamp(0, h);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inVGap = x >= leftEdge && x < rightEdge;
        final inHGap = y >= topEdge && y < bottomEdge;
        if (inVGap || inHGap) continue; // NEW “+” around hinge

        late final int sx;
        late final int sy;
        if (x < leftEdge && y < topEdge) {
          sx = (x + slideXL).clamp(0, w - 1);
          sy = (y + slideYT).clamp(0, h - 1);
        } else if (x >= rightEdge && y < topEdge) {
          sx = (x - slideXR).clamp(0, w - 1);
          sy = (y + slideYT).clamp(0, h - 1);
        } else if (x < leftEdge && y >= bottomEdge) {
          sx = (x + slideXL).clamp(0, w - 1);
          sy = (y - slideYB).clamp(0, h - 1);
        } else {
          sx = (x - slideXR).clamp(0, w - 1);
          sy = (y - slideYB).clamp(0, h - 1);
        }
        final c = oldImg.getPixel(sx, sy);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  /// slide_06 / Zoom_In icon: NEW expands from bottom-right over OLD.
  /// Mid-frame = small NEW square flush BR + L-shaped OLD (matches icon).
  static img.Image _cornerExpandBr(
    img.Image oldImg,
    img.Image newImg,
    double p,
  ) {
    final w = oldImg.width;
    final h = oldImg.height;
    if (p <= 0.0) return img.Image.from(oldImg);
    if (p >= 1.0) return img.Image.from(newImg);

    final out = img.Image.from(oldImg);
    final rw = math.max(1, (w * p).round());
    final rh = math.max(1, (h * p).round());
    final left = w - rw;
    final top = h - rh;

    for (var y = top; y < h; y++) {
      for (var x = left; x < w; x++) {
        // Scale full NEW into the growing BR rect (picture-in-picture expand).
        final u = (x - left) / rw;
        final v = (y - top) / rh;
        final sx = (u * (w - 1)).round().clamp(0, w - 1);
        final sy = (v * (h - 1)).round().clamp(0, h - 1);
        final c = newImg.getPixel(sx, sy);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  /// Native center Rect_Zoom_In / Rect_Zoom_Out.
  /// In: NEW fills outside, center hole shows OLD shrinking (scale 1→0.7).
  /// Out: OLD zooms out behind, center NEW rect grows 0→full.
  static img.Image _rectZoom(
    img.Image oldImg,
    img.Image newImg,
    double p, {
    required bool zoomIn,
  }) {
    final w = oldImg.width;
    final h = oldImg.height;
    final cx = w / 2.0;
    final cy = h / 2.0;
    final out = img.Image(width: w, height: h, numChannels: 4);

    if (zoomIn) {
      // Native Rect_Zoom_In: scaleFactor = 1 - 0.014*i; hole ≈ (1-p)
      final scale = (1.0 - 0.3 * p).clamp(0.2, 1.0);
      final holeW = (w * (1.0 - p)).round().clamp(0, w);
      final holeH = (h * (1.0 - p)).round().clamp(0, h);
      final left = (w - holeW) ~/ 2;
      final top = (h - holeH) ~/ 2;

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inHole =
              holeW > 0 &&
              holeH > 0 &&
              x >= left &&
              x < left + holeW &&
              y >= top &&
              y < top + holeH;
          if (inHole) {
            final sx = ((x - cx) / scale + cx).round().clamp(0, w - 1);
            final sy = ((y - cy) / scale + cy).round().clamp(0, h - 1);
            final c = oldImg.getPixel(sx, sy);
            out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
          } else {
            final c = newImg.getPixel(x, y);
            out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
          }
        }
      }
    } else {
      // Native Rect_Zoom_Out: old scale 1+0.014*i; center NEW mask grows.
      final scale = 1.0 + 0.3 * p;
      final rw = (w * p).round().clamp(0, w);
      final rh = (h * p).round().clamp(0, h);
      final left = (w - rw) ~/ 2;
      final top = (h - rh) ~/ 2;

      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final inRect =
              rw > 0 &&
              rh > 0 &&
              x >= left &&
              x < left + rw &&
              y >= top &&
              y < top + rh;
          if (inRect) {
            final c = newImg.getPixel(x, y);
            out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
          } else {
            final sx = ((x - cx) / scale + cx).round().clamp(0, w - 1);
            final sy = ((y - cy) / scale + cy).round().clamp(0, h - 1);
            final c = oldImg.getPixel(sx, sy);
            out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
          }
        }
      }
    }
    return out;
  }

  static img.Image _crossShutter(img.Image a, img.Image b, double p) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    const cell = 24;
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final cx = x ~/ cell;
        final cy = y ~/ cell;
        final localX = (x % cell) / cell;
        final localY = (y % cell) / cell;
        final odd = (cx + cy).isOdd;
        final open = odd ? localX < p : localY < p;
        final c = open ? b.getPixel(x, y) : a.getPixel(x, y);
        out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
      }
    }
    return out;
  }

  static img.Image _split(
    img.Image a,
    img.Image b,
    double p, {
    required bool rows,
  }) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final offset = rows
        ? (a.height * p / 2).round()
        : (a.width * p / 2).round();
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        img.Pixel c;
        if (rows) {
          if (y < a.height / 2) {
            final sy = (y - offset).clamp(0, a.height - 1);
            c = y - offset < 0 ? b.getPixel(x, y) : a.getPixel(x, sy);
            if (p > 0.5 && y < offset) c = b.getPixel(x, y);
          } else {
            final sy = (y + offset).clamp(0, a.height - 1);
            c = y + offset >= a.height ? b.getPixel(x, y) : a.getPixel(x, sy);
            if (p > 0.5 && y >= a.height - offset) c = b.getPixel(x, y);
          }
        } else {
          if (x < a.width / 2) {
            final sx = (x - offset).clamp(0, a.width - 1);
            c = x - offset < 0 ? b.getPixel(x, y) : a.getPixel(sx, y);
            if (p > 0.5 && x < offset) c = b.getPixel(x, y);
          } else {
            final sx = (x + offset).clamp(0, a.width - 1);
            c = x + offset >= a.width ? b.getPixel(x, y) : a.getPixel(sx, y);
            if (p > 0.5 && x >= a.width - offset) c = b.getPixel(x, y);
          }
        }
        // Soft blend toward B in second half
        if (p > 0.55) {
          final t = ((p - 0.55) / 0.45).clamp(0.0, 1.0);
          final cb = b.getPixel(x, y);
          out.setPixelRgba(
            x,
            y,
            _lerp(c.r.toInt(), cb.r.toInt(), t),
            _lerp(c.g.toInt(), cb.g.toInt(), t),
            _lerp(c.b.toInt(), cb.b.toInt(), t),
            255,
          );
        } else {
          out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
        }
      }
    }
    return out;
  }

  /// Whole3D vertical fold (native Camera.rotateX).
  /// [bottomToTop] false = TB (green): new from top; true = BT (blue): opposite.
  static img.Image _whole3dFold(
    img.Image oldImg,
    img.Image newImg,
    double p, {
    required bool bottomToTop,
  }) {
    if (p <= 0.001) return img.Image.from(oldImg);
    if (p >= 0.999) return img.Image.from(newImg);

    final w = oldImg.width;
    final h = oldImg.height;
    final out = img.Image(width: w, height: h, numChannels: 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        out.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }

    final angle = p * (math.pi / 2); // 0° → 90°
    final cosA = math.cos(angle).clamp(0.02, 1.0); // outgoing scale
    final sinA = math.sin(angle).clamp(0.02, 1.0); // incoming scale
    const persp = 0.55;

    void blitFace({
      required img.Image src,
      required int y0,
      required int faceH,
      required double shade,
      required bool taperTop,
      required double edgeOn,
    }) {
      if (faceH < 1) return;
      for (var y = y0; y < y0 + faceH && y < h; y++) {
        if (y < 0) continue;
        final v = ((y - y0) / faceH).clamp(0.0, 1.0);
        final sy = (v * (h - 1)).round().clamp(0, h - 1);
        final far = taperTop ? (1.0 - v) : v;
        final taper = 1.0 - far * persp * edgeOn;
        final drawW = (w * taper).clamp(1.0, w.toDouble());
        final x0 = ((w - drawW) / 2).round();
        final x1 = (x0 + drawW).round().clamp(x0 + 1, w);
        final span = (x1 - x0).clamp(1, w);
        for (var x = x0; x < x1; x++) {
          if (x < 0 || x >= w) continue;
          final u = ((x - x0) / span).clamp(0.0, 1.0);
          final sx = (u * (w - 1)).round().clamp(0, w - 1);
          final c = src.getPixel(sx, sy);
          out.setPixelRgba(
            x,
            y,
            (c.r.toInt() * shade).round().clamp(0, 255),
            (c.g.toInt() * shade).round().clamp(0, 255),
            (c.b.toInt() * shade).round().clamp(0, 255),
            255,
          );
        }
      }
    }

    final oldH = (h * cosA).round().clamp(1, h);
    final newH = (h * sinA).round().clamp(1, h);

    if (!bottomToTop) {
      // TB (green): old bottom-aligned; new from top.
      blitFace(
        src: oldImg,
        y0: h - oldH,
        faceH: oldH,
        shade: 0.62 + 0.38 * cosA,
        taperTop: true,
        edgeOn: math.sin(angle),
      );
      blitFace(
        src: newImg,
        y0: 0,
        faceH: newH,
        shade: 0.62 + 0.38 * sinA,
        taperTop: true,
        edgeOn: math.cos(angle),
      );
    } else {
      // BT (blue): exact opposite — old top-aligned; new from bottom.
      blitFace(
        src: oldImg,
        y0: 0,
        faceH: oldH,
        shade: 0.62 + 0.38 * cosA,
        taperTop: false, // far edge at bottom
        edgeOn: math.sin(angle),
      );
      blitFace(
        src: newImg,
        y0: h - newH,
        faceH: newH,
        shade: 0.62 + 0.38 * sinA,
        taperTop: false,
        edgeOn: math.cos(angle),
      );
    }

    return out;
  }

  static img.Image _flipPage(img.Image a, img.Image b, double p) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final fold = (a.width * p).round();
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        if (x < a.width - fold) {
          final c = a.getPixel(x, y);
          out.setPixelRgba(x, y, c.r.toInt(), c.g.toInt(), c.b.toInt(), 255);
        } else {
          // mirrored curl-ish look
          final srcX = (2 * (a.width - fold) - x).clamp(0, a.width - 1);
          final shade = (0.7 + 0.3 * (1 - p));
          final c = b.getPixel(srcX, y);
          out.setPixelRgba(
            x,
            y,
            (c.r.toInt() * shade).round().clamp(0, 255),
            (c.g.toInt() * shade).round().clamp(0, 255),
            (c.b.toInt() * shade).round().clamp(0, 255),
            255,
          );
        }
      }
    }
    return out;
  }

  static img.Image _tiltDrift(img.Image a, img.Image b, double p) {
    final out = img.Image(width: a.width, height: a.height, numChannels: 4);
    final dx = (a.width * 0.25 * p).round();
    for (var y = 0; y < a.height; y++) {
      final rowShift = ((y / a.height - 0.5) * 40 * p).round();
      for (var x = 0; x < a.width; x++) {
        final ax = (x + dx + rowShift).clamp(0, a.width - 1);
        final ca = a.getPixel(ax, y);
        final cb = b.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          _lerp(ca.r.toInt(), cb.r.toInt(), p),
          _lerp(ca.g.toInt(), cb.g.toInt(), p),
          _lerp(ca.b.toInt(), cb.b.toInt(), p),
          255,
        );
      }
    }
    return out;
  }

  static int _lerp(int a, int b, double t) =>
      (a + (b - a) * t).round().clamp(0, 255);

  static Uint8List encodeJpeg(img.Image image, {int quality = 85}) {
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  static img.Image? decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Apply EXIF orientation so phone photos show upright and full.
    return img.bakeOrientation(decoded);
  }

  static img.Image coverCrop(img.Image src, int w, int h) {
    final scale = math.max(w / src.width, h / src.height);
    final rw = math.max(1, (src.width * scale).round());
    final rh = math.max(1, (src.height * scale).round());
    final resized = img.copyResize(
      src,
      width: rw,
      height: rh,
      interpolation: img.Interpolation.linear,
    );
    final x = ((rw - w) / 2).round().clamp(0, math.max(0, rw - w)).toInt();
    final y = ((rh - h) / 2).round().clamp(0, math.max(0, rh - h)).toInt();
    return img.copyCrop(resized, x: x, y: y, width: w, height: h);
  }
}
