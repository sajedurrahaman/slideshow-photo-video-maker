import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

  final canvas = FrameCompositor.placeOnCanvas(
    src: filtered,
    w: args['width'] as int,
    h: args['height'] as int,
    bgArgb: args['photoBackground'] as int,
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
    } else if (photos.length < AppConstants.minPhotos) {
      unawaited(_refreshPhotoPreview(index));
    } else if (!isPreparingPreview) {
      unawaited(preparePreviewFrames());
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

  void updatePhoto(int index, SlideshowPhoto photo) {
    if (index < 0 || index >= photos.length) return;
    _recordHistory();
    photos[index] = photo;
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    if (photos.length >= AppConstants.minPhotos) {
      unawaited(preparePreviewFrames());
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
    _previewCacheKey = null;
    isPreviewReady = false;
  }

  /// Build frames in background after transition select (shows loading UI).
  Future<void> preparePreviewFrames() async {
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
    isPreparingPreview = true;
    isPreviewReady = false;
    notifyListeners();

    try {
      await _buildPreviewMemoryFrames(generation: generation, cacheKey: key);
      if (generation != _previewGeneration) return;
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
                '${e.backgroundArgb}:${e.cropAspectRatio}:${e.mirrored}:'
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
    if (isPreviewPlaying) {
      isPreviewPlaying = false;
      isPlaying = false;
      notifyListeners();
    }
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

  Future<void> _buildPreviewMemoryFrames({
    required int generation,
    required String cacheKey,
  }) async {
    _previewMemoryFrames.clear();
    final (w, h) = previewSize;
    final decoded = <img.Image>[];
    for (final photo in photos) {
      if (generation != _previewGeneration) return;
      decoded.add(await _preparePhoto(photo, w, h));
    }
    if (decoded.length < 2) return;

    final effect = selectedSlideTransition.type;
    final pairs = decoded.length - 1;
    final overlayFrames = isEffectOverlayEnabled
        ? await EffectOverlayService.previewFrames(width: w, height: h)
        : const <File>[];
    var renderedFrameIndex = 0;

    Uint8List? lastBytes;
    img.Image? lastSource;

    Future<void> pushFrame(img.Image image) async {
      if (generation != _previewGeneration) return;
      // Reuse identical consecutive frames (hold) — same bytes = no re-decode blink.
      if (overlayFrames.isEmpty &&
          identical(image, lastSource) &&
          lastBytes != null) {
        _previewMemoryFrames.add(lastBytes!);
        return;
      }
      final baked = await _finalize(image);
      var composed = baked;
      if (overlayFrames.isNotEmpty) {
        final effectTime = renderedFrameIndex / previewFps;
        final effectIndex =
            ((effectTime * EffectOverlayService.previewFps).floor()) %
            overlayFrames.length;
        final effectBytes = await overlayFrames[effectIndex].readAsBytes();
        final effectFrame = TransitionEngine.decode(effectBytes);
        if (effectFrame != null) {
          composed = EffectOverlayService.screenBlend(composed, effectFrame);
        }
      }
      renderedFrameIndex++;
      final bytes = Uint8List.fromList(
        TransitionEngine.encodeJpeg(composed, quality: 70),
      );
      lastSource = image;
      lastBytes = bytes;
      _previewMemoryFrames.add(bytes);
    }

    if (startingCard != null) {
      final cardImg = await FrameCompositor.makeTitleCard(
        card: startingCard!,
        w: w,
        h: h,
      );
      final n = frameCountForDuration(startingCard!.durationSec).clamp(4, 300);
      for (var i = 0; i < n; i++) {
        if (generation != _previewGeneration) return;
        await pushFrame(cardImg);
      }
    }

    for (var i = 0; i < decoded.length; i++) {
      if (generation != _previewGeneration) return;
      final photo = photos[i];
      final totalFrames = frameCountForDuration(photo.durationSec);
      final transitionFrames = i < pairs && effect != SlideTransitionType.none
          ? math.min(AppConstants.framesPerTransition, totalFrames)
          : 0;
      final background = photo.backgroundArgb ?? backgroundArgb;
      final (inFrames, outFrames) = _splitAnimFrames(photo, totalFrames);
      final soloFrames = totalFrames - transitionFrames;

      for (var hold = 0; hold < soloFrames; hold++) {
        if (generation != _previewGeneration) return;
        await pushFrame(
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
      }

      if (transitionFrames > 0) {
        final option = selectedSlideTransition;
        for (var t = 0; t < transitionFrames; t++) {
          if (generation != _previewGeneration) return;
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
          await pushFrame(blended);
        }
      }
    }

    if (generation != _previewGeneration) return;
    if (endingCard != null) {
      final cardImg = await FrameCompositor.makeTitleCard(
        card: endingCard!,
        w: w,
        h: h,
      );
      final n = frameCountForDuration(endingCard!.durationSec).clamp(4, 300);
      for (var i = 0; i < n; i++) {
        if (generation != _previewGeneration) return;
        await pushFrame(cardImg);
      }
    }

    if (generation == _previewGeneration) {
      _previewCacheKey = cacheKey;
    }
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
    aspectRatio = preset;
    generatedFrames = [];
    stopPreviewPlayback();
    _invalidatePreviewCache();
    notifyListeners();
    unawaited(preparePreviewFrames());
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
    final preparedBytes = await compute(_preparePhotoInWorker, {
      'bytes': bytes,
      'filter': photo.filter.index,
      'width': w,
      'height': h,
      'photoBackground': photo.backgroundArgb ?? backgroundArgb,
      'cropAspectRatio': photo.cropAspectRatio ?? 0.0,
      'mirrored': photo.mirrored,
      'flipped': photo.flipped,
      'rotationQuarterTurns': photo.rotationQuarterTurns,
    });
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
