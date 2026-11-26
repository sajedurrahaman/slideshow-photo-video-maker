import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';

class VideoEditorExportClip {
  const VideoEditorExportClip({
    required this.path,
    required this.sourceDurationSec,
    required this.trimInSec,
    required this.trimOutSec,
    required this.volume,
    required this.speed,
    this.revealColorAssetPath,
    this.revealAlphaAssetPath,
    this.revealAssetDurationSec,
    this.revealDurationSec,
  });

  final String path;
  final double sourceDurationSec;
  final double trimInSec;
  final double trimOutSec;
  final double volume;
  final double speed;
  final String? revealColorAssetPath;
  final String? revealAlphaAssetPath;
  final double? revealAssetDurationSec;
  final double? revealDurationSec;
}

/// Exports the Video Editor timeline, including clip-start In animations.
class VideoEditorExportService {
  VideoEditorExportService._();

  static const _fps = 30;
  static final Map<String, Future<String>> _assetCopies = {};

  static Future<File> export({
    required List<VideoEditorExportClip> clips,
    required double aspectRatio,
  }) async {
    if (clips.isEmpty) throw Exception('Add a video clip first.');

    final inputs = <String>[];
    final graph = <String>[];
    final clipInputs = <int>[];
    final audioInputs = <bool>[];
    var nextInput = 0;

    for (final clip in clips) {
      clipInputs.add(nextInput++);
      inputs.add('-i "${_escape(clip.path)}"');
      audioInputs.add(await _hasAudio(clip.path));
    }

    final revealInputs = <({int color, int matte})?>[];
    for (final clip in clips) {
      final colorAsset = clip.revealColorAssetPath;
      final matteAsset = clip.revealAlphaAssetPath;
      if (colorAsset == null || matteAsset == null) {
        revealInputs.add(null);
        continue;
      }
      final colorPath = await _copyAsset(colorAsset);
      final mattePath = await _copyAsset(matteAsset);
      final color = nextInput++;
      final matte = nextInput++;
      inputs.add('-i "${_escape(colorPath)}"');
      inputs.add('-i "${_escape(mattePath)}"');
      revealInputs.add((color: color, matte: matte));
    }

    final ratio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 9 / 16;
    final width = ratio >= 1 ? 1920 : 1080;
    final height = ratio >= 1
        ? (width / ratio).round().clamp(2, 1920)
        : (width / ratio).round().clamp(2, 1920);
    final outWidth = width.isEven ? width : width - 1;
    final outHeight = height.isEven ? height : height - 1;

    final durations = <double>[];
    final videoLabels = <String>[];
    final audioLabels = <String>[];

    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final sourceDuration = math.max(0.1, clip.sourceDurationSec);
      final start = clip.trimInSec.clamp(0.0, sourceDuration - 0.05);
      final end = clip.trimOutSec.clamp(start + 0.05, sourceDuration);
      final speed = clip.speed.clamp(0.5, 2.0);
      final outputDuration = (end - start) / speed;
      durations.add(outputDuration);

      final baseLabel = 'base$i';
      graph.add(
        '[${clipInputs[i]}:v:0]'
        'trim=start=${_n(start)}:end=${_n(end)},'
        'setpts=(PTS-STARTPTS)/${_n(speed)},'
        'scale=$outWidth:$outHeight:force_original_aspect_ratio=decrease,'
        'pad=$outWidth:$outHeight:(ow-iw)/2:(oh-ih)/2:black,'
        'setsar=1,fps=$_fps,format=yuv420p[$baseLabel]',
      );

      final revealInput = revealInputs[i];
      final revealColorAsset = clip.revealColorAssetPath;
      final revealAssetDuration = clip.revealAssetDurationSec;
      if (revealColorAsset == null ||
          revealAssetDuration == null ||
          revealInput == null) {
        videoLabels.add(baseLabel);
      } else {
        final revealDuration = (clip.revealDurationSec ?? revealAssetDuration)
            .clamp(0.1, outputDuration);
        final assetDuration = math.max(0.1, revealAssetDuration);
        final retime = revealDuration / assetDuration;
        final colorLabel = 'reveal_color$i';
        final matteLabel = 'reveal_matte$i';
        final alphaLabel = 'reveal_rgba$i';
        final videoLabel = 'video$i';
        graph.add(
          '[${revealInput.color}:v:0]'
          'trim=duration=${_n(assetDuration)},'
          'setpts=(PTS-STARTPTS)*${_n(retime)},'
          'scale=$outWidth:$outHeight:force_original_aspect_ratio=increase,'
          'crop=$outWidth:$outHeight,setsar=1,format=rgb24[$colorLabel]',
        );
        graph.add(
          '[${revealInput.matte}:v:0]'
          'trim=duration=${_n(assetDuration)},'
          'setpts=(PTS-STARTPTS)*${_n(retime)},'
          'scale=$outWidth:$outHeight:force_original_aspect_ratio=increase,'
          'crop=$outWidth:$outHeight,setsar=1,format=gray[$matteLabel]',
        );
        graph.add(
          '[$colorLabel][$matteLabel]alphamerge,format=rgba[$alphaLabel]',
        );
        graph.add(
          '[$baseLabel][$alphaLabel]'
          'overlay=0:0:format=auto:alpha=straight:eof_action=pass:'
          'repeatlast=0:shortest=0:'
          "enable='between(t,0,${_n(revealDuration)})'[$videoLabel]",
        );
        videoLabels.add(videoLabel);
      }

      final audioLabel = 'audio$i';
      if (audioInputs[i]) {
        graph.add(
          '[${clipInputs[i]}:a:0]'
          'atrim=start=${_n(start)}:end=${_n(end)},'
          'asetpts=PTS-STARTPTS,atempo=${_n(speed)},'
          'volume=${_n(clip.volume.clamp(0.0, 1.0))},'
          'aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo'
          '[$audioLabel]',
        );
      } else {
        graph.add(
          'anullsrc=r=48000:cl=stereo,'
          'atrim=duration=${_n(outputDuration)},'
          'asetpts=PTS-STARTPTS[$audioLabel]',
        );
      }
      audioLabels.add(audioLabel);
    }

    final concatInputs = StringBuffer();
    for (var i = 0; i < clips.length; i++) {
      concatInputs.write('[${videoLabels[i]}][${audioLabels[i]}]');
    }
    final totalDuration = durations.fold<double>(0, (sum, value) => sum + value);
    graph.add(
      '${concatInputs}concat=n=${clips.length}:v=1:a=1[outv][outa]',
    );

    final docs = await getApplicationDocumentsDirectory();
    final outputDir = Directory(p.join(docs.path, AppConstants.creationsFolder));
    if (!await outputDir.exists()) await outputDir.create(recursive: true);
    final output = File(
      p.join(
        outputDir.path,
        'video_editor_${DateTime.now().microsecondsSinceEpoch}.mp4',
      ),
    );
    final command = StringBuffer()
      ..write('-y ${inputs.join(' ')} ')
      ..write('-filter_complex "${graph.join(';')}" ')
      ..write('-map "[outv]" -map "[outa]" ')
      ..write('-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p ')
      ..write('-r $_fps -c:a aac -b:a 192k -movflags +faststart ')
      ..write('-t ${_n(totalDuration)} "${_escape(output.path)}"');

    final session = await FFmpegKit.execute(command.toString());
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Video export failed: $logs');
    }

    try {
      await Gal.putVideo(output.path, album: AppConstants.appName);
    } catch (_) {
      // The exported file remains available in the app's Creations folder.
    }
    return output;
  }

  static Future<bool> _hasAudio(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      return info?.getStreams().any((stream) => stream.getType() == 'audio') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _copyAsset(String assetPath) {
    return _assetCopies.putIfAbsent(assetPath, () async {
      final data = await rootBundle.load(assetPath);
      final temp = await getTemporaryDirectory();
      final file = File(p.join(temp.path, 'clipcraft_${p.basename(assetPath)}'));
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    });
  }

  static String _n(num value) => value.toStringAsFixed(5);

  static String _escape(String value) =>
      value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}
