import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/models.dart';
import 'slideshow_project.dart';

class DraftMeta {
  const DraftMeta({
    required this.id,
    required this.updatedAt,
    required this.photoCount,
    required this.durationSec,
    this.thumbPath,
    this.title,
  });

  final String id;
  final DateTime updatedAt;
  final int photoCount;
  final double durationSec;
  final String? thumbPath;
  final String? title;

  String get displayTitle =>
      title?.trim().isNotEmpty == true
          ? title!
          : DateFormat('yyyyMMddHHmmss').format(updatedAt);
}

/// Persists editor project state (photos + edits) — not an MP4 export.
class DraftService {
  DraftService._();

  /// Bumped after save/delete so Home Drafts can refresh immediately.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static void _notifyChanged() => changes.value++;

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, AppConstants.draftsFolder));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _draftDir(String id) async {
    final dir = Directory(p.join((await _root()).path, id));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<DraftMeta>> listDrafts() async {
    final root = await _root();
    final drafts = <DraftMeta>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final meta = await _readMeta(entity);
      if (meta != null) drafts.add(meta);
    }
    drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return drafts;
  }

  static Future<DraftMeta?> _readMeta(Directory dir) async {
    final file = File(p.join(dir.path, 'project.json'));
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final updatedMs = map['updatedAtMs'] as int? ??
          (await file.lastModified()).millisecondsSinceEpoch;
      final photos = (map['photos'] as List?) ?? const [];
      final thumb = File(p.join(dir.path, 'thumb.jpg'));
      return DraftMeta(
        id: p.basename(dir.path),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMs),
        photoCount: photos.length,
        durationSec: (map['estimatedDurationSec'] as num?)?.toDouble() ?? 0,
        thumbPath: await thumb.exists() ? thumb.path : null,
        title: map['title'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<DraftMeta> saveDraft(SlideshowProject project) async {
    if (project.photos.isEmpty) {
      throw StateError('Nothing to save');
    }

    final id = project.activeDraftId ??
        'draft_${DateTime.now().millisecondsSinceEpoch}';
    final dir = await _draftDir(id);
    final photosDir = Directory(p.join(dir.path, 'photos'));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);

    final savedPhotos = <Map<String, dynamic>>[];
    for (var i = 0; i < project.photos.length; i++) {
      final photo = project.photos[i];
      final ext = p.extension(photo.path).isEmpty ? '.jpg' : p.extension(photo.path);
      final dest = File(p.join(photosDir.path, 'photo_${i.toString().padLeft(3, '0')}$ext'));
      final src = File(photo.path);
      if (await src.exists()) {
        if (p.normalize(src.path) != p.normalize(dest.path)) {
          await src.copy(dest.path);
        }
      } else if (!await dest.exists()) {
        throw StateError('Missing photo file: ${photo.path}');
      }
      savedPhotos.add(_photoToJson(photo.copyWith(path: dest.path)));
    }

    String? musicPath;
    Map<String, dynamic>? musicJson;
    final music = project.music;
    if (music != null) {
      if (music.isAsset) {
        musicJson = _musicToJson(music);
      } else {
        final ext = p.extension(music.path).isEmpty ? '.mp3' : p.extension(music.path);
        final dest = File(p.join(dir.path, 'music$ext'));
        final src = File(music.path);
        if (await src.exists() &&
            p.normalize(src.path) != p.normalize(dest.path)) {
          await src.copy(dest.path);
        }
        musicPath = dest.path;
        musicJson = _musicToJson(
          MusicTrack(
            path: musicPath,
            title: music.title,
            duration: music.duration,
            isAsset: false,
            volume: music.volume,
            timelineStartSec: music.timelineStartSec,
            timelineEndSec: music.timelineEndSec,
            clipStartSec: music.clipStartSec,
            clipEndSec: music.clipEndSec,
            fadeIn: music.fadeIn,
            fadeOut: music.fadeOut,
          ),
        );
      }
    }

    // Thumb = first durable photo.
    final firstPath = savedPhotos.first['path'] as String;
    final thumb = File(p.join(dir.path, 'thumb.jpg'));
    try {
      await File(firstPath).copy(thumb.path);
    } catch (_) {}

    final now = DateTime.now();
    final map = <String, dynamic>{
      'id': id,
      'updatedAtMs': now.millisecondsSinceEpoch,
      'title': DateFormat('yyyyMMddHHmmss').format(now),
      'estimatedDurationSec': project.estimatedDurationSec,
      'photos': savedPhotos,
      'transitionId': project.selectedSlideTransition.id,
      'junctionTransitions': project.junctionTransitionIds,
      'themeId': project.selectedTheme.id,
      'selectedFrameAsset': project.selectedFrameAsset,
      'slideDurationSec': project.slideDurationSec,
      'aspectRatio': project.aspectRatio.name,
      'exportQuality': project.exportQuality.name,
      'backgroundArgb': project.backgroundArgb,
      'globalFilter': project.globalFilter.name,
      'music': musicJson,
      'isEffectOverlayEnabled': project.isEffectOverlayEnabled,
      'overlayEffectId': project.selectedOverlayEffect?.id,
      'overlayClipStartSec': project.overlayClipStartSec,
      'overlayClipEndSec': project.overlayClipEndSec,
      'overlaySourceDurationSec': project.overlaySourceDurationSec,
      'overlayTimelineStartSec': project.overlayTimelineStartSec,
      'overlayTimelineEndSec': project.overlayTimelineEndSec,
      'overlays': project.overlays.map(_overlayToJson).toList(),
      'startingCard': project.startingCard == null
          ? null
          : _titleCardToJson(project.startingCard!),
      'endingCard':
          project.endingCard == null ? null : _titleCardToJson(project.endingCard!),
    };

    await File(p.join(dir.path, 'project.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(map));

    project.activeDraftId = id;
    _notifyChanged();
    return DraftMeta(
      id: id,
      updatedAt: now,
      photoCount: savedPhotos.length,
      durationSec: project.estimatedDurationSec,
      thumbPath: await thumb.exists() ? thumb.path : firstPath,
      title: map['title'] as String?,
    );
  }

  static Future<void> loadDraft(String id, SlideshowProject project) async {
    final dir = await _draftDir(id);
    final file = File(p.join(dir.path, 'project.json'));
    if (!await file.exists()) {
      throw StateError('Draft not found');
    }
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    project.restoreFromDraftJson(map);
  }

  static Future<void> deleteDraft(String id) async {
    final dir = Directory(p.join((await _root()).path, id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _notifyChanged();
  }

  static Map<String, dynamic> _photoToJson(SlideshowPhoto photo) => {
        'id': photo.id,
        'path': photo.path,
        'filter': photo.filter.name,
        'durationSec': photo.durationSec,
        'backgroundArgb': photo.backgroundArgb,
        'backgroundBlurLevel': photo.backgroundBlurLevel,
        'cropAspectRatio': photo.cropAspectRatio,
        'cropLeft': photo.cropLeft,
        'cropTop': photo.cropTop,
        'cropWidth': photo.cropWidth,
        'cropHeight': photo.cropHeight,
        'cropDegrees': photo.cropDegrees,
        'mirrored': photo.mirrored,
        'flipped': photo.flipped,
        'rotationQuarterTurns': photo.rotationQuarterTurns,
        'animationIn': photo.animationIn.name,
        'animationOut': photo.animationOut.name,
        'animationLoop': photo.animationLoop.name,
        'animationInDurationSec': photo.animationInDurationSec,
        'animationOutDurationSec': photo.animationOutDurationSec,
        'animationLoopDurationSec': photo.animationLoopDurationSec,
      };

  static Map<String, dynamic> _musicToJson(MusicTrack m) => {
        'path': m.path,
        'title': m.title,
        'durationMs': m.duration?.inMilliseconds,
        'isAsset': m.isAsset,
        'volume': m.volume,
        'timelineStartSec': m.timelineStartSec,
        'timelineEndSec': m.timelineEndSec,
        'clipStartSec': m.clipStartSec,
        'clipEndSec': m.clipEndSec,
        'fadeIn': m.fadeIn,
        'fadeOut': m.fadeOut,
      };

  static Map<String, dynamic> _titleCardToJson(TitleCard c) => {
        'title': c.title,
        'subtitle': c.subtitle,
        'backgroundArgb': c.backgroundArgb,
        'durationSec': c.durationSec,
      };

  static Map<String, dynamic> _overlayToJson(SlideOverlay o) => {
        'id': o.id,
        'kind': o.kind.name,
        'nx': o.nx,
        'ny': o.ny,
        'scale': o.scale,
        'rotation': o.rotation,
        'text': o.text,
        'colorArgb': o.colorArgb,
        'opacity': o.opacity,
        'fontFamily': o.fontFamily,
        'fontWeight': o.fontWeight,
        'fontSize': o.fontSize,
        'align': o.align.name,
        'textCase': o.textCase.name,
        'letterSpacing': o.letterSpacing,
        'lineHeight': o.lineHeight,
        'curve': o.curve,
        'strokeColorArgb': o.strokeColorArgb,
        'strokeWidth': o.strokeWidth,
        'strokeDoubleColorArgb': o.strokeDoubleColorArgb,
        'bgColorArgb': o.bgColorArgb,
        'bgOpacity': o.bgOpacity,
        'bgCorner': o.bgCorner,
        'shadowColorArgb': o.shadowColorArgb,
        'shadowDistance': o.shadowDistance,
        'shadowAngle': o.shadowAngle,
        'shadowOpacity': o.shadowOpacity,
        'shadowBlur': o.shadowBlur,
        'gradientEndArgb': o.gradientEndArgb,
        'templateId': o.templateId,
        'stickerEmoji': o.stickerEmoji,
      };
}
