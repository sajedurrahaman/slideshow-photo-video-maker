import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/models.dart';
import 'effect_overlay_service.dart';
import 'frame_compositor.dart';
import 'photo_animation_engine.dart';
import 'transition_engine.dart';

class _PreparedPhotoLayers {
  const _PreparedPhotoLayers({
    required this.composed,
    required this.background,
    required this.subject,
    required this.subjectDx,
    required this.subjectDy,
  });

  final img.Image composed;
  final img.Image background;
  final img.Image subject;
  final int subjectDx;
  final int subjectDy;
}

Map<String, Object> _preparePhotoInWorker(Map<String, Object> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Unsupported image file');

  final filter = PhotoFilterPreset.values[args['filter'] as int];
  var filtered = FrameCompositor.applyFilter(decoded, filter);
  final cropLeft = (args['cropLeft'] as num?)?.toDouble() ?? 0;
  final cropTop = (args['cropTop'] as num?)?.toDouble() ?? 0;
  final cropWidthN = (args['cropWidth'] as num?)?.toDouble() ?? 1;
  final cropHeightN = (args['cropHeight'] as num?)?.toDouble() ?? 1;
  final hasRect =
      cropLeft < -0.001 ||
      cropTop < -0.001 ||
      cropLeft + cropWidthN > 1.001 ||
      cropTop + cropHeightN > 1.001 ||
      cropWidthN < 0.999 ||
      cropHeightN < 0.999;
  final cropDegrees = (args['cropDegrees'] as num?)?.toDouble() ?? 0;
  if (cropDegrees.abs() > 0.05 || hasRect) {
    final srcW = filtered.width.toDouble();
    final srcH = filtered.height.toDouble();
    final outW = (cropWidthN * srcW).round().clamp(1, 8000);
    final outH = (cropHeightN * srcH).round().clamp(1, 8000);
    final rad = cropDegrees.abs() * math.pi / 180;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final cover = math.max(
      (srcW * cosA + srcH * sinA) / srcW,
      (srcW * sinA + srcH * cosA) / srcH,
    );
    final zoom = math.max(cropWidthN, cropHeightN);
    final scale = cover * (zoom > 1.001 ? zoom : 1);
    var picture = filtered;
    if (scale > 1.01) {
      picture = img.copyResize(
        picture,
        width: (srcW * scale).round(),
        height: (srcH * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    if (cropDegrees.abs() > 0.05) {
      if (picture.numChannels < 4) {
        picture = picture.convert(numChannels: 4);
      }
      picture = img.copyRotate(
        picture,
        angle: cropDegrees,
        interpolation: img.Interpolation.linear,
      );
    }
    final centerX = zoom > 1.001 ? outW / 2 : -cropLeft * srcW + srcW / 2;
    final centerY = zoom > 1.001 ? outH / 2 : -cropTop * srcH + srcH / 2;
    final canvas = img.Image(width: outW, height: outH, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 255));
    img.compositeImage(
      canvas,
      picture,
      dstX: (centerX - picture.width / 2).round(),
      dstY: (centerY - picture.height / 2).round(),
      dstW: picture.width,
      dstH: picture.height,
    );
    filtered = canvas;
  } else {
    final cropAspectRatio = args['cropAspectRatio'] as double;
    if (cropAspectRatio > 0) {
      final sourceAspectRatio = filtered.width / filtered.height;
      var cropWidth = filtered.width;
      var cropHeight = filtered.height;
      if (sourceAspectRatio > cropAspectRatio) {
        cropWidth = (filtered.height * cropAspectRatio).round();
      } else {
        cropHeight = (filtered.width / cropAspectRatio).round();
      }
      filtered = img.copyCrop(
        filtered,
        x: (filtered.width - cropWidth) ~/ 2,
        y: (filtered.height - cropHeight) ~/ 2,
        width: cropWidth,
        height: cropHeight,
      );
    }
  }
  if (args['mirrored'] as bool) img.flipHorizontal(filtered);
  if (args['flipped'] as bool) img.flipVertical(filtered);
  final rotationQuarterTurns = args['rotationQuarterTurns'] as int;
  if (rotationQuarterTurns != 0) {
    filtered = img.copyRotate(
      filtered,
      angle: rotationQuarterTurns * 90,
      interpolation: img.Interpolation.linear,
    );
  }

  final blurLevel = args['backgroundBlurLevel'] as int?;
  final w = args['width'] as int;
  final h = args['height'] as int;
  // Match live _blurFill (BoxFit.cover) — stretch-to-fit left black bars
  // when the plate aspect differs from the canvas.
  final blurPlate = blurLevel != null
      ? TransitionEngine.coverCrop(filtered, w, h)
      : null;
  final layers = FrameCompositor.placeOnCanvasLayers(
    src: filtered,
    w: w,
    h: h,
    bgArgb: args['photoBackground'] as int,
    blurPlate: blurPlate,
    blurLevel: blurLevel ?? 0,
  );
  return {
    'composed': Uint8List.fromList(img.encodeJpg(layers.composed, quality: 90)),
    'background': Uint8List.fromList(
      img.encodeJpg(layers.background, quality: 90),
    ),
    'subject': Uint8List.fromList(img.encodePng(layers.subject)),
    'subjectDx': layers.dx,
    'subjectDy': layers.dy,
  };
}

Map<String, Object> _transitionImageWorkerData(img.Image source) {
  var image = source;
  if (image.hasPalette ||
      image.format != img.Format.uint8 ||
      image.numChannels < 3) {
    image = image.convert(format: img.Format.uint8, numChannels: 4);
  }
  return {
    'bytes': image.toUint8List(),
    'width': image.width,
    'height': image.height,
    'channels': image.numChannels,
    'rowStride': image.rowStride,
  };
}

Map<String, Object> _renderTransitionBatchInWorker(Map<String, Object> args) {
  img.Image decodeWorkerImage(Map<String, Object> data) {
    final bytes = data['bytes'] as Uint8List;
    return img.Image.fromBytes(
      width: data['width'] as int,
      height: data['height'] as int,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      numChannels: data['channels'] as int,
      rowStride: data['rowStride'] as int,
    );
  }

  final sourceData = (args['fromFrames'] as List).cast<Map<String, Object>>();
  final sources = sourceData.map(decodeWorkerImage).toList(growable: false);
  final target = decodeWorkerImage(args['toImage'] as Map<String, Object>);
  final type = SlideTransitionType.values[args['type'] as int];
  final frameCount = args['frameCount'] as int;

  // Single from plate (no motion): one size pass + shared pixel buffers.
  if (sources.length == 1) {
    return {
      'frames': TransitionEngine.renderJpegBatch(
        from: sources.first,
        to: target,
        type: type,
        frameCount: frameCount,
        gridCols: args['gridCols'] as int,
        gridRows: args['gridRows'] as int,
        reverseDiagonal: args['reverseDiagonal'] as bool,
        topToBottom: args['topToBottom'] as bool,
        pivotNx: args['pivotNx'] as double,
        pivotNy: args['pivotNy'] as double,
        quality: 70,
      ),
    };
  }

  final rendered = <Uint8List>[];
  for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
    final frame = TransitionEngine.apply(
      from: sources[frameIndex],
      to: target,
      type: type,
      progress: (frameIndex + 1) / frameCount,
      gridCols: args['gridCols'] as int,
      gridRows: args['gridRows'] as int,
      reverseDiagonal: args['reverseDiagonal'] as bool,
      topToBottom: args['topToBottom'] as bool,
      pivotNx: args['pivotNx'] as double,
      pivotNy: args['pivotNy'] as double,
    );
    rendered.add(TransitionEngine.encodeJpeg(frame, quality: 70));
  }
  return {'frames': rendered};
}

class SlideshowProject extends ChangeNotifier {
  final List<SlideshowPhoto> photos = [];
  SlideTheme selectedTheme = AppThemes.all.first;
  bool isEffectOverlayEnabled = false;

  /// Active particle/FX overlay clip (null when overlay is off).
  OverlayEffect? selectedOverlayEffect;

  /// Source trim of the overlay clip (seconds within the effect video).
  double overlayClipStartSec = 0;
  double? overlayClipEndSec;
  double? overlaySourceDurationSec;

  /// Where the effect sits on the video timeline (like music timelineStart/End).
  double overlayTimelineStartSec = 0;
  double? overlayTimelineEndSec;
  int? selectedPhotoIndex;
  SlideTransitionOption selectedSlideTransition =
      SlideTransitionOption.all.first;
  String? selectedFrameAsset;
  double slideDurationSec = AppConstants.defaultDurationSec;
  MusicTrack? music;

  /// Device imports shown under the Local music tab.
  final List<MusicTrack> localMusicTracks = [];
  AspectPreset aspectRatio = AspectPreset.square;
  ExportQuality exportQuality = ExportQuality.p720;
  int backgroundArgb = 0xFF000000;
  PhotoFilterPreset globalFilter = PhotoFilterPreset.original;
  TitleCard? startingCard;
  TitleCard? endingCard;
  final List<SlideOverlay> overlays = [];

  bool isPlaying = false;
  bool isPreviewPlaying = false;

  /// True while building in-memory preview frames after transition select.
  bool isPreparingPreview = false;

  /// True when cache is ready — Play starts smooth playback immediately.
  bool isPreviewReady = false;
  bool isProcessing = false;
  double processProgress = 0;
  double previewPositionSec = 0;
  Uint8List? previewFrameBytes;
  int previewFrameIndex = 0;
  List<File> generatedFrames = [];

  /// Lightweight listeners — avoid rebuilding the whole editor every frame.
  final ValueNotifier<Uint8List?> previewFrameListenable =
      ValueNotifier<Uint8List?>(null);
  final ValueNotifier<double> previewPositionListenable = ValueNotifier<double>(
    0,
  );

  /// Photo under the playhead while the user scrubs a paused timeline
  /// before preview frames exist.
  final ValueNotifier<({int index, double fraction})?> scrubLive =
      ValueNotifier<({int index, double fraction})?>(null);

  /// In-memory JPEG frames for smooth editor preview (no % overlay).
  final List<Uint8List> _previewMemoryFrames = [];
  final List<img.Image?> _decodedPreview = [];
  final List<_PreparedPhotoLayers?> _decodedPreviewLayers = [];
  final List<String> _decodedPreviewKeys = [];
  final List<int> _previewSegmentCounts = [];
  String? _previewCacheKey;
  String? _previewBaseCacheKey;
  bool _isWarmingPreviewCache = false;
  int _previewGeneration = 0;
  Timer? _previewTimer;
  Timer? _transitionPreviewDebounce;

  /// Cached A→B transition JPEG strips (solo frames stay in the base preview).
  final LinkedHashMap<String, List<Uint8List>> _transitionStripCache =
      LinkedHashMap();
  static const int _transitionStripCacheMax = 12;
  int _transitionWarmEpoch = 0;

  /// Editor Play button — mixes selected music with the frame preview.
  AudioPlayer? _previewMusic;
  String? _previewMusicPath;

  void _setPreviewFrame(Uint8List? bytes, {bool syncLegacy = true}) {
    previewFrameListenable.value = bytes;
    if (syncLegacy) previewFrameBytes = bytes;
  }

  void _setPreviewPosition(double sec) {
    previewPositionSec = sec;
    previewPositionListenable.value = sec;
  }

  int get photoCount => photos.length;

  (int, int) get outputSize => aspectRatio.sizeForQuality(exportQuality);

  /// Smaller size so preview can play near real-time like native.
  (int, int) get previewSize => aspectRatio.sizeForQuality(ExportQuality.p480);

  double get previewFps =>
      (AppConstants.framesPerTransition + AppConstants.holdFrames) /
      slideDurationSec;

  int frameCountForDuration(double seconds) =>
      (seconds * previewFps).round().clamp(1, 10000);

  double _animSeconds(double seconds, double photoDuration) {
    final cap = photoDuration < 0.1 ? 0.1 : photoDuration;
    return seconds.clamp(0.1, cap);
  }

  int _animFrames(double seconds, double photoDuration) =>
      frameCountForDuration(_animSeconds(seconds, photoDuration));

  (int, int) _splitAnimFrames(SlideshowPhoto photo, int totalFrames) {
    final hasIn = photo.animationIn != PhotoAnimationType.none;
    final hasOut = photo.animationOut != PhotoAnimationType.none;
    var inFrames = hasIn
        ? _animFrames(photo.animationInDurationSec, photo.durationSec)
        : 0;
    var outFrames = hasOut
        ? _animFrames(photo.animationOutDurationSec, photo.durationSec)
        : 0;
    if (inFrames > totalFrames) inFrames = totalFrames;
    if (outFrames > totalFrames - inFrames) {
      outFrames = totalFrames - inFrames;
    }
    return (inFrames, outFrames);
  }

  /// In motion occupies the opening frames. Out motion occupies the closing frames.
  img.Image _animatePhotoFrame({
    required img.Image source,
    required SlideshowPhoto photo,
    required int frameIndex,
    required int totalFrames,
    required int inFrames,
    required int outFrames,
    required int background,
    _PreparedPhotoLayers? layers,
  }) {
    final outStart = totalFrames - outFrames;
    final useLayers = layers != null;
    img.Image applyMotion({
      required PhotoAnimationType type,
      required double progress,
      required bool reverse,
      required img.Image current,
    }) {
      if (useLayers) {
        return PhotoAnimationEngine.applyLayered(
          background: layers.background,
          subject: layers.subject,
          subjectDx: layers.subjectDx,
          subjectDy: layers.subjectDy,
          type: type,
          progress: progress,
          backgroundArgb: background,
          reverse: reverse,
        );
      }
      return PhotoAnimationEngine.apply(
        image: reverse ? source : current,
        type: type,
        progress: progress,
        backgroundArgb: background,
        reverse: reverse,
      );
    }

    var frame = source;
    if (photo.animationIn != PhotoAnimationType.none &&
        inFrames > 0 &&
        frameIndex < outStart) {
      final progress = frameIndex < inFrames
          ? (frameIndex + 1) / inFrames
          : 1.0;
      frame = applyMotion(
        type: photo.animationIn,
        progress: progress,
        reverse: false,
        current: source,
      );
    }
    if (photo.animationOut != PhotoAnimationType.none &&
        outFrames > 0 &&
        frameIndex >= outStart) {
      final outIndex = frameIndex - outStart;
      frame = applyMotion(
        type: photo.animationOut,
        progress: (outIndex + 1) / outFrames,
        reverse: true,
        current: source,
      );
    }
    if (photo.animationLoop != PhotoAnimationType.none) {
      final loopFrames = math.max(
        1,
        _animFrames(photo.animationLoopDurationSec, photo.durationSec),
      );
      if (useLayers) {
        frame = PhotoAnimationEngine.applyLayered(
          background: layers.background,
          subject: layers.subject,
          subjectDx: layers.subjectDx,
          subjectDy: layers.subjectDy,
          type: photo.animationLoop,
          progress: (frameIndex % loopFrames) / loopFrames,
          backgroundArgb: background,
        );
      } else {
        frame = PhotoAnimationEngine.apply(
          image: frame,
          type: photo.animationLoop,
          progress: (frameIndex % loopFrames) / loopFrames,
          backgroundArgb: background,
        );
      }
    }
    return frame;
  }

  int photoFrameStartIndex(int photoIndex) {
    var index = startingCard == null
        ? 0
        : frameCountForDuration(startingCard!.durationSec);
    for (var i = 0; i < photoIndex && i < photos.length; i++) {
      index += frameCountForDuration(photos[i].durationSec);
    }
    return index;
  }

  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  _EditorSnapshot _snapshot() => _EditorSnapshot(
    photos: List<SlideshowPhoto>.from(photos),
    transitionId: selectedSlideTransition.id,
    selectedPhotoIndex: selectedPhotoIndex,
  );

  void _recordHistory() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > 30) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snapshot());
    _restore(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snapshot());
    _restore(_redoStack.removeLast());
  }

  void _restore(_EditorSnapshot snap) {
    photos
      ..clear()
      ..addAll(snap.photos);
    selectedSlideTransition = SlideTransitionOption.all.firstWhere(
      (o) => o.id == snap.transitionId,
      orElse: () => SlideTransitionOption.all.first,
    );
    selectedPhotoIndex = snap.selectedPhotoIndex == null || photos.isEmpty
        ? null
        : snap.selectedPhotoIndex!.clamp(0, photos.length - 1).toInt();
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames());
    } else if (photos.isNotEmpty) {
      unawaited(_refreshPhotoPreview(selectedPhotoIndex ?? 0));
    } else {
      _setPreviewFrame(null);
    }
  }

  void setPhotos(List<SlideshowPhoto> list) {
    photos
      ..clear()
      ..addAll(list);
    generatedFrames = [];
    _setPreviewFrame(null);
    _clearDecodedPreview();
    _invalidatePreviewCache();
    selectedPhotoIndex = null;
    notifyListeners();
  }

  /// Insert newly picked photos before [index] on the image timeline.
  /// [index] is clamped to `0..photos.length` (length = append at end).
  void insertPhotosAt(int index, List<SlideshowPhoto> list) {
    if (list.isEmpty) return;
    final room = AppConstants.maxPhotos - photos.length;
    if (room <= 0) return;
    final toAdd = list.take(room).toList();
    if (toAdd.isEmpty) return;
    final at = index.clamp(0, photos.length).toInt();
    _recordHistory();
    photos.insertAll(at, toAdd);
    if (selectedPhotoIndex != null && selectedPhotoIndex! >= at) {
      selectedPhotoIndex = selectedPhotoIndex! + toAdd.length;
    }
    generatedFrames = [];
    stopPreviewPlayback();
    _clearDecodedPreview();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames());
    } else if (photos.isNotEmpty) {
      unawaited(_refreshPhotoPreview(at.clamp(0, photos.length - 1)));
    }
  }

  void selectTimelinePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    selectedPhotoIndex = index;
    stopPreviewPlayback();
    if (_previewMemoryFrames.isNotEmpty && isPreviewReady) {
      final frameIndex = photoFrameStartIndex(index)
          .clamp(0, _previewMemoryFrames.length - 1)
          .toInt();
      previewFrameIndex = frameIndex;
      _setPreviewPosition(frameIndex / previewFps);
      _setPreviewFrame(_previewMemoryFrames[frameIndex]);
    } else {
      unawaited(_refreshPhotoPreview(index));
    }
    notifyListeners();
  }

  void clearTimelinePhotoSelection() {
    selectedPhotoIndex = null;
    stopPreviewPlayback();
    if (_previewMemoryFrames.isNotEmpty) {
      previewFrameIndex = 0;
      _setPreviewPosition(0);
      _setPreviewFrame(_previewMemoryFrames.first);
    } else if (photos.isNotEmpty) {
      unawaited(_refreshPhotoPreview(0));
    }
    notifyListeners();
  }

  void applyBackgroundToAll(int sourceIndex) {
    if (sourceIndex < 0 || sourceIndex >= photos.length) return;
    final source = photos[sourceIndex];
    _recordHistory();
    for (var i = 0; i < photos.length; i++) {
      photos[i] = photos[i].copyWith(
        backgroundArgb: source.backgroundArgb,
        clearBackgroundArgb: source.backgroundArgb == null,
        backgroundBlurLevel: source.backgroundBlurLevel,
        clearBackgroundBlur: source.backgroundBlurLevel == null,
      );
    }
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames(showLoading: false));
    }
  }

  void updatePhoto(int index, SlideshowPhoto photo) {
    if (index < 0 || index >= photos.length) return;
    final previous = photos[index];
    _recordHistory();
    photos[index] = photo;
    generatedFrames = [];
    stopPreviewPlayback();
    if (_samePreviewPixels(previous, photo)) {
      // Animation and duration stay on the GPU. Export bakes frames later.
      _invalidatePreviewCache();
      notifyListeners();
      return;
    }
    // Pixel change (blur/BG/crop/filter): drop stale frames so Play cannot
    // keep using the old black letterbox while the rebake is in flight.
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames(showLoading: false));
    } else {
      unawaited(_refreshPhotoPreview(index));
    }
  }

  void changePhotoDuration(int index, double seconds) {
    if (index < 0 || index >= photos.length) return;
    final duration = seconds.clamp(1.0, 10.0).toDouble();
    if ((photos[index].durationSec - duration).abs() < 0.001) return;
    final current = photos[index];
    updatePhoto(
      index,
      current.copyWith(
        durationSec: duration,
        animationInDurationSec: _animSeconds(
          current.animationInDurationSec,
          duration,
        ),
        animationOutDurationSec: _animSeconds(
          current.animationOutDurationSec,
          duration,
        ),
        animationLoopDurationSec: _animSeconds(
          current.animationLoopDurationSec,
          duration,
        ),
      ),
    );
  }

  void reorderPhoto(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= photos.length) return;
    if (newIndex < 0 || newIndex >= photos.length) return;
    _recordHistory();
    final item = photos.removeAt(oldIndex);
    photos.insert(newIndex, item);
    // Keep selection on the moved clip.
    if (selectedPhotoIndex == oldIndex) {
      selectedPhotoIndex = newIndex;
    } else if (selectedPhotoIndex != null) {
      final s = selectedPhotoIndex!;
      if (oldIndex < s && newIndex >= s) {
        selectedPhotoIndex = s - 1;
      } else if (oldIndex > s && newIndex <= s) {
        selectedPhotoIndex = s + 1;
      }
    }
    stopPreviewPlayback();
    _clearDecodedPreview();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames(showLoading: false));
    }
  }

  void removePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    _recordHistory();
    photos.removeAt(index);
    final previouslySelected = selectedPhotoIndex;
    if (photos.isEmpty) {
      selectedPhotoIndex = null;
    } else if (previouslySelected == index) {
      selectedPhotoIndex = index >= photos.length ? photos.length - 1 : index;
    } else if (previouslySelected != null && previouslySelected > index) {
      selectedPhotoIndex = previouslySelected - 1;
    }
    generatedFrames = [];
    stopPreviewPlayback();
    _clearDecodedPreview();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames());
    } else if (photos.isNotEmpty) {
      unawaited(_refreshPhotoPreview(selectedPhotoIndex ?? 0));
    } else {
      _setPreviewFrame(null);
    }
  }

  Future<void> _refreshPhotoPreview(int index) async {
    if (index < 0 || index >= photos.length) return;
    try {
      final (w, h) = previewSize;
      final image = await _preparePhoto(photos[index], w, h);
      final baked = await _finalize(
        image,
        includeDecorativeFrame: false,
        includeTextOverlays: false,
      );
      _setPreviewFrame(
        Uint8List.fromList(TransitionEngine.encodeJpeg(baked, quality: 85)),
      );
      notifyListeners();
    } catch (_) {
      // Keep the current frame if a replacement image cannot be decoded.
    }
  }

  void selectTheme(SlideTheme theme) {
    final shouldPrepare = selectedTheme.id != theme.id;
    selectedTheme = theme;
    if (music == null || music!.isAsset) {
      if (theme.musicAsset != null) {
        music = MusicTrack(
          path: theme.musicAsset!,
          title: p.basenameWithoutExtension(theme.musicAsset!),
          isAsset: true,
        );
      }
    }
    if (shouldPrepare) {
      generatedFrames = [];
      stopPreviewPlayback();
      _invalidatePreviewCache();
    }
    notifyListeners();
    if (shouldPrepare) unawaited(preparePreviewFrames());
  }

  /// Instant select — live VideoPlayer overlay; no frame rebuild.
  void previewPickOverlayEffect(OverlayEffect effect) {
    if (selectedOverlayEffect?.id == effect.id) {
      isEffectOverlayEnabled = true;
      notifyListeners();
      return;
    }
    selectedOverlayEffect = effect;
    isEffectOverlayEnabled = true;
    overlayClipStartSec = 0;
    overlayClipEndSec = null;
    overlaySourceDurationSec = null;
    overlayTimelineStartSec = 0;
    overlayTimelineEndSec = null;
    notifyListeners();
  }

  /// Live overlay needs no bake — kept for Play path compatibility.
  Future<void> ensureOverlayReadyForPreview() async {
    if (selectedOverlayEffect == null) return;
    if (!isEffectOverlayEnabled) {
      isEffectOverlayEnabled = true;
      notifyListeners();
    }
  }

  /// Confirm effect — live layer only (no Preparing preview).
  void commitOverlayEffect({bool resetClip = false}) {
    final effect = selectedOverlayEffect;
    if (effect == null) return;
    isEffectOverlayEnabled = true;
    if (resetClip) {
      overlayClipStartSec = 0;
      overlayClipEndSec = null;
      overlaySourceDurationSec = null;
      overlayTimelineStartSec = 0;
      overlayTimelineEndSec = null;
    }
    notifyListeners();
  }

  void selectOverlayEffect(OverlayEffect effect, {bool resetClip = true}) {
    previewPickOverlayEffect(effect);
    if (resetClip) {
      overlayClipStartSec = 0;
      overlayClipEndSec = null;
      overlaySourceDurationSec = null;
      overlayTimelineStartSec = 0;
      overlayTimelineEndSec = null;
    }
    commitOverlayEffect(resetClip: false);
  }

  void clearOverlayEffect() {
    if (!isEffectOverlayEnabled && selectedOverlayEffect == null) return;
    selectedOverlayEffect = null;
    isEffectOverlayEnabled = false;
    overlayClipStartSec = 0;
    overlayClipEndSec = null;
    overlaySourceDurationSec = null;
    overlayTimelineStartSec = 0;
    overlayTimelineEndSec = null;
    notifyListeners();
  }

  void setOverlayTimelineRange(
    double startSec,
    double endSec, {
    bool notify = true,
  }) {
    if (!isEffectOverlayEnabled || selectedOverlayEffect == null) return;
    final maxDur = estimatedDurationSec;
    if (maxDur <= 0.5) return;
    const minLen = 0.5;
    final start = startSec.clamp(0.0, maxDur - minLen);
    final end = endSec.clamp(start + minLen, maxDur);
    if ((overlayTimelineStartSec - start).abs() < 0.001 &&
        ((overlayTimelineEndSec ?? maxDur) - end).abs() < 0.001) {
      return;
    }
    overlayTimelineStartSec = start;
    overlayTimelineEndSec = end;
    if (notify) notifyListeners();
  }

  /// Timeline drag end — instant, no frame rebuild (live compositor).
  void commitOverlayTimelineRange(double startSec, double endSec) {
    if (!isEffectOverlayEnabled || selectedOverlayEffect == null) return;
    final maxDur = estimatedDurationSec;
    if (maxDur <= 0.5) return;
    const minLen = 0.5;
    overlayTimelineStartSec = startSec.clamp(0.0, maxDur - minLen);
    overlayTimelineEndSec = endSec.clamp(
      overlayTimelineStartSec + minLen,
      maxDur,
    );
    notifyListeners();
  }

  void setOverlaySourceDuration(double sec) {
    if (sec <= 0) return;
    overlaySourceDurationSec = sec;
    final end = overlayClipEndSec;
    if (end != null && end > sec) {
      overlayClipEndSec = sec;
    }
    notifyListeners();
  }

  /// Clip start at playhead — source trim (live; no bake).
  void setOverlayClipStartAtPlayhead() {
    if (!isEffectOverlayEnabled || selectedOverlayEffect == null) return;
    final dur = overlaySourceDurationSec ?? 5.0;
    final t = previewPositionSec % dur;
    final end = overlayClipEndSec ?? dur;
    overlayClipStartSec = t.clamp(0.0, math.max(0.0, end - 0.15));
    notifyListeners();
  }

  /// Clip end at playhead — source trim (live; no bake).
  void setOverlayClipEndAtPlayhead() {
    if (!isEffectOverlayEnabled || selectedOverlayEffect == null) return;
    final dur = overlaySourceDurationSec ?? 5.0;
    final t = previewPositionSec % dur;
    overlayClipEndSec = t.clamp(overlayClipStartSec + 0.15, dur).toDouble();
    notifyListeners();
  }

  bool get isLiveEffectVisible => isEffectVisibleAt(previewPositionSec);

  bool isEffectVisibleAt(double timelineSec) {
    if (!isEffectOverlayEnabled || selectedOverlayEffect == null) return false;
    final start = overlayTimelineStartSec;
    final end = overlayTimelineEndSec ?? estimatedDurationSec;
    return timelineSec >= start && timelineSec <= end;
  }

  /// Local time inside the effect clip for seeking the live VideoPlayer.
  double liveEffectLocalSec() => effectLocalSecAt(previewPositionSec);

  double effectLocalSecAt(double timelineSec) {
    final start = overlayTimelineStartSec;
    final local = (timelineSec - start).clamp(0.0, 36000.0);
    final clip0 = overlayClipStartSec;
    final clip1 = overlayClipEndSec ?? overlaySourceDurationSec;
    if (clip1 != null && clip1 > clip0 + 0.05) {
      final span = clip1 - clip0;
      return clip0 + (local % span);
    }
    return local;
  }

  void selectSlideTransition(SlideTransitionOption option) {
    if (selectedSlideTransition.id == option.id) {
      // Re-tap same item: ensure preview is prepared.
      if (!_isWarmingPreviewCache && !isPreviewReady && !isPreparingPreview) {
        unawaited(preparePreviewFrames());
      }
      return;
    }
    _recordHistory();
    selectedSlideTransition = option;
    if (!_isWarmingPreviewCache) stopPreviewPlayback();
    // A slide effect only changes the transition frames. Keep prepared photos
    // and the current frame list so only those frames need to be rebuilt.
    _previewCacheKey = null;
    isPreviewReady = false;
    if (!_isWarmingPreviewCache) {
      final baseReady =
          _previewBaseCacheKey == _buildPreviewBaseCacheKey() &&
          _previewMemoryFrames.isNotEmpty &&
          _previewSegmentCounts.length == photos.length;
      final firstStripReady =
          option.type == SlideTransitionType.none ||
          _transitionStripCache.containsKey(_transitionStripKey(0, option));
      // Prefetched / cached first A→B → no Lottie; otherwise short debounce.
      if (baseReady && firstStripReady) {
        unawaited(preparePreviewFrames(showLoading: false));
      } else {
        isPreparingPreview = true;
        _transitionPreviewDebounce?.cancel();
        _transitionPreviewDebounce = Timer(const Duration(milliseconds: 80), () {
          _transitionPreviewDebounce = null;
          unawaited(preparePreviewFrames());
        });
      }
    }
    notifyListeners();
  }

  /// Quietly prepare a no-effect preview after the editor opens, so the first
  /// transition selection only needs to replace its transition frames.
  Future<void> warmPreviewCache() async {
    if (_isWarmingPreviewCache ||
        isPreparingPreview ||
        isProcessing ||
        photos.length < AppConstants.minPhotos ||
        photos.any(
          (photo) =>
              photo.animationIn != PhotoAnimationType.none ||
              photo.animationOut != PhotoAnimationType.none ||
              photo.animationLoop != PhotoAnimationType.none,
        )) {
      return;
    }
    _isWarmingPreviewCache = true;
    final transitionAtStart = selectedSlideTransition.id;
    try {
      if (!isPreviewReady || _previewMemoryFrames.isEmpty) {
        await preparePreviewFrames(showLoading: false);
      }
      // Prefetch first-5 A→B strips so picker taps skip the long load.
      await _warmPriorityTransitionStrips();
    } finally {
      _isWarmingPreviewCache = false;
      final baseIsCurrent = _previewBaseCacheKey == _buildPreviewBaseCacheKey();
      final effectIsCurrent =
          _previewCacheKey == _buildPreviewCacheKey(selectedSlideTransition);
      if (!baseIsCurrent && transitionAtStart == selectedSlideTransition.id) {
        unawaited(warmPreviewCache());
      } else if (!baseIsCurrent || !effectIsCurrent) {
        unawaited(preparePreviewFrames());
      }
    }
  }

  static List<SlideTransitionOption> get _prioritySlideOptions =>
      SlideTransitionOption.all.take(5).toList(growable: false);

  String _transitionStripKey(int pairIndex, SlideTransitionOption option) {
    return '${_buildPreviewBaseCacheKey()}|$pairIndex|${option.id}';
  }

  void _storeTransitionStrip(String key, List<Uint8List> frames) {
    _transitionStripCache.remove(key);
    _transitionStripCache[key] = frames;
    while (_transitionStripCache.length > _transitionStripCacheMax) {
      _transitionStripCache.remove(_transitionStripCache.keys.first);
    }
  }

  Future<void> _warmPriorityTransitionStrips() async {
    if (photos.length < 2 || _previewBaseCacheKey == null) return;
    final epoch = _transitionWarmEpoch;
    final (w, h) = previewSize;
    final fromLayers = await _cachedPreviewLayers(0, w, h);
    final toLayers = await _cachedPreviewLayers(1, w, h);
    if (epoch != _transitionWarmEpoch) return;

    for (final opt in _prioritySlideOptions) {
      if (epoch != _transitionWarmEpoch) return;
      if (opt.type == SlideTransitionType.none) continue;
      final key = _transitionStripKey(0, opt);
      if (_transitionStripCache.containsKey(key)) continue;
      final n = AppConstants.framesPerTransition;
      final rendered = await _renderTransitionFramesOffThread(
        fromFrames: [fromLayers.composed],
        toImage: toLayers.composed,
        option: opt,
        frameCount: n,
      );
      if (epoch != _transitionWarmEpoch) return;
      _storeTransitionStrip(key, rendered);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  void _invalidatePreviewCache() {
    _previewMemoryFrames.clear();
    _previewSegmentCounts.clear();
    _previewCacheKey = null;
    _previewBaseCacheKey = null;
    isPreviewReady = false;
    _transitionStripCache.clear();
    _transitionWarmEpoch++;
    // Drop decoded layers too — otherwise a blur/BG change can briefly
    // (or fully) replay stale black-letterbox frames while rebake runs.
    _clearDecodedPreview();
  }

  String _previewPixelKey(SlideshowPhoto photo) {
    final (w, h) = previewSize;
    return '${photo.path}|${photo.filter.index}|${photo.backgroundArgb}|'
        '${photo.backgroundBlurLevel}|'
        '${photo.cropAspectRatio}|${photo.cropLeft}|${photo.cropTop}|'
        '${photo.cropWidth}|${photo.cropHeight}|${photo.cropDegrees}|'
        '${photo.mirrored}|${photo.flipped}|'
        '${photo.rotationQuarterTurns}|$backgroundArgb|${w}x$h|'
        '${selectedFrameAsset ?? ''}|${overlays.length}';
  }

  bool _samePreviewPixels(SlideshowPhoto a, SlideshowPhoto b) =>
      _previewPixelKey(a) == _previewPixelKey(b);

  void _clearDecodedPreview() {
    _decodedPreview.clear();
    _decodedPreviewLayers.clear();
    _decodedPreviewKeys.clear();
  }

  Future<_PreparedPhotoLayers> _cachedPreviewLayers(
    int index,
    int w,
    int h,
  ) async {
    final key = _previewPixelKey(photos[index]);
    while (_decodedPreview.length <= index) {
      _decodedPreview.add(null);
      _decodedPreviewLayers.add(null);
      _decodedPreviewKeys.add('');
    }
    final cached = _decodedPreviewLayers[index];
    if (cached != null && _decodedPreviewKeys[index] == key) return cached;
    final layers = await _preparePhotoLayers(photos[index], w, h);
    _decodedPreview[index] = layers.composed;
    _decodedPreviewLayers[index] = layers;
    _decodedPreviewKeys[index] = key;
    return layers;
  }

  /// Build frames in background after transition select (shows loading UI).
  /// Duration and animation edits pass [showLoading] false so the current
  /// frame stays on screen while only the changed work runs.
  Future<void> preparePreviewFrames({bool showLoading = true}) async {
    _transitionPreviewDebounce?.cancel();
    _transitionPreviewDebounce = null;
    if (photos.length < AppConstants.minPhotos || isProcessing) {
      isPreviewReady = false;
      isPreparingPreview = false;
      notifyListeners();
      return;
    }

    final baseKey = _buildPreviewBaseCacheKey();
    final transitionOption = selectedSlideTransition;
    final key = _buildPreviewCacheKey(transitionOption);
    if (_previewCacheKey == key && _previewMemoryFrames.isNotEmpty) {
      isPreviewReady = true;
      isPreparingPreview = false;
      notifyListeners();
      return;
    }

    final generation = ++_previewGeneration;
    if (showLoading) {
      isPreparingPreview = true;
      isPreviewReady = false;
      notifyListeners();
    }

    try {
      final canRebuildTransitionsOnly =
          _previewBaseCacheKey == baseKey &&
          _previewMemoryFrames.isNotEmpty &&
          _previewSegmentCounts.length == photos.length;
      final built = canRebuildTransitionsOnly
          ? await _rebuildTransitionFrames(
              generation: generation,
              // Drop Lottie as soon as the first A→B strip is spliced.
              onFirstPairReady: showLoading
                  ? (frames, counts) {
                      if (generation != _previewGeneration) return;
                      _previewMemoryFrames
                        ..clear()
                        ..addAll(frames);
                      _previewSegmentCounts
                        ..clear()
                        ..addAll(counts);
                      _previewCacheKey = key;
                      _previewBaseCacheKey = baseKey;
                      isPreviewReady = true;
                      isPreparingPreview = false;
                      final selectedStart = selectedPhotoIndex == null
                          ? 0
                          : photoFrameStartIndex(selectedPhotoIndex!);
                      previewFrameIndex = selectedStart
                          .clamp(0, _previewMemoryFrames.length - 1)
                          .toInt();
                      _setPreviewPosition(previewFrameIndex / previewFps);
                      _setPreviewFrame(
                        _previewMemoryFrames[previewFrameIndex],
                      );
                      notifyListeners();
                    }
                  : null,
            )
          : await _buildPreviewMemoryFrames(
              generation: generation,
              cacheKey: key,
              transitionOption: transitionOption,
            );
      if (generation != _previewGeneration || built == null) return;
      _previewMemoryFrames
        ..clear()
        ..addAll(built.frames);
      _previewSegmentCounts
        ..clear()
        ..addAll(built.counts);
      _previewCacheKey = key;
      _previewBaseCacheKey = baseKey;
      isPreviewReady =
          _previewMemoryFrames.isNotEmpty &&
          key == _buildPreviewCacheKey(selectedSlideTransition);
      if (isPreviewReady) {
        final selectedStart = selectedPhotoIndex == null
            ? 0
            : photoFrameStartIndex(selectedPhotoIndex!);
        previewFrameIndex = selectedStart
            .clamp(0, _previewMemoryFrames.length - 1)
            .toInt();
        _setPreviewPosition(previewFrameIndex / previewFps);
        _setPreviewFrame(_previewMemoryFrames[previewFrameIndex]);
      }
    } finally {
      if (generation == _previewGeneration) {
        isPreparingPreview = false;
        notifyListeners();
      }
    }
  }

  String _buildPreviewCacheKey(SlideTransitionOption transitionOption) {
    return '${_buildPreviewBaseCacheKey()}::${transitionOption.id}';
  }

  String _buildPreviewBaseCacheKey() {
    return [
      photos
          .map(
            (e) =>
                '${e.path}:${e.filter.name}:${e.durationSec}:'
                '${e.backgroundArgb}:${e.backgroundBlurLevel}:${e.cropAspectRatio}:'
                '${e.cropLeft}:${e.cropTop}:${e.cropWidth}:${e.cropHeight}:'
                '${e.cropDegrees}:${e.mirrored}:'
                '${e.flipped}:${e.rotationQuarterTurns}:'
                '${e.animationIn.name}:${e.animationOut.name}:'
                '${e.animationLoop.name}:'
                '${e.animationInDurationSec.toStringAsFixed(2)}:'
                '${e.animationOutDurationSec.toStringAsFixed(2)}:'
                '${e.animationLoopDurationSec.toStringAsFixed(2)}',
          )
          .join('|'),
      selectedTheme.id,
      // Effect overlay is live-composited — not part of baked preview cache.
      slideDurationSec,
      aspectRatio.name,
      backgroundArgb,
      startingCard?.title,
      startingCard?.durationSec,
      endingCard?.title,
      endingCard?.durationSec,
      overlays.length,
    ].join('::');
  }

  Future<({List<Uint8List> frames, List<int> counts})?>
  _rebuildTransitionFrames({
    required int generation,
    void Function(List<Uint8List> frames, List<int> counts)? onFirstPairReady,
  }) async {
    final (w, h) = previewSize;
    final layers = <_PreparedPhotoLayers>[];
    for (var i = 0; i < photos.length; i++) {
      if (generation != _previewGeneration) return null;
      layers.add(await _cachedPreviewLayers(i, w, h));
    }
    if (layers.length < 2) return null;

    final frames = List<Uint8List>.of(_previewMemoryFrames);
    final decoded = layers.map((e) => e.composed).toList(growable: false);
    final option = selectedSlideTransition;
    final hasMotion = photos.any(
      (photo) =>
          photo.animationIn != PhotoAnimationType.none ||
          photo.animationOut != PhotoAnimationType.none ||
          photo.animationLoop != PhotoAnimationType.none,
    );
    var segmentStart = startingCard == null
        ? 0
        : frameCountForDuration(startingCard!.durationSec)
              .clamp(4, 300)
              .toInt();

    for (var i = 0; i < photos.length - 1; i++) {
      if (generation != _previewGeneration) return null;
      final photo = photos[i];
      final totalFrames = frameCountForDuration(photo.durationSec);
      final segmentCount = _previewSegmentCounts[i];
      final transitionFrames = math.min(
        math.min(AppConstants.framesPerTransition, totalFrames),
        segmentCount,
      );
      if (transitionFrames <= 0) {
        segmentStart += segmentCount;
        continue;
      }
      final tailStart = segmentStart + segmentCount - transitionFrames;

      // Restore hold frames when switching back to None (tail was blended).
      if (option.type == SlideTransitionType.none) {
        final solo = frames[segmentStart];
        for (var t = 0; t < transitionFrames; t++) {
          frames[tailStart + t] = solo;
        }
        segmentStart += segmentCount;
        if (i == 0 && onFirstPairReady != null) {
          onFirstPairReady(
            List<Uint8List>.of(frames),
            List<int>.of(_previewSegmentCounts),
          );
        }
        continue;
      }

      final stripKey = _transitionStripKey(i, option);
      var rendered = _transitionStripCache[stripKey];

      if (rendered == null || rendered.length != transitionFrames) {
        final background = photo.backgroundArgb ?? backgroundArgb;
        final (inFrames, outFrames) = _splitAnimFrames(photo, totalFrames);
        final List<img.Image> fromFrames;
        if (!hasMotion) {
          // Hold plate is static — one source image for the whole strip.
          fromFrames = [decoded[i]];
        } else {
          fromFrames = <img.Image>[];
          for (var t = 0; t < transitionFrames; t++) {
            if (generation != _previewGeneration) return null;
            fromFrames.add(
              _animatePhotoFrame(
                source: decoded[i],
                photo: photo,
                frameIndex: totalFrames - transitionFrames + t,
                totalFrames: totalFrames,
                inFrames: inFrames,
                outFrames: outFrames,
                background: background,
                layers: layers[i],
              ),
            );
            await Future<void>.delayed(Duration.zero);
          }
        }
        rendered = await _renderTransitionFramesOffThread(
          fromFrames: fromFrames,
          toImage: decoded[i + 1],
          option: option,
          frameCount: transitionFrames,
        );
        if (generation != _previewGeneration) return null;
        _storeTransitionStrip(stripKey, rendered);
      }

      for (var t = 0; t < rendered.length && t < transitionFrames; t++) {
        frames[tailStart + t] = rendered[t];
      }
      segmentStart += segmentCount;

      // Unlock UI after first pair — remaining pairs continue quietly.
      if (i == 0 && onFirstPairReady != null) {
        onFirstPairReady(
          List<Uint8List>.of(frames),
          List<int>.of(_previewSegmentCounts),
        );
      }
    }

    if (generation != _previewGeneration) return null;
    return (frames: frames, counts: List<int>.of(_previewSegmentCounts));
  }

  void stopPreviewPlayback() {
    _transitionPreviewDebounce?.cancel();
    _transitionPreviewDebounce = null;
    _previewGeneration++;
    _previewTimer?.cancel();
    _previewTimer = null;
    unawaited(_stopPreviewMusic());
    final wasPreparing = isPreparingPreview;
    isPreparingPreview = false;
    if (isPreviewPlaying || wasPreparing) {
      isPreviewPlaying = false;
      isPlaying = false;
      notifyListeners();
    }
  }

  static const _previewMusicFadeSec = 1.5;

  Future<void> _stopPreviewMusic() async {
    try {
      await _previewMusic?.pause();
    } catch (_) {}
  }

  /// Volume at [videoSec] respecting Fade In / Fade Out switches.
  double _previewMusicVolumeAt(double videoSec, MusicTrack m) {
    final target = (m.volume / 100.0).clamp(0.0, 1.0);
    final tStart = m.timelineStartSec;
    final tEnd = m.timelineEndSec ?? estimatedDurationSec;
    final window = (tEnd - tStart).clamp(0.1, 36000.0);
    if (videoSec < tStart || videoSec >= tEnd) return 0;

    var vol = target;
    final into = videoSec - tStart;
    final remain = tEnd - videoSec;
    final fadeDur = math.min(_previewMusicFadeSec, window / 2);

    if (m.fadeIn && into < fadeDur) {
      vol = target * (into / fadeDur).clamp(0.0, 1.0);
    }
    if (m.fadeOut && remain < fadeDur) {
      vol = math.min(vol, target * (remain / fadeDur).clamp(0.0, 1.0));
    }
    return vol;
  }

  Future<void> _applyPreviewMusicVolume(double videoSec) async {
    final m = music;
    final player = _previewMusic;
    if (m == null || player == null) return;
    try {
      await player.setVolume(_previewMusicVolumeAt(videoSec, m));
    } catch (_) {}
  }

  Future<void> _startPreviewMusicAt(
    double videoSec, {
    bool forceSeek = true,
  }) async {
    final m = music;
    if (m == null) {
      await _stopPreviewMusic();
      return;
    }
    try {
      _previewMusic ??= AudioPlayer();
      final clipStart = m.clipStartSec;

      if (_previewMusicPath != m.path) {
        if (m.isAsset) {
          await _previewMusic!.setAsset(m.path);
        } else {
          await _previewMusic!.setFilePath(m.path);
        }
        _previewMusicPath = m.path;
      }

      final tStart = m.timelineStartSec;
      final tEnd = m.timelineEndSec ?? estimatedDurationSec;
      if (videoSec < tStart || videoSec >= tEnd) {
        await _previewMusic!.pause();
        return;
      }

      final sourceDur = m.duration?.inMilliseconds != null
          ? m.duration!.inMilliseconds / 1000.0
          : (_previewMusic!.duration?.inMilliseconds ?? 60000) / 1000.0;
      final clipEnd = (m.clipEndSec ?? sourceDur).clamp(
        clipStart + 0.1,
        sourceDur,
      );
      final clipLen = math.max(0.1, clipEnd - clipStart);
      final into = videoSec - tStart;
      final audioSec = clipStart + (into % clipLen);

      await _previewMusic!.setVolume(_previewMusicVolumeAt(videoSec, m));

      if (forceSeek || !_previewMusic!.playing) {
        await _previewMusic!.seek(
          Duration(milliseconds: (audioSec * 1000).round()),
        );
      }
      if (!_previewMusic!.playing) {
        await _previewMusic!.play();
      }
    } catch (_) {
      // Video preview still works if audio fails to load.
    }
  }

  /// Selected-photo motion plays on the GPU. No JPEG frames.
  void startLiveClip() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewGeneration++;
    isPreviewPlaying = true;
    isPlaying = true;
    notifyListeners();
  }

  void finishLiveClip() {
    if (!isPreviewPlaying && !isPlaying) return;
    isPreviewPlaying = false;
    isPlaying = false;
    notifyListeners();
  }

  int? _pendingClockPhoto;
  double? _pendingClockFraction;
  bool _clockCallbackScheduled = false;

  void setLivePreviewClock(int photoIndex, double clipFraction) {
    if (photoIndex < 0 || photoIndex >= photos.length) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _pendingClockPhoto = photoIndex;
      _pendingClockFraction = clipFraction;
      if (_clockCallbackScheduled) return;
      _clockCallbackScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _clockCallbackScheduled = false;
        final index = _pendingClockPhoto;
        final fraction = _pendingClockFraction;
        _pendingClockPhoto = null;
        _pendingClockFraction = null;
        if (index == null || fraction == null || index >= photos.length) {
          return;
        }
        _applyLivePreviewClock(index, fraction);
      });
      return;
    }
    _applyLivePreviewClock(photoIndex, clipFraction);
  }

  void _applyLivePreviewClock(int photoIndex, double clipFraction) {
    final start = photoFrameStartIndex(photoIndex);
    final clipFrames = frameCountForDuration(photos[photoIndex].durationSec);
    final frame = start + clipFraction.clamp(0.0, 1.0) * clipFrames;
    _setPreviewPosition(frame / previewFps);
  }

  /// Play only when frames are ready — otherwise wait for prepare.
  Future<void> togglePreviewPlayback() async {
    if (isPreviewPlaying) {
      stopPreviewPlayback();
      return;
    }
    if (isPreparingPreview) return;
    // Effect is live-composited; only ensure base frames exist.
    if (selectedOverlayEffect != null) {
      await ensureOverlayReadyForPreview();
    }
    if (!isPreviewReady || _previewMemoryFrames.isEmpty) {
      await preparePreviewFrames();
      if (!isPreviewReady) return;
    }
    playSmoothPreview();
  }

  void playSmoothPreview() {
    if (photos.length < AppConstants.minPhotos || isProcessing) return;
    if (_previewMemoryFrames.isEmpty || !isPreviewReady) return;

    _previewTimer?.cancel();
    final generation = _previewGeneration;

    isPreviewPlaying = true;
    isPlaying = true;
    final selected = selectedPhotoIndex;
    final selectedStart = selected == null ? 0 : photoFrameStartIndex(selected);
    final selectedEnd = selected == null
        ? _previewMemoryFrames.length
        : (selectedStart + frameCountForDuration(photos[selected].durationSec))
              .clamp(0, _previewMemoryFrames.length)
              .toInt();
    previewFrameIndex = selectedStart
        .clamp(0, _previewMemoryFrames.length - 1)
        .toInt();
    _setPreviewPosition(previewFrameIndex / previewFps);
    _setPreviewFrame(_previewMemoryFrames[previewFrameIndex]);
    notifyListeners(); // play/pause icon only
    unawaited(_startPreviewMusicAt(previewPositionSec));

    // Slightly gentler than encode FPS so JPEG decode can keep up (less blink).
    final frameMs = (1000 / previewFps).round().clamp(28, 90);
    var musicSyncCounter = 0;
    _previewTimer = Timer.periodic(Duration(milliseconds: frameMs), (timer) {
      if (generation != _previewGeneration || !isPreviewPlaying) {
        timer.cancel();
        return;
      }
      final next = previewFrameIndex + 1;
      if (next >= selectedEnd) {
        timer.cancel();
        _previewTimer = null;
        isPreviewPlaying = false;
        isPlaying = false;
        previewFrameIndex = selectedStart
            .clamp(0, _previewMemoryFrames.length - 1)
            .toInt();
        _setPreviewPosition(previewFrameIndex / previewFps);
        if (_previewMemoryFrames.isNotEmpty) {
          _setPreviewFrame(_previewMemoryFrames[previewFrameIndex]);
        }
        unawaited(_stopPreviewMusic());
        notifyListeners(); // stop icon
        return;
      }
      previewFrameIndex = next;
      // Only update listenables — do NOT notifyListeners (avoids full rebuild blink).
      _setPreviewPosition(next / previewFps);
      _setPreviewFrame(_previewMemoryFrames[next]);
      // Fade volume every couple of frames; full sync less often.
      musicSyncCounter++;
      if (musicSyncCounter % 2 == 0) {
        unawaited(_applyPreviewMusicVolume(previewPositionSec));
      }
      if (musicSyncCounter % 15 == 0) {
        unawaited(_startPreviewMusicAt(previewPositionSec, forceSeek: false));
      }
    });
  }

  Future<({List<Uint8List> frames, List<int> counts})?>
  _buildPreviewMemoryFrames({
    required int generation,
    required String cacheKey,
    required SlideTransitionOption transitionOption,
  }) async {
    final frames = <Uint8List>[];
    final counts = <int>[];
    final (w, h) = previewSize;
    final layers = <_PreparedPhotoLayers>[];
    for (var i = 0; i < photos.length; i++) {
      if (generation != _previewGeneration) return null;
      layers.add(await _cachedPreviewLayers(i, w, h));
    }
    if (layers.length < 2) return null;
    final decoded = layers.map((e) => e.composed).toList(growable: false);

    final overlays = await _loadPreviewOverlays(w, h);
    final cursor = <int>[0];

    if (startingCard != null) {
      final cardImg = await FrameCompositor.makeTitleCard(
        card: startingCard!,
        w: w,
        h: h,
      );
      final n = frameCountForDuration(startingCard!.durationSec).clamp(4, 300);
      final cardFrames = await _encodeStill(
        cardImg,
        n,
        generation,
        overlays: overlays,
        frameCursor: cursor,
      );
      if (cardFrames == null) return null;
      frames.addAll(cardFrames);
    }

    for (var i = 0; i < decoded.length; i++) {
      if (generation != _previewGeneration) return null;
      final segment = await _renderPhotoSegment(
        index: i,
        decoded: decoded,
        layers: layers,
        generation: generation,
        transitionOption: transitionOption,
        overlays: overlays,
        frameCursor: cursor,
      );
      if (segment == null) return null;
      counts.add(segment.length);
      frames.addAll(segment);
    }

    if (generation != _previewGeneration) return null;
    if (endingCard != null) {
      final cardImg = await FrameCompositor.makeTitleCard(
        card: endingCard!,
        w: w,
        h: h,
      );
      final n = frameCountForDuration(endingCard!.durationSec).clamp(4, 300);
      final cardFrames = await _encodeStill(
        cardImg,
        n,
        generation,
        overlays: overlays,
        frameCursor: cursor,
      );
      if (cardFrames == null) return null;
      frames.addAll(cardFrames);
    }

    if (generation != _previewGeneration) return null;
    _previewCacheKey = cacheKey;
    return (frames: frames, counts: counts);
  }

  /// Editor preview never bakes FX — live VideoPlayer layer handles it.
  Future<List<img.Image>> _loadPreviewOverlays(int w, int h) async {
    return const [];
  }

  Future<Uint8List> _jpegFrame(
    img.Image image,
    List<img.Image> overlays,
    List<int> frameCursor,
  ) async {
    final baked = await _finalize(
      image,
      includeDecorativeFrame: false,
      includeTextOverlays: false,
    );
    frameCursor[0] = frameCursor[0] + 1;
    return Uint8List.fromList(TransitionEngine.encodeJpeg(baked, quality: 70));
  }

  Future<List<Uint8List>> _renderTransitionFramesOffThread({
    required List<img.Image> fromFrames,
    required img.Image toImage,
    required SlideTransitionOption option,
    int? frameCount,
  }) async {
    if (fromFrames.isEmpty) return const [];
    final count = frameCount ?? fromFrames.length;
    if (count <= 0) return const [];
    final first = fromFrames.first;
    final sources = fromFrames.every((frame) => identical(frame, first))
        ? <img.Image>[first]
        : fromFrames;
    final result = await compute(_renderTransitionBatchInWorker, {
      'fromFrames': sources
          .map(_transitionImageWorkerData)
          .toList(growable: false),
      'toImage': _transitionImageWorkerData(toImage),
      'type': option.type.index,
      'frameCount': count,
      'gridCols': option.gridCols,
      'gridRows': option.gridRows,
      'reverseDiagonal': option.reverseDiagonal,
      'topToBottom': option.topToBottom,
      'pivotNx': option.pivotNx,
      'pivotNy': option.pivotNy,
    });
    return (result['frames'] as List).cast<Uint8List>();
  }

  Future<List<Uint8List>?> _encodeStill(
    img.Image image,
    int count,
    int generation, {
    List<img.Image> overlays = const [],
    List<int>? frameCursor,
  }) async {
    if (generation != _previewGeneration) return null;
    final cursor = frameCursor ?? <int>[0];
    if (overlays.isEmpty) {
      final bytes = await _jpegFrame(image, overlays, cursor);
      cursor[0] = cursor[0] + count - 1;
      return List<Uint8List>.filled(count, bytes);
    }
    final frames = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      if (generation != _previewGeneration) return null;
      frames.add(await _jpegFrame(image, overlays, cursor));
    }
    return frames;
  }

  Future<List<Uint8List>?> _renderPhotoSegment({
    required int index,
    required List<img.Image> decoded,
    required List<_PreparedPhotoLayers> layers,
    required int generation,
    required SlideTransitionOption transitionOption,
    List<img.Image> overlays = const [],
    List<int>? frameCursor,
  }) async {
    if (generation != _previewGeneration) return null;
    final photo = photos[index];
    final effect = transitionOption.type;
    final pairs = decoded.length - 1;
    final totalFrames = frameCountForDuration(photo.durationSec);
    final transitionFrames = index < pairs && effect != SlideTransitionType.none
        ? math.min(AppConstants.framesPerTransition, totalFrames)
        : 0;
    final background = photo.backgroundArgb ?? backgroundArgb;
    final (inFrames, outFrames) = _splitAnimFrames(photo, totalFrames);
    final soloFrames = totalFrames - transitionFrames;
    final photoLayers = index < layers.length ? layers[index] : null;
    final frames = <Uint8List>[];
    final cursor = frameCursor ?? <int>[0];
    Uint8List? lastBytes;
    img.Image? lastSource;

    Future<bool> pushFrame(img.Image image) async {
      if (generation != _previewGeneration) return false;
      if (overlays.isEmpty &&
          identical(image, lastSource) &&
          lastBytes != null) {
        frames.add(lastBytes!);
        cursor[0] = cursor[0] + 1;
        return true;
      }
      final bytes = await _jpegFrame(image, overlays, cursor);
      if (generation != _previewGeneration) return false;
      lastSource = image;
      lastBytes = bytes;
      frames.add(bytes);
      return true;
    }

    for (var hold = 0; hold < soloFrames; hold++) {
      if (generation != _previewGeneration) return null;
      final kept = await pushFrame(
        _animatePhotoFrame(
          source: decoded[index],
          photo: photo,
          frameIndex: hold,
          totalFrames: totalFrames,
          inFrames: inFrames,
          outFrames: outFrames,
          background: background,
          layers: photoLayers,
        ),
      );
      if (!kept) return null;
      // Let taps and frames run. A tight image loop ANRs Android and the
      // process is killed ("Lost connection to device").
      await Future<void>.delayed(Duration.zero);
    }

    if (transitionFrames > 0) {
      final option = transitionOption;
      final fromFrames = <img.Image>[];
      for (var t = 0; t < transitionFrames; t++) {
        if (generation != _previewGeneration) return null;
        fromFrames.add(
          _animatePhotoFrame(
            source: decoded[index],
            photo: photo,
            frameIndex: soloFrames + t,
            totalFrames: totalFrames,
            inFrames: inFrames,
            outFrames: outFrames,
            background: background,
            layers: photoLayers,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      if (overlays.isEmpty) {
        final rendered = await _renderTransitionFramesOffThread(
          fromFrames: fromFrames,
          toImage: decoded[index + 1],
          option: option,
        );
        if (generation != _previewGeneration) return null;
        frames.addAll(rendered);
        cursor[0] = cursor[0] + rendered.length;
        lastSource = null;
        lastBytes = null;
      } else {
        for (var t = 0; t < fromFrames.length; t++) {
          if (generation != _previewGeneration) return null;
          final blended = TransitionEngine.apply(
            from: fromFrames[t],
            to: decoded[index + 1],
            type: effect,
            progress: (t + 1) / transitionFrames,
            gridCols: option.gridCols,
            gridRows: option.gridRows,
            reverseDiagonal: option.reverseDiagonal,
            topToBottom: option.topToBottom,
            pivotNx: option.pivotNx,
            pivotNy: option.pivotNy,
          );
          final kept = await pushFrame(blended);
          if (!kept) return null;
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    return frames;
  }

  void selectFrame(String? assetPath) {
    if (selectedFrameAsset == assetPath) return;
    selectedFrameAsset = assetPath;
    // Editor shows the frame as a live overlay. Drop any JPEG preview that
    // already baked an older frame so the two cannot stack.
    if (_previewMemoryFrames.isNotEmpty ||
        previewFrameListenable.value != null) {
      stopPreviewPlayback();
      _previewMemoryFrames.clear();
      _previewSegmentCounts.clear();
      _previewCacheKey = null;
      isPreviewReady = false;
      unawaited(refreshLivePreview());
    } else {
      notifyListeners();
    }
  }

  void setDuration(double seconds) {
    slideDurationSec = seconds;
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(preparePreviewFrames());
  }

  void setMusic(MusicTrack? track) {
    music = track?.copyWith(
      timelineStartSec: 0,
      clearTimelineEnd: true,
      clipStartSec: 0,
      clearClipEnd: true,
    );
    _previewMusicPath = null;
    if (!isPreviewPlaying) unawaited(_stopPreviewMusic());
    notifyListeners();
    if (music != null) unawaited(_probeMusicDuration(music!));
  }

  void addLocalMusicTrack(MusicTrack track) {
    if (!localMusicTracks.any((t) => t.path == track.path)) {
      localMusicTracks.add(track);
    }
    music = track.copyWith(
      timelineStartSec: 0,
      clearTimelineEnd: true,
      clipStartSec: 0,
      clearClipEnd: true,
    );
    _previewMusicPath = null;
    if (!isPreviewPlaying) unawaited(_stopPreviewMusic());
    notifyListeners();
    unawaited(_probeMusicDuration(music!));
  }

  /// Resolves real file length so Edit cut handles scale to any song duration.
  Future<void> _probeMusicDuration(MusicTrack track) async {
    final player = AudioPlayer();
    try {
      final d = track.isAsset
          ? await player.setAsset(track.path)
          : await player.setFilePath(track.path);
      final resolved = d ?? player.duration;
      if (resolved == null || resolved.inMilliseconds <= 0) return;
      if (music?.path != track.path) return;
      music = music!.copyWith(duration: resolved);
      notifyListeners();
    } catch (_) {
      // Keep unknown duration; Edit sheet will retry.
    } finally {
      await player.dispose();
    }
  }

  void setMusicVolume(int volume) {
    if (music == null) return;
    music = music!.copyWith(volume: volume.clamp(0, 100));
    notifyListeners();
  }

  /// Places music on the video timeline: plays from [startSec] to [endSec].
  /// Set [notify] false while dragging handles for smooth UI (commit with notify at end).
  void setMusicTimelineRange(
    double startSec,
    double endSec, {
    bool notify = true,
  }) {
    if (music == null) return;
    final maxDur = estimatedDurationSec;
    if (maxDur <= 0.5) return;
    final minLen = 0.5;
    var start = startSec.clamp(0.0, maxDur - minLen);
    var end = endSec.clamp(start + minLen, maxDur);
    if ((music!.timelineStartSec - start).abs() < 0.001 &&
        ((music!.timelineEndSec ?? maxDur) - end).abs() < 0.001) {
      return;
    }
    music = music!.copyWith(timelineStartSec: start, timelineEndSec: end);
    if (notify) notifyListeners();
  }

  /// Slides the music clip left/right on the video timeline (keeps duration).
  void shiftMusicTimeline(double deltaSec, {bool notify = true}) {
    if (music == null || deltaSec == 0) return;
    final maxDur = estimatedDurationSec;
    final start = music!.timelineStartSec;
    final end = music!.timelineEndSec ?? maxDur;
    final len = (end - start).clamp(0.5, maxDur);
    final newStart = (start + deltaSec).clamp(0.0, maxDur - len);
    setMusicTimelineRange(newStart, newStart + len, notify: notify);
  }

  /// Trims which portion of the source audio file is used.
  void setMusicClip({
    double? clipStartSec,
    double? clipEndSec,
    bool? fadeIn,
    bool? fadeOut,
    Duration? duration,
    bool clearClipEnd = false,
  }) {
    if (music == null) return;
    music = music!.copyWith(
      clipStartSec: clipStartSec,
      clipEndSec: clipEndSec,
      clearClipEnd: clearClipEnd,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      duration: duration,
    );
    notifyListeners();
  }

  void setAspect(AspectPreset preset) {
    if (aspectRatio == preset) return;
    aspectRatio = preset;
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
  }

  void setExportQuality(ExportQuality q) {
    exportQuality = q;
    generatedFrames = [];
    notifyListeners();
  }

  void setBackground(int argb) {
    backgroundArgb = argb;
    notifyListeners();
  }

  /// One undo step. Used by the editor Ratio/BG sheet when no photo is selected.
  void setAllPhotoBackgrounds({
    int? color,
    int? blurLevel,
    bool clearBlur = false,
  }) {
    if (photos.isEmpty) {
      if (color != null) {
        backgroundArgb = color;
        notifyListeners();
      }
      return;
    }
    _recordHistory();
    if (color != null) backgroundArgb = color;
    for (var i = 0; i < photos.length; i++) {
      photos[i] = photos[i].copyWith(
        backgroundArgb: color,
        backgroundBlurLevel: blurLevel,
        clearBackgroundBlur: clearBlur,
      );
    }
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      // Must rebake — showLoading false keeps UI calm, but cache was cleared
      // so Play waits for the blur/color frames instead of stale letterbox.
      unawaited(preparePreviewFrames(showLoading: false));
    }
  }

  void setGlobalFilter(PhotoFilterPreset filter) {
    globalFilter = filter;
    for (var i = 0; i < photos.length; i++) {
      photos[i] = photos[i].copyWith(filter: filter);
    }
    notifyListeners();
  }

  void setStartingCard(TitleCard? card) {
    startingCard = card;
    notifyListeners();
  }

  void setEndingCard(TitleCard? card) {
    endingCard = card;
    notifyListeners();
  }

  void addOverlay(SlideOverlay overlay) {
    overlays.add(overlay);
    // Drop any frames that may have baked text; live layer owns text now.
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(refreshLivePreview());
  }

  void updateOverlay(SlideOverlay overlay) {
    final i = overlays.indexWhere((e) => e.id == overlay.id);
    if (i < 0) return;
    overlays[i] = overlay;
    notifyListeners();
  }

  void removeOverlay(String id) {
    overlays.removeWhere((e) => e.id == id);
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(refreshLivePreview());
  }

  void clearOverlays() {
    overlays.clear();
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(refreshLivePreview());
  }

  Future<img.Image> _preparePhoto(SlideshowPhoto photo, int w, int h) async {
    return (await _preparePhotoLayers(photo, w, h)).composed;
  }

  Future<_PreparedPhotoLayers> _preparePhotoLayers(
    SlideshowPhoto photo,
    int w,
    int h,
  ) async {
    final bytes = await File(photo.path).readAsBytes();
    // Full-resolution JPEG decode, filtering and resize can take long enough
    // to trigger an Android ANR when run on the UI isolate (especially after
    // selecting several recent photos). Do that work in a worker isolate.
    final workerArgs = <String, Object>{
      'bytes': bytes,
      'filter': photo.filter.index,
      'width': w,
      'height': h,
      'photoBackground': photo.backgroundArgb ?? backgroundArgb,
      'cropAspectRatio': photo.cropAspectRatio ?? 0.0,
      'cropLeft': photo.cropLeft,
      'cropTop': photo.cropTop,
      'cropWidth': photo.cropWidth,
      'cropHeight': photo.cropHeight,
      'cropDegrees': photo.cropDegrees,
      'mirrored': photo.mirrored,
      'flipped': photo.flipped,
      'rotationQuarterTurns': photo.rotationQuarterTurns,
    };
    final blurLevel = photo.backgroundBlurLevel;
    if (blurLevel != null) {
      workerArgs['backgroundBlurLevel'] = blurLevel;
    }
    final prepared = await compute(_preparePhotoInWorker, workerArgs);
    final composed = TransitionEngine.decode(prepared['composed'] as Uint8List);
    final background = TransitionEngine.decode(
      prepared['background'] as Uint8List,
    );
    final subject = img.decodeImage(prepared['subject'] as Uint8List);
    if (composed == null || background == null || subject == null) {
      throw Exception('Could not decode ${photo.path}');
    }
    return _PreparedPhotoLayers(
      composed: composed,
      background: background,
      subject: subject,
      subjectDx: prepared['subjectDx'] as int,
      subjectDy: prepared['subjectDy'] as int,
    );
  }

  /// [includeDecorativeFrame] is true for export. Editor preview keeps the
  /// decorative frame as a live Image overlay so switching frames never stacks.
  ///
  /// [includeTextOverlays] must stay false for editor preview — text is drawn
  /// by [LiveTextOverlaysLayer]. Baking both causes a ghost duplicate when moving.
  Future<img.Image> _finalize(
    img.Image frame, {
    bool includeDecorativeFrame = true,
    bool includeTextOverlays = true,
  }) {
    return FrameCompositor.bakeOverlays(
      base: frame,
      frameAsset: includeDecorativeFrame ? selectedFrameAsset : null,
      overlays: includeTextOverlays ? List.of(overlays) : const [],
    );
  }

  Future<void> generatePreviewFrames({
    void Function(double)? onProgress,
  }) async {
    if (photos.length < AppConstants.minPhotos) return;
    isProcessing = true;
    processProgress = 0;
    notifyListeners();

    try {
      final dir = await getTemporaryDirectory();
      final outDir = Directory(p.join(dir.path, 'slideshow_frames'));
      if (await outDir.exists()) {
        await outDir.delete(recursive: true);
      }
      await outDir.create(recursive: true);

      final (w, h) = outputSize;
      final photoLayers = <_PreparedPhotoLayers>[];
      for (final photo in photos) {
        photoLayers.add(await _preparePhotoLayers(photo, w, h));
      }
      if (photoLayers.length < 2) {
        throw Exception('Could not decode enough photos');
      }
      final decoded = photoLayers
          .map((e) => e.composed)
          .toList(growable: false);

      // Bake FX with the same JPEG proxies + screenBlend as live preview so
      // export does not pick up FFmpeg full-res screen haze.
      final exportEffect = isEffectOverlayEnabled
          ? selectedOverlayEffect
          : null;
      List<File> effectFrameFiles = const [];
      if (exportEffect != null) {
        final (ew, eh) = EffectOverlayService.cappedSize(w, h, maxSide: 360);
        effectFrameFiles = await EffectOverlayService.previewFrames(
          effect: exportEffect,
          width: ew,
          height: eh,
        );
        if (overlaySourceDurationSec == null && effectFrameFiles.isNotEmpty) {
          overlaySourceDurationSec =
              effectFrameFiles.length / EffectOverlayService.previewFps;
        }
      }

      final frames = <File>[];
      var frameIndex = 0;
      final pairs = decoded.length - 1;

      Future<img.Image> applyExportEffect(img.Image image) async {
        if (exportEffect == null || effectFrameFiles.isEmpty) return image;
        final t = frameIndex / previewFps;
        if (!isEffectVisibleAt(t)) return image;
        final local = effectLocalSecAt(t);
        final idx =
            (local * EffectOverlayService.previewFps).floor() %
            effectFrameFiles.length;
        final fx = TransitionEngine.decode(
          await effectFrameFiles[idx].readAsBytes(),
        );
        if (fx == null) return image;
        return EffectOverlayService.compose(
          image,
          fx,
          blend: exportEffect.blend,
        );
      }

      Future<void> writeFrame(img.Image image) async {
        // Live stack: photo → decorative frame → FX → text.
        var out = await _finalize(image, includeTextOverlays: false);
        out = await applyExportEffect(out);
        if (overlays.isNotEmpty) {
          out = await FrameCompositor.bakeOverlays(
            base: out,
            frameAsset: null,
            overlays: List.of(overlays),
          );
        }
        final file = File(
          p.join(
            outDir.path,
            'img${frameIndex.toString().padLeft(5, '0')}.jpg',
          ),
        );
        await file.writeAsBytes(TransitionEngine.encodeJpeg(out, quality: 82));
        frames.add(file);
        frameIndex++;
      }

      // Starting title card
      var introFrames = 0;
      if (startingCard != null) {
        final cardImg = await FrameCompositor.makeTitleCard(
          card: startingCard!,
          w: w,
          h: h,
        );
        introFrames = frameCountForDuration(startingCard!.durationSec);
        for (var i = 0; i < introFrames; i++) {
          await writeFrame(cardImg);
        }
      }

      final endingFrames = endingCard == null
          ? 0
          : frameCountForDuration(endingCard!.durationSec);
      final totalFramesEstimate =
          introFrames +
          photos.fold<int>(
            0,
            (total, photo) => total + frameCountForDuration(photo.durationSec),
          ) +
          endingFrames;
      final effect = selectedSlideTransition.type;
      final option = selectedSlideTransition;

      for (var i = 0; i < decoded.length; i++) {
        final photo = photos[i];
        final totalFrames = frameCountForDuration(photo.durationSec);
        final transitionFrames = i < pairs && effect != SlideTransitionType.none
            ? math.min(AppConstants.framesPerTransition, totalFrames)
            : 0;
        final background = photo.backgroundArgb ?? backgroundArgb;
        final (inFrames, outFrames) = _splitAnimFrames(photo, totalFrames);
        final soloFrames = totalFrames - transitionFrames;

        for (var hold = 0; hold < soloFrames; hold++) {
          await writeFrame(
            _animatePhotoFrame(
              source: decoded[i],
              photo: photo,
              frameIndex: hold,
              totalFrames: totalFrames,
              inFrames: inFrames,
              outFrames: outFrames,
              background: background,
              layers: photoLayers[i],
            ),
          );
          processProgress = (frameIndex / totalFramesEstimate).clamp(0.0, 1.0);
          onProgress?.call(processProgress);
        }

        if (transitionFrames > 0) {
          for (var t = 0; t < transitionFrames; t++) {
            final progress = (t + 1) / transitionFrames;
            final fromFrame = _animatePhotoFrame(
              source: decoded[i],
              photo: photo,
              frameIndex: soloFrames + t,
              totalFrames: totalFrames,
              inFrames: inFrames,
              outFrames: outFrames,
              background: background,
              layers: photoLayers[i],
            );
            final toFrame = decoded[i + 1];
            final blended = TransitionEngine.apply(
              from: fromFrame,
              to: toFrame,
              type: effect,
              progress: progress,
              gridCols: option.gridCols,
              gridRows: option.gridRows,
              reverseDiagonal: option.reverseDiagonal,
              topToBottom: option.topToBottom,
              pivotNx: option.pivotNx,
              pivotNy: option.pivotNy,
            );
            await writeFrame(blended);
            processProgress = (frameIndex / totalFramesEstimate).clamp(
              0.0,
              1.0,
            );
            onProgress?.call(processProgress);
            if (t % 3 == 0) {
              previewFrameBytes = await frames.last.readAsBytes();
              previewFrameIndex = frameIndex - 1;
              notifyListeners();
            }
          }
        }
      }

      if (endingCard != null) {
        final cardImg = await FrameCompositor.makeTitleCard(
          card: endingCard!,
          w: w,
          h: h,
        );
        final n = endingFrames;
        for (var i = 0; i < n; i++) {
          await writeFrame(cardImg);
        }
      }

      generatedFrames = frames;
      if (frames.isNotEmpty) {
        final selectedStart = selectedPhotoIndex == null
            ? 0
            : photoFrameStartIndex(selectedPhotoIndex!);
        previewFrameIndex = selectedStart.clamp(0, frames.length - 1).toInt();
        previewFrameBytes = await frames[previewFrameIndex].readAsBytes();
      }
      processProgress = 1;
    } finally {
      isProcessing = false;
      notifyListeners();
    }
  }

  int _sharpenToken = 0;

  /// Gallery Next only copies a small thumb so the editor opens immediately.
  /// This replaces each thumb with a sharp preview file after the screen is up.
  Future<void> sharpenPhotoSources() async {
    final token = ++_sharpenToken;
    for (var i = 0; i < photos.length; i++) {
      if (token != _sharpenToken) return;
      final photo = photos[i];
      try {
        final file = File(photo.path);
        if (!await file.exists()) continue;
        if (await file.length() > 350 * 1024) continue;
        final asset = await AssetEntity.fromId(photo.id);
        if (asset == null || token != _sharpenToken) continue;
        final bytes = await asset
            .thumbnailDataWithSize(const ThumbnailSize(1800, 1800), quality: 93)
            .timeout(const Duration(seconds: 8));
        if (bytes == null || bytes.length < await file.length()) continue;
        if (token != _sharpenToken || i >= photos.length) return;
        if (photos[i].id != photo.id) continue;
        final dest = File('${photo.path}.sharp.jpg');
        await dest.writeAsBytes(bytes, flush: true);
        photos[i] = photos[i].copyWith(path: dest.path);
        await FileImage(file).evict();
        notifyListeners();
      } catch (_) {}
    }
  }

  /// Quick single-frame preview for live UI without full render.
  Future<void> refreshLivePreview() async {
    if (photos.isEmpty) {
      _setPreviewFrame(null);
      notifyListeners();
      return;
    }
    try {
      final (w, h) = previewSize;
      final index = selectedPhotoIndex ?? 0;
      final prepared = await _preparePhoto(photos[index], w, h);
      final baked = await _finalize(
        prepared,
        includeDecorativeFrame: false,
        includeTextOverlays: false,
      );
      _setPreviewFrame(
        Uint8List.fromList(TransitionEngine.encodeJpeg(baked, quality: 85)),
      );
      notifyListeners();
    } catch (_) {
      // Keep previous preview on failure.
    }
  }

  /// Paused timeline scrub. Updates the clock and the visible preview.
  void seekPreviewSeconds(double sec) {
    if (isPreviewPlaying || photos.isEmpty) return;
    final duration = estimatedDurationSec;
    final clamped = duration <= 0 ? 0.0 : sec.clamp(0.0, duration).toDouble();
    _setPreviewPosition(clamped);
    if (isPreviewReady && _previewMemoryFrames.isNotEmpty) {
      if (scrubLive.value != null) scrubLive.value = null;
      final index = (clamped * previewFps)
          .round()
          .clamp(0, _previewMemoryFrames.length - 1)
          .toInt();
      if (index == previewFrameIndex && previewFrameListenable.value != null) {
        return;
      }
      previewFrameIndex = index;
      _setPreviewFrame(_previewMemoryFrames[index]);
      return;
    }
    var t = clamped - (startingCard?.durationSec ?? 0);
    if (t < 0) {
      scrubLive.value = (index: 0, fraction: 0);
      return;
    }
    for (var i = 0; i < photos.length; i++) {
      final span = photos[i].durationSec;
      if (t <= span || i == photos.length - 1) {
        final fraction = span <= 0 ? 0.0 : (t / span).clamp(0.0, 1.0);
        final current = scrubLive.value;
        if (current != null &&
            current.index == i &&
            (current.fraction - fraction).abs() < 0.008) {
          return;
        }
        scrubLive.value = (index: i, fraction: fraction);
        return;
      }
      t -= span;
    }
  }

  double get estimatedDurationSec {
    if (photos.length < 2) return 0;
    return photos.fold<double>(0, (total, photo) => total + photo.durationSec) +
        (startingCard?.durationSec ?? 0) +
        (endingCard?.durationSec ?? 0);
  }
}

class _EditorSnapshot {
  final List<SlideshowPhoto> photos;
  final String transitionId;
  final int? selectedPhotoIndex;

  _EditorSnapshot({
    required this.photos,
    required this.transitionId,
    required this.selectedPhotoIndex,
  });
}
