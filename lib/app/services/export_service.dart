import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import 'slideshow_project.dart';

class ExportService {
  /// Exports generated frames + optional music into MP4.
  /// Saves into app creations folder (My Creation) and gallery.
  static Future<File> export(SlideshowProject project) async {
    if (project.generatedFrames.isEmpty) {
      await project.generatePreviewFrames();
    }
    if (project.generatedFrames.isEmpty) {
      throw Exception('No frames to export');
    }

    final docs = await getApplicationDocumentsDirectory();
    final creations = Directory(p.join(docs.path, AppConstants.creationsFolder));
    if (!await creations.exists()) {
      await creations.create(recursive: true);
    }

    final stamp = DateFormat('dd_MM_yyyy_HH_mm_ss').format(DateTime.now());
    final output = File(p.join(creations.path, 'video_$stamp.mp4'));
    if (await output.exists()) await output.delete();

    final framesDir = project.generatedFrames.first.parent.path;
    final fps = 22.0 / project.slideDurationSec;

    String? musicPath;
    final music = project.music;
    if (music != null) {
      if (music.isAsset) {
        musicPath = await _copyAssetToTemp(music.path);
      } else {
        musicPath = music.path;
      }
    }

    final volumeFilter = (music != null && music.volume < 100)
        ? ' -af volume=${(music.volume / 100.0).toStringAsFixed(2)}'
        : '';

    final cmd = StringBuffer()
      ..write('-y -framerate ${fps.toStringAsFixed(3)} ')
      ..write('-i $framesDir/img%05d.jpg ');

    if (musicPath != null) {
      cmd.write('-stream_loop -1 -i "$musicPath" ');
    }

    cmd.write('-c:v libx264 -pix_fmt yuv420p -r 30 ');
    if (musicPath != null) {
      cmd.write('-c:a aac -shortest$volumeFilter ');
    }
    cmd.write('-preset ultrafast -t ${project.estimatedDurationSec.toStringAsFixed(2)} ');
    cmd.write('"${output.path}"');

    final session = await FFmpegKit.execute(cmd.toString());
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('FFmpeg export failed: $logs');
    }

    // Save to device gallery as well
    try {
      await Gal.putVideo(output.path, album: AppConstants.appName);
    } catch (_) {
      // Gallery save is best-effort; local My Creation still keeps the file.
    }

    return output;
  }

  static Future<List<File>> listCreations() async {
    final docs = await getApplicationDocumentsDirectory();
    final creations = Directory(p.join(docs.path, AppConstants.creationsFolder));
    if (!await creations.exists()) return [];

    final files = <File>[];
    await for (final entity in creations.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.mp4')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) return files;

    final dated = await Future.wait(
      files.map((f) async => MapEntry(f, await f.lastModified())),
    );
    dated.sort((a, b) => b.value.compareTo(a.value));
    return dated.map((e) => e.key).toList();
  }

  static Future<String> _copyAssetToTemp(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, p.basename(assetPath)));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
