import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/models.dart';
import 'effect_overlay_service.dart';
import 'frame_compositor.dart';
import 'photo_animation_engine.dart';
import 'transition_engine.dart';

Uint8List _preparePhotoInWorker(Map<String, Object> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Unsupported image file');

  final filter = PhotoFilterPreset.values[args['filter'] as int];
  var filtered = FrameCompositor.applyFilter(decoded, filter);
  final cropLeft = (args['cropLeft'] as num?)?.toDouble() ?? 0;
  final cropTop = (args['cropTop'] as num?)?.toDouble() ?? 0;
  final cropWidthN = (args['cropWidth'] as num?)?.toDouble() ?? 1;
  final cropHeightN = (args['cropHeight'] as num?)?.toDouble() ?? 1;
  final hasRect =
      cropLeft > 0.001 ||
      cropTop > 0.001 ||
      cropWidthN < 0.999 ||
      cropHeightN < 0.999;
  final cropDegrees = (args['cropDegrees'] as num?)?.toDouble() ?? 0;
  if (cropDegrees.abs() > 0.05) {
    final srcW = filtered.width.toDouble();
    final srcH = filtered.height.toDouble();
    final leftPx = cropLeft * srcW;
    final topPx = cropTop * srcH;
    final widthPx = (cropWidthN * srcW).clamp(1, srcW);
    final heightPx = (cropHeightN * srcH).clamp(1, srcH);
    if (filtered.numChannels < 4) {
      filtered = filtered.convert(numChannels: 4);
    }
    filtered = img.copyRotate(
      filtered,
      angle: cropDegrees,
      interpolation: img.Interpolation.linear,
    );
    final rawX = filtered.width / 2 + (leftPx - srcW / 2);
    final rawY = filtered.height / 2 + (topPx - srcH / 2);
    final x = rawX.round().clamp(0, filtered.width - 1);
    final y = rawY.round().clamp(0, filtered.height - 1);
    final cw = widthPx.round().clamp(1, filtered.width - x);
    final ch = heightPx.round().clamp(1, filtered.height - y);
    filtered = img.copyCrop(filtered, x: x, y: y, width: cw, height: ch);
  } else if (hasRect) {
    final x = (cropLeft * filtered.width).round().clamp(0, filtered.width - 1);
    final y = (cropTop * filtered.height).round().clamp(0, filtered.height - 1);
    final cw = (cropWidthN * filtered.width).round().clamp(1, filtered.width - x);
    final ch = (cropHeightN * filtered.height)
        .round()
        .clamp(1, filtered.height - y);
    filtered = img.copyCrop(filtered, x: x, y: y, width: cw, height: ch);
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
  final canvas = FrameCompositor.placeOnCanvas(
    src: filtered,
    w: args['width'] as int,
    h: args['height'] as int,
    bgArgb: args['photoBackground'] as int,
    blurPlate: blurLevel != null ? filtered : null,
    blurLevel: blurLevel ?? 0,
  );
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

class SlideshowProject extends ChangeNotifier {
  final List<SlideshowPhoto> photos = [];
  SlideTheme selectedTheme = AppThemes.all.first;
  bool isEffectOverlayEnabled = false;
  int? selectedPhotoIndex;
  SlideTransitionOption selectedSlideTransition =
      SlideTransitionOption.all.first;
  String? selectedFrameAsset;
  double slideDurationSec = AppConstants.defaultDurationSec;
  MusicTrack? music;
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

  /// In-memory JPEG frames for smooth editor preview (no % overlay).
  final List<Uint8List> _previewMemoryFrames = [];
  final List<img.Image?> _decodedPreview = [];
  final List<String> _decodedPreviewKeys = [];
  final List<int> _previewSegmentCounts = [];
  String? _previewCacheKey;
  int _previewGeneration = 0;
  Timer? _previewTimer;

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
  }) {
    final outStart = totalFrames - outFrames;
    var frame = source;
    if (photo.animationIn != PhotoAnimationType.none &&
        inFrames > 0 &&
        frameIndex < outStart) {
      final progress = frameIndex < inFrames
          ? (frameIndex + 1) / inFrames
          : 1.0;
      frame = PhotoAnimationEngine.apply(
        image: source,
        type: photo.animationIn,
        progress: progress,
        backgroundArgb: background,
      );
    }
    if (photo.animationOut != PhotoAnimationType.none &&
        outFrames > 0 &&
        frameIndex >= outStart) {
      final outIndex = frameIndex - outStart;
      frame = PhotoAnimationEngine.apply(
        image: source,
        type: photo.animationOut,
        progress: (outIndex + 1) / outFrames,
        backgroundArgb: background,
        reverse: true,
      );
    }
    if (photo.animationLoop != PhotoAnimationType.none) {
      final loopFrames = math.max(
        1,
        _animFrames(photo.animationLoopDurationSec, photo.durationSec),
      );
      frame = PhotoAnimationEngine.apply(
        image: frame,
        type: photo.animationLoop,
        progress: (frameIndex % loopFrames) / loopFrames,
        backgroundArgb: background,
      );
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
    notifyListeners();
    final canSplice =
        _previewSegmentCounts.length == photos.length &&
        _previewMemoryFrames.isNotEmpty &&
        isPreviewReady;
    if (canSplice) {
      unawaited(_resplicePhotoPreview(index));
    } else if (photos.length >= AppConstants.minPhotos) {
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
    if (newIndex < 0 || newIndex >= photos.length) return;
    _recordHistory();
    final item = photos.removeAt(oldIndex);
    photos.insert(newIndex, item);
    _clearDecodedPreview();
    notifyListeners();
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
      final baked = await _finalize(image);
      _setPreviewFrame(
        Uint8List.fromList(TransitionEngine.encodeJpeg(baked, quality: 85)),
      );
      notifyListeners();
    } catch (_) {
      // Keep the current frame if a replacement image cannot be decoded.
    }
  }

  void selectTheme(SlideTheme theme) {
    final shouldPrepare =
        selectedTheme.id != theme.id || !isEffectOverlayEnabled;
    selectedTheme = theme;
    isEffectOverlayEnabled = true;
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

  void selectSlideTransition(SlideTransitionOption option) {
    if (selectedSlideTransition.id == option.id) {
      // Re-tap same item: ensure preview is prepared.
      if (!isPreviewReady && !isPreparingPreview) {
        unawaited(preparePreviewFrames());
      }
      return;
    }
    _recordHistory();
    selectedSlideTransition = option;
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(preparePreviewFrames());
  }

  void _invalidatePreviewCache() {
    _previewMemoryFrames.clear();
    _previewSegmentCounts.clear();
    _previewCacheKey = null;
    isPreviewReady = false;
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
    _decodedPreviewKeys.clear();
  }

  Future<img.Image> _cachedPreviewPhoto(int index, int w, int h) async {
    final key = _previewPixelKey(photos[index]);
    while (_decodedPreview.length <= index) {
      _decodedPreview.add(null);
      _decodedPreviewKeys.add('');
    }
    final cached = _decodedPreview[index];
    if (cached != null && _decodedPreviewKeys[index] == key) return cached;
    final image = await _preparePhoto(photos[index], w, h);
    _decodedPreview[index] = image;
    _decodedPreviewKeys[index] = key;
    return image;
  }

  /// Build frames in background after transition select (shows loading UI).
  /// Duration and animation edits pass [showLoading] false so the current
  /// frame stays on screen while only the changed work runs.
  Future<void> preparePreviewFrames({bool showLoading = true}) async {
    if (photos.length < AppConstants.minPhotos || isProcessing) {
      isPreviewReady = false;
      isPreparingPreview = false;
      notifyListeners();
      return;
    }

    final key = _buildPreviewCacheKey();
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
      final built = await _buildPreviewMemoryFrames(
        generation: generation,
        cacheKey: key,
      );
      if (generation != _previewGeneration || built == null) return;
      _previewMemoryFrames
        ..clear()
        ..addAll(built.frames);
      _previewSegmentCounts
        ..clear()
        ..addAll(built.counts);
      _previewCacheKey = key;
      isPreviewReady = _previewMemoryFrames.isNotEmpty;
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

  String _buildPreviewCacheKey() {
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
      isEffectOverlayEnabled,
      selectedSlideTransition.id,
      slideDurationSec,
      aspectRatio.name,
      selectedFrameAsset ?? '',
      backgroundArgb,
      startingCard?.title,
      startingCard?.durationSec,
      endingCard?.title,
      endingCard?.durationSec,
      overlays.length,
    ].join('::');
  }

  void stopPreviewPlayback() {
    _previewGeneration++;
    _previewTimer?.cancel();
    _previewTimer = null;
    final wasPreparing = isPreparingPreview;
    isPreparingPreview = false;
    if (isPreviewPlaying || wasPreparing) {
      isPreviewPlaying = false;
      isPlaying = false;
      notifyListeners();
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
    final selectedStart = selected == null
        ? 0
        : photoFrameStartIndex(selected);
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

    // Slightly gentler than encode FPS so JPEG decode can keep up (less blink).
    final frameMs = (1000 / previewFps).round().clamp(28, 90);
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
        notifyListeners(); // stop icon
        return;
      }
      previewFrameIndex = next;
      // Only update listenables — do NOT notifyListeners (avoids full rebuild blink).
      _setPreviewPosition(next / previewFps);
      _setPreviewFrame(_previewMemoryFrames[next]);
    });
  }

  Future<({List<Uint8List> frames, List<int> counts})?> _buildPreviewMemoryFrames({
    required int generation,
    required String cacheKey,
  }) async {
    final frames = <Uint8List>[];
    final counts = <int>[];
    final (w, h) = previewSize;
    final decoded = <img.Image>[];
    for (var i = 0; i < photos.length; i++) {
      if (generation != _previewGeneration) return null;
      decoded.add(await _cachedPreviewPhoto(i, w, h));
    }
    if (decoded.length < 2) return null;

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
        generation: generation,
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

  Future<void> _resplicePhotoPreview(int index) async {
    if (isEffectOverlayEnabled ||
        index < 0 ||
        index >= photos.length ||
        _previewSegmentCounts.length != photos.length) {
      unawaited(preparePreviewFrames(showLoading: false));
      return;
    }
    final generation = ++_previewGeneration;
    try {
      final (w, h) = previewSize;
      final decoded = <img.Image>[];
      for (var i = 0; i < photos.length; i++) {
        if (generation != _previewGeneration) return;
        decoded.add(await _cachedPreviewPhoto(i, w, h));
      }
      final segment = await _renderPhotoSegment(
        index: index,
        decoded: decoded,
        generation: generation,
      );
      if (segment == null || generation != _previewGeneration) return;
      final start = photoFrameStartIndex(index);
      final oldCount = _previewSegmentCounts[index];
      final end = math.min(start + oldCount, _previewMemoryFrames.length);
      if (start < 0 || start > _previewMemoryFrames.length) {
        unawaited(preparePreviewFrames(showLoading: false));
        return;
      }
      _previewMemoryFrames.replaceRange(start, end, segment);
      _previewSegmentCounts[index] = segment.length;
      _previewCacheKey = _buildPreviewCacheKey();
      isPreviewReady = _previewMemoryFrames.isNotEmpty;
      final frameIndex = start.clamp(0, _previewMemoryFrames.length - 1).toInt();
      previewFrameIndex = frameIndex;
      _setPreviewPosition(frameIndex / previewFps);
      _setPreviewFrame(_previewMemoryFrames[frameIndex]);
      notifyListeners();
    } catch (_) {
      if (generation == _previewGeneration) {
        unawaited(preparePreviewFrames(showLoading: false));
      }
    }
  }

  Future<List<img.Image>> _loadPreviewOverlays(int w, int h) async {
    if (!isEffectOverlayEnabled) return const [];
    final files = await EffectOverlayService.previewFrames(width: w, height: h);
    final images = <img.Image>[];
    for (final file in files) {
      final decoded = TransitionEngine.decode(await file.readAsBytes());
      if (decoded != null) images.add(decoded);
    }
    return images;
  }

  Future<Uint8List> _jpegFrame(
    img.Image image,
    List<img.Image> overlays,
    List<int> frameCursor,
  ) async {
    final baked = await _finalize(image);
    var composed = baked;
    if (overlays.isNotEmpty) {
      final effectIndex =
          ((frameCursor[0] / previewFps) * EffectOverlayService.previewFps)
              .floor() %
          overlays.length;
      composed = EffectOverlayService.screenBlend(composed, overlays[effectIndex]);
    }
    frameCursor[0] = frameCursor[0] + 1;
    return Uint8List.fromList(TransitionEngine.encodeJpeg(composed, quality: 70));
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
    required int generation,
    List<img.Image> overlays = const [],
    List<int>? frameCursor,
  }) async {
    if (generation != _previewGeneration) return null;
    final photo = photos[index];
    final effect = selectedSlideTransition.type;
    final pairs = decoded.length - 1;
    final totalFrames = frameCountForDuration(photo.durationSec);
    final transitionFrames = index < pairs && effect != SlideTransitionType.none
        ? math.min(AppConstants.framesPerTransition, totalFrames)
        : 0;
    final background = photo.backgroundArgb ?? backgroundArgb;
    final (inFrames, outFrames) = _splitAnimFrames(photo, totalFrames);
    final soloFrames = totalFrames - transitionFrames;
    final frames = <Uint8List>[];
    final cursor = frameCursor ?? <int>[0];
    Uint8List? lastBytes;
    img.Image? lastSource;

    Future<bool> pushFrame(img.Image image) async {
      if (generation != _previewGeneration) return false;
      if (overlays.isEmpty && identical(image, lastSource) && lastBytes != null) {
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
        ),
      );
      if (!kept) return null;
      // Let taps and frames run. A tight image loop ANRs Android and the
      // process is killed ("Lost connection to device").
      await Future<void>.delayed(Duration.zero);
    }

    if (transitionFrames > 0) {
      final option = selectedSlideTransition;
      for (var t = 0; t < transitionFrames; t++) {
        if (generation != _previewGeneration) return null;
        final progress = (t + 1) / transitionFrames;
        final fromFrame = _animatePhotoFrame(
          source: decoded[index],
          photo: photo,
          frameIndex: soloFrames + t,
          totalFrames: totalFrames,
          inFrames: inFrames,
          outFrames: outFrames,
          background: background,
        );
        final blended = TransitionEngine.apply(
          from: fromFrame,
          to: decoded[index + 1],
          type: effect,
          progress: progress,
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
    return frames;
  }


  void selectFrame(String? assetPath) {
    selectedFrameAsset = assetPath;
    notifyListeners();
  }

  void setDuration(double seconds) {
    slideDurationSec = seconds;
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(preparePreviewFrames());
  }

  void setMusic(MusicTrack? track) {
    music = track;
    notifyListeners();
  }

  void setMusicVolume(int volume) {
    if (music == null) return;
    music = music!.copyWith(volume: volume.clamp(0, 100));
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
    notifyListeners();
  }

  void updateOverlay(SlideOverlay overlay) {
    final i = overlays.indexWhere((e) => e.id == overlay.id);
    if (i < 0) return;
    overlays[i] = overlay;
    notifyListeners();
  }

  void removeOverlay(String id) {
    overlays.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void clearOverlays() {
    overlays.clear();
    notifyListeners();
  }

  Future<img.Image> _preparePhoto(SlideshowPhoto photo, int w, int h) async {
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
    final preparedBytes = await compute(_preparePhotoInWorker, workerArgs);
    final prepared = TransitionEngine.decode(preparedBytes);
    if (prepared == null) {
      throw Exception('Could not decode ${photo.path}');
    }
    return prepared;
  }

  Future<img.Image> _finalize(img.Image frame) {
    return FrameCompositor.bakeOverlays(
      base: frame,
      frameAsset: selectedFrameAsset,
      overlays: List.of(overlays),
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
      final decoded = <img.Image>[];
      for (final photo in photos) {
        decoded.add(await _preparePhoto(photo, w, h));
      }
      if (decoded.length < 2) {
        throw Exception('Could not decode enough photos');
      }

      final frames = <File>[];
      var frameIndex = 0;
      final pairs = decoded.length - 1;

      Future<void> writeFrame(img.Image image) async {
        final baked = await _finalize(image);
        final file = File(
          p.join(
            outDir.path,
            'img${frameIndex.toString().padLeft(5, '0')}.jpg',
          ),
        );
        await file.writeAsBytes(
          TransitionEngine.encodeJpeg(baked, quality: 82),
        );
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
      final baked = await _finalize(prepared);
      _setPreviewFrame(
        Uint8List.fromList(TransitionEngine.encodeJpeg(baked, quality: 85)),
      );
      notifyListeners();
    } catch (_) {
      // Keep previous preview on failure.
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
