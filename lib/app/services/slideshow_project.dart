import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../models/models.dart';
import 'frame_compositor.dart';
import 'transition_engine.dart';

Uint8List _preparePhotoInWorker(Map<String, Object> args) {
  final sourceBytes = args['bytes'] as Uint8List;
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) throw const FormatException('Unsupported image file');

  final filter = PhotoFilterPreset.values[args['filter'] as int];
  final filtered = FrameCompositor.applyFilter(decoded, filter);
  final canvas = FrameCompositor.placeOnCanvas(
    src: filtered,
    w: args['width'] as int,
    h: args['height'] as int,
    bgArgb: args['background'] as int,
  );
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

class SlideshowProject extends ChangeNotifier {
  final List<SlideshowPhoto> photos = [];
  SlideTheme selectedTheme = AppThemes.all.first;
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

  double get previewFps => AppConstants.framesPerTransition / slideDurationSec;

  void setPhotos(List<SlideshowPhoto> list) {
    photos
      ..clear()
      ..addAll(list);
    generatedFrames = [];
    _setPreviewFrame(null);
    _invalidatePreviewCache();
    notifyListeners();
  }

  void reorderPhoto(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (newIndex < 0 || newIndex >= photos.length) return;
    final item = photos.removeAt(oldIndex);
    photos.insert(newIndex, item);
    notifyListeners();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    photos.removeAt(index);
    notifyListeners();
  }

  void selectTheme(SlideTheme theme) {
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
    notifyListeners();
  }

  void selectSlideTransition(SlideTransitionOption option) {
    if (selectedSlideTransition.id == option.id) {
      // Re-tap same item: ensure preview is prepared.
      if (!isPreviewReady && !isPreparingPreview) {
        unawaited(preparePreviewFrames());
      }
      return;
    }
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
        previewFrameIndex = 0;
        _setPreviewPosition(0);
        _setPreviewFrame(_previewMemoryFrames.first);
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
      photos.map((e) => '${e.path}:${e.filter.name}').join('|'),
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
    previewFrameIndex = 0;
    _setPreviewPosition(0);
    _setPreviewFrame(_previewMemoryFrames.first);
    notifyListeners(); // play/pause icon only

    // Slightly gentler than encode FPS so JPEG decode can keep up (less blink).
    final frameMs = (1000 / previewFps).round().clamp(28, 90);
    _previewTimer = Timer.periodic(Duration(milliseconds: frameMs), (timer) {
      if (generation != _previewGeneration || !isPreviewPlaying) {
        timer.cancel();
        return;
      }
      final next = previewFrameIndex + 1;
      if (next >= _previewMemoryFrames.length) {
        timer.cancel();
        _previewTimer = null;
        isPreviewPlaying = false;
        isPlaying = false;
        previewFrameIndex = 0;
        _setPreviewPosition(0);
        if (_previewMemoryFrames.isNotEmpty) {
          _setPreviewFrame(_previewMemoryFrames.first);
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

    Uint8List? lastBytes;
    img.Image? lastSource;

    Future<void> pushFrame(img.Image image) async {
      if (generation != _previewGeneration) return;
      // Reuse identical consecutive frames (hold) — same bytes = no re-decode blink.
      if (identical(image, lastSource) && lastBytes != null) {
        _previewMemoryFrames.add(lastBytes!);
        return;
      }
      final baked = await _finalize(image);
      final bytes = Uint8List.fromList(
        TransitionEngine.encodeJpeg(baked, quality: 70),
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
      final n = (startingCard!.durationSec * previewFps).round().clamp(4, 40);
      for (var i = 0; i < n; i++) {
        if (generation != _previewGeneration) return;
        await pushFrame(cardImg);
      }
    }

    for (var i = 0; i < pairs; i++) {
      if (generation != _previewGeneration) return;
      final from = decoded[i];
      final to = decoded[i + 1];

      for (var hold = 0; hold < AppConstants.holdFrames; hold++) {
        if (generation != _previewGeneration) return;
        await pushFrame(from);
      }

      // None = hard cut (one frame of next), skip long blend.
      if (effect == SlideTransitionType.none) {
        await pushFrame(to);
        continue;
      }

      final option = selectedSlideTransition;
      for (var t = 0; t < AppConstants.framesPerTransition; t++) {
        if (generation != _previewGeneration) return;
        final progress = (t + 1) / AppConstants.framesPerTransition;
        final blended = TransitionEngine.apply(
          from: from,
          to: to,
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

    if (generation != _previewGeneration) return;
    final last = decoded.last;
    for (var hold = 0; hold < AppConstants.holdFrames; hold++) {
      if (generation != _previewGeneration) return;
      await pushFrame(last);
    }

    if (endingCard != null) {
      final cardImg = await FrameCompositor.makeTitleCard(
        card: endingCard!,
        w: w,
        h: h,
      );
      final n = (endingCard!.durationSec * previewFps).round().clamp(4, 40);
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
      'background': backgroundArgb,
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
      // Prefer explicit Slide-panel transition; fall back to theme mix.
      final effectList = <SlideTransitionType>[selectedSlideTransition.type];
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
        introFrames = (startingCard!.durationSec * (22.0 / slideDurationSec))
            .round()
            .clamp(8, 60);
        for (var i = 0; i < introFrames; i++) {
          await writeFrame(cardImg);
        }
      }

      final totalFramesEstimate =
          introFrames +
          pairs * (AppConstants.framesPerTransition + AppConstants.holdFrames) +
          AppConstants.holdFrames +
          (endingCard != null ? 16 : 0);

      for (var i = 0; i < pairs; i++) {
        final from = decoded[i];
        final to = decoded[i + 1];
        final effect = effectList[i % effectList.length];

        for (var hold = 0; hold < AppConstants.holdFrames; hold++) {
          await writeFrame(from);
          processProgress = (frameIndex / totalFramesEstimate).clamp(0.0, 1.0);
          onProgress?.call(processProgress);
        }

        final option = selectedSlideTransition;
        if (effect == SlideTransitionType.none) {
          await writeFrame(to);
          processProgress = (frameIndex / totalFramesEstimate).clamp(0.0, 1.0);
          onProgress?.call(processProgress);
          continue;
        }

        for (var t = 0; t < AppConstants.framesPerTransition; t++) {
          final progress = (t + 1) / AppConstants.framesPerTransition;
          final blended = TransitionEngine.apply(
            from: from,
            to: to,
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
          processProgress = (frameIndex / totalFramesEstimate).clamp(0.0, 1.0);
          onProgress?.call(processProgress);
          if (t % 3 == 0) {
            previewFrameBytes = await frames.last.readAsBytes();
            previewFrameIndex = frameIndex - 1;
            notifyListeners();
          }
        }
      }

      final last = decoded.last;
      for (var hold = 0; hold < AppConstants.holdFrames; hold++) {
        await writeFrame(last);
      }

      if (endingCard != null) {
        final cardImg = await FrameCompositor.makeTitleCard(
          card: endingCard!,
          w: w,
          h: h,
        );
        final n = (endingCard!.durationSec * (22.0 / slideDurationSec))
            .round()
            .clamp(8, 60);
        for (var i = 0; i < n; i++) {
          await writeFrame(cardImg);
        }
      }

      generatedFrames = frames;
      if (frames.isNotEmpty) {
        previewFrameBytes = await frames.first.readAsBytes();
        previewFrameIndex = 0;
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
      final prepared = await _preparePhoto(photos.first, w, h);
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
    final pairs = photos.length - 1;
    var frames =
        pairs * (AppConstants.framesPerTransition + AppConstants.holdFrames) +
        AppConstants.holdFrames;
    final fps = 22.0 / slideDurationSec;
    if (startingCard != null) {
      frames += (startingCard!.durationSec * fps).round();
    }
    if (endingCard != null) {
      frames += (endingCard!.durationSec * fps).round();
    }
    return frames / fps;
  }
}
