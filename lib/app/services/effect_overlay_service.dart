import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Loads and prepares bundled overlay animations for preview and export.
class EffectOverlayService {
  EffectOverlayService._();

  static const previewFps = 12;

  static final Map<String, Future<List<File>>> _frameJobs = {};
  static final Map<String, Future<String>> _assetCopies = {};

  static (int, int) cappedSize(int w, int h, {int maxSide = 320}) {
    final longest = math.max(w, h);
    if (longest <= maxSide) return (w, h);
    final scale = maxSide / longest;
    return (
      math.max(2, (w * scale).round()),
      math.max(2, (h * scale).round()),
    );
  }

  static Future<String> assetFilePath(String assetPath) {
    return _assetCopies.putIfAbsent(
      assetPath,
      () => _copyAssetToTemp(assetPath),
    );
  }

  static Future<String> _copyAssetToTemp(String assetPath) async {
    final tmp = await getTemporaryDirectory();
    final name = p.basename(assetPath);
    final file = File(p.join(tmp.path, 'clipcraft_fx_$name'));
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  static Future<List<File>> previewFrames({
    required OverlayEffect effect,
    required int width,
    required int height,
  }) async {
    final key = '${effect.id}_${width}x$height';
    try {
      return await _frameJobs.putIfAbsent(
        key,
        () => _extractFrames(effect, width, height),
      );
    } catch (_) {
      _frameJobs.remove(key);
      rethrow;
    }
  }

  static Future<List<File>> _extractFrames(
    OverlayEffect effect,
    int width,
    int height,
  ) async {
    final tmp = await getTemporaryDirectory();
    final outputDir = Directory(
      p.join(
        tmp.path,
        'clipcraft_effect_frames_${effect.id}_${width}x${height}_v2',
      ),
    );
    if (await outputDir.exists()) {
      final existing = await _listFrames(outputDir);
      if (existing.isNotEmpty) return existing;
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final source = await assetFilePath(effect.assetPath);
    final pattern = p.join(outputDir.path, 'effect_%05d.jpg');
    final command =
        '-y -i "${_escape(source)}" '
        '-vf "fps=$previewFps,scale=$width:$height,setsar=1" '
        '-q:v 4 -start_number 1 "${_escape(pattern)}"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Could not prepare effect preview frames: $logs');
    }

    final frames = await _listFrames(outputDir);
    if (frames.isEmpty) throw Exception('Effect video has no decodable frames');
    return frames;
  }

  static Future<List<File>> _listFrames(Directory dir) async {
    final frames = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.jpg')) frames.add(entity);
    }
    frames.sort((a, b) => a.path.compareTo(b.path));
    return frames;
  }

  static String _escape(String value) => value.replaceAll('"', r'\"');

  /// Composites [effect] onto [base] using the effect's blend mode.
  static img.Image compose(
    img.Image base,
    img.Image effect, {
    required OverlayBlendMode blend,
  }) {
    return switch (blend) {
      OverlayBlendMode.screen => screenBlend(base, effect),
      OverlayBlendMode.chromaGreen => chromaKeyBlend(base, effect),
    };
  }

  /// Black pixels leave the slideshow untouched; bright pixels reveal the FX.
  static img.Image screenBlend(img.Image base, img.Image effect) {
    final overlay = effect.width == base.width && effect.height == base.height
        ? effect
        : img.copyResize(
            effect,
            width: base.width,
            height: base.height,
            interpolation: img.Interpolation.linear,
          );
    final result = base.clone();
    for (var y = 0; y < base.height; y++) {
      for (var x = 0; x < base.width; x++) {
        final src = overlay.getPixel(x, y);
        final sr = src.r.toInt();
        final sg = src.g.toInt();
        final sb = src.b.toInt();
        // Skip near-black — keeps photo clean with no haze.
        if (sr < 8 && sg < 8 && sb < 8) continue;
        final dst = base.getPixel(x, y);
        result.setPixelRgba(
          x,
          y,
          _screen(dst.r.toInt(), sr),
          _screen(dst.g.toInt(), sg),
          _screen(dst.b.toInt(), sb),
          255,
        );
      }
    }
    return result;
  }

  /// Green-screen FX: near-green pixels are transparent; others overlay.
  static img.Image chromaKeyBlend(
    img.Image base,
    img.Image effect, {
    int threshold = 70,
  }) {
    final overlay = effect.width == base.width && effect.height == base.height
        ? effect
        : img.copyResize(
            effect,
            width: base.width,
            height: base.height,
            interpolation: img.Interpolation.linear,
          );
    final result = base.clone();
    for (var y = 0; y < base.height; y++) {
      for (var x = 0; x < base.width; x++) {
        final src = overlay.getPixel(x, y);
        final r = src.r.toInt();
        final g = src.g.toInt();
        final b = src.b.toInt();
        // Strong green, low red/blue → treat as transparency.
        if (g > r + threshold && g > b + threshold && g > 80) {
          continue;
        }
        final dst = base.getPixel(x, y);
        // Soft mix so bright particles pop over the photo.
        final a = ((r + g + b) / (3 * 255)).clamp(0.35, 1.0);
        result.setPixelRgba(
          x,
          y,
          _mix(dst.r.toInt(), r, a),
          _mix(dst.g.toInt(), g, a),
          _mix(dst.b.toInt(), b, a),
          255,
        );
      }
    }
    return result;
  }

  static int _screen(int base, int effect) =>
      255 - (((255 - base) * (255 - effect)) ~/ 255);

  static int _mix(int base, int fx, double a) =>
      (base * (1 - a) + fx * a).round().clamp(0, 255);

  /// FFmpeg filter graph fragment that maps slideshow+effect → [screened].
  static String exportFilterComplex({
    required int overlayInputIndex,
    required int width,
    required int height,
    required double fps,
    required OverlayBlendMode blend,
    double clipStartSec = 0,
    double? clipEndSec,
    double timelineStartSec = 0,
    double? timelineEndSec,
  }) {
    final trim = StringBuffer();
    if (clipStartSec > 0.001 || clipEndSec != null) {
      trim.write('trim=');
      if (clipStartSec > 0.001) {
        trim.write('start=${clipStartSec.toStringAsFixed(3)}');
      }
      if (clipEndSec != null) {
        if (clipStartSec > 0.001) trim.write(':');
        trim.write('end=${clipEndSec.toStringAsFixed(3)}');
      }
      trim.write(',setpts=PTS-STARTPTS,');
    }
    final prep =
        '[$overlayInputIndex:v]${trim}fps=${fps.toStringAsFixed(3)},'
        'scale=$width:$height,setsar=1';
    final t0 = timelineStartSec.toStringAsFixed(3);
    final enable = timelineEndSec == null
        ? "enable='gte(t,$t0)'"
        : "enable='between(t,$t0,${timelineEndSec.toStringAsFixed(3)})'";
    return switch (blend) {
      OverlayBlendMode.screen =>
        '$prep[effect];[0:v][effect]blend=all_mode=screen:$enable[screened]',
      OverlayBlendMode.chromaGreen =>
        '$prep,'
            'chromakey=0x00FF00:0.35:0.12[effect];'
            '[0:v][effect]overlay=$enable:format=auto[screened]',
    };
  }

  /// Distance helper kept for tests / tuning.
  static double greenDistance(int r, int g, int b) =>
      math.max(0, g - math.max(r, b)).toDouble();
}
