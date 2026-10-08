import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Loads and prepares the bundled black-background animation for preview and
/// export. The clip is intentionally small and contains no audio.
class EffectOverlayService {
  EffectOverlayService._();

  static const assetPath = 'assets/effects/screen_hearts.mp4';
  static const previewFps = 15;

  static final Map<String, Future<List<File>>> _frameJobs = {};
  static Future<String>? _assetCopy;

  static Future<String> assetFilePath() {
    return _assetCopy ??= _copyAssetToTemp();
  }

  static Future<String> _copyAssetToTemp() async {
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, 'clipcraft_screen_hearts_v1.mp4'));
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return file.path;
  }

  static Future<List<File>> previewFrames({
    required int width,
    required int height,
  }) async {
    final key = '${width}x$height';
    try {
      return await _frameJobs.putIfAbsent(
        key,
        () => _extractFrames(width, height),
      );
    } catch (_) {
      _frameJobs.remove(key);
      rethrow;
    }
  }

  static Future<List<File>> _extractFrames(int width, int height) async {
    final tmp = await getTemporaryDirectory();
    final outputDir = Directory(
      p.join(tmp.path, 'clipcraft_effect_frames_${width}x${height}_v1'),
    );
    if (await outputDir.exists()) {
      final existing = await _listFrames(outputDir);
      if (existing.isNotEmpty) return existing;
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final source = await assetFilePath();
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

  /// Applies the screen blend used by the export filter. Black pixels leave
  /// the slideshow untouched, while bright pixels reveal the effect.
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
        final dst = base.getPixel(x, y);
        final src = overlay.getPixel(x, y);
        result.setPixelRgba(
          x,
          y,
          _screen(dst.r.toInt(), src.r.toInt()),
          _screen(dst.g.toInt(), src.g.toInt()),
          _screen(dst.b.toInt(), src.b.toInt()),
          255,
        );
      }
    }
    return result;
  }

  static int _screen(int base, int effect) =>
      255 - (((255 - base) * (255 - effect)) ~/ 255);
}
