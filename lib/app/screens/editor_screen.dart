import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/effect_overlay_service.dart';
import '../services/slideshow_project.dart';
import 'crop_screen.dart';
import '../widgets/editTool_sheet.dart';
import '../widgets/text_tools_sheet.dart';

enum EditorTool {
  slide,
  text,
  effects,
  starting,
  ending,
  music,
  frame,
  filter,
  sticker,
  ratio,
  bg,
}

/// Hidden from the editor toolbar for this release.
const _toolsHiddenThisRelease = <EditorTool>{
  EditorTool.starting,
  EditorTool.ending,
  EditorTool.filter,
  EditorTool.sticker,
};

enum _PhotoTool {
  duration,
  animation,
  delete,
  background,
  crop,
  mirror,
  flip,
  rotate,
  replace,
}

enum _AnimationPhase { inAnimation, outAnimation }

enum _CanvasSheetTab { ratio, background }

enum _LiveMode { idle, inPhase, outPhase, full }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  EditorTool? _tool;
  _PhotoTool? _photoTool;
  _AnimationPhase _animationPhase = _AnimationPhase.inAnimation;
  _CanvasSheetTab _canvasSheetTab = _CanvasSheetTab.background;
  double? _durationSliderValue;
  double? _inDurationDrag;
  double? _outDurationDrag;
  int _liveToken = 0;
  _LiveMode _liveMode = _LiveMode.idle;

  /// After Music sheet close/check — photo-style music tools navbar.
  bool _photoDurationDragging = false;
  bool _photoReordering = false;
  double _reorderDragDx = 0;
  double? _livePhotoDurationSec;
  bool _musicToolsOpen = false;
  bool _musicVolumeOpen = false;
  bool _musicEditOpen = false;

  /// Music timeline tapped → tools become active.
  bool _musicTrackSelected = false;

  /// After Effects picker confirm — music-style effects tools navbar.
  bool _effectsToolsOpen = false;
  bool _effectsTrackSelected = false;

  /// Text tools (CapCut-style Template / Font / Color).
  bool _textToolsOpen = false;
  String? _selectedTextOverlayId;
  final _textController = TextEditingController();
  final _textFocusNode = FocusNode();
  final _stripController = ScrollController();

  /// Keeps the photo ListView Element across panel branch switches so the
  /// ScrollController is never attached to two scroll views at once.
  final _photoStripListKey = GlobalKey();

  static const _sheetHeight = 180.0;
  static const _timelineHeaderHeight = 48.0;
  static const _photoToolbarHeight = 72.0;
  static const _musicTrackHeight = 28.0;

  /// Gap between photo thumbs and music lane / placeholder line.
  static const _musicUnderPhotosGap = 4.0;
  static const _musicPlaceholderH = 2.0;

  /// Compact slot for the inactive track's thin line (tools open / Done).
  static const _collapsedLineSlotH = 6.0;
  static const _collapsedToActiveGap = 2.0;

  /// Effect lane sits this far above the strip bottom edge.
  static const _effectBottomPad = 5.0;
  static const _plusW = 52.0;
  static const _pixelsPerSecond = 44.0;
  static const _thumbH = 60.0;
  static const _transitionMarkerSize = 22.0;
  static const _stripPadLeft = 16.0;

  SlideshowProject? _listenedProject;

  bool _syncingStrip = false;
  bool _userScrubbing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stripController.addListener(_onStripScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the editor paint first so Next→route is not blocked by decode.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      final project = context.read<SlideshowProject>();
      await project.refreshLivePreview();
      if (!mounted) return;
      unawaited(project.sharpenPhotoSources());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Home / Recents → stop slideshow preview audio.
      context.read<SlideshowProject>().stopPreviewPlayback();
      if (_liveMode != _LiveMode.idle && mounted) {
        setState(() => _liveMode = _LiveMode.idle);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final project = context.read<SlideshowProject>();
    if (!identical(_listenedProject, project)) {
      _listenedProject?.previewPositionListenable.removeListener(
        _onPreviewPosition,
      );
      _listenedProject = project;
      _listenedProject!.previewPositionListenable.addListener(
        _onPreviewPosition,
      );
    }
  }

  /// Safe while the strip ListView is mounting/unmounting across layout branches.
  double get _stripOffset {
    final c = _stripController;
    if (c.positions.length != 1) return 0.0;
    return c.offset;
  }

  bool get _stripReady => _stripController.positions.length == 1;

  void _onStripScroll() {
    if (_syncingStrip || !_stripReady || !mounted) return;
    final project = _listenedProject;
    if (project == null) return;
    if (project.selectedPhotoIndex != null) return;
    // User scrub while playing → pause so strip isn't yanked by playhead sync.
    if (project.isPreviewPlaying) {
      project.stopPreviewPlayback();
    }
    _userScrubbing = true;
    final seconds =
        _stripOffset / _pixelsPerSecond +
        (project.startingCard?.durationSec ?? 0);
    project.seekPreviewSeconds(seconds);
    _userScrubbing = false;
  }

  /// Scrub timeline by dragging the music row (same as photo strip scroll).
  void _scrollTimelineByDx(double dx) {
    if (!_stripReady || !mounted) return;
    final project = context.read<SlideshowProject>();
    if (project.isPreviewPlaying) {
      project.stopPreviewPlayback();
    }
    final max = _stripController.position.maxScrollExtent;
    final next = (_stripOffset - dx).clamp(0.0, max);
    _userScrubbing = true;
    _stripController.jumpTo(next);
    final seconds =
        next / _pixelsPerSecond + (project.startingCard?.durationSec ?? 0);
    project.seekPreviewSeconds(seconds);
    _userScrubbing = false;
  }

  /// Long-press drag on selected photo: move left/right to change index.
  void _applyPhotoReorderDrag({
    required SlideshowProject project,
    required int selectedIndex,
    required double deltaDx,
  }) {
    if (!_photoReordering || project.photos.isEmpty) return;
    final nextDx = _reorderDragDx + deltaDx;
    // Content-space center of the dragged clip (relative; scroll cancels out).
    var startPx = 0.0;
    for (var i = 0; i < selectedIndex; i++) {
      startPx += project.photos[i].durationSec * _pixelsPerSecond;
    }
    final selfW = project.photos[selectedIndex].durationSec * _pixelsPerSecond;
    final visualCenter = startPx + selfW / 2 + nextDx;

    var acc = 0.0;
    var target = selectedIndex;
    for (var i = 0; i < project.photos.length; i++) {
      final w = project.photos[i].durationSec * _pixelsPerSecond;
      final mid = acc + w / 2;
      if (visualCenter < mid) {
        target = i;
        break;
      }
      target = i;
      acc += w;
    }

    if (target != selectedIndex) {
      HapticFeedback.selectionClick();
      project.reorderPhoto(selectedIndex, target);
      // After reorder, Positioned.left jumps to the new slot — keep the same
      // visual center under the finger by adjusting residual drag.
      var newStart = 0.0;
      for (var i = 0; i < target; i++) {
        newStart += project.photos[i].durationSec * _pixelsPerSecond;
      }
      setState(() {
        _reorderDragDx = visualCenter - (newStart + selfW / 2);
      });
    } else {
      setState(() => _reorderDragDx = nextDx);
    }
  }

  /// Photo index currently under the fixed green playhead (for "+" insert).
  /// Returns that index so new images are inserted *before* it.
  int _photoIndexAtPlayhead(SlideshowProject project) {
    if (project.photos.isEmpty) return 0;
    final t = _stripOffset / _pixelsPerSecond;
    var acc = 0.0;
    for (var i = 0; i < project.photos.length; i++) {
      final dur = project.photos[i].durationSec;
      if (t < acc + dur - 1e-6) return i;
      acc += dur;
    }
    return project.photos.length;
  }

  void _onPreviewPosition() {
    if (_userScrubbing) return;
    if (!mounted || _tool != null) return;
    if (!_stripReady) return;
    final project = _listenedProject;
    if (project == null) return;
    _syncStripToPlayhead(project: project);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listenedProject?.previewPositionListenable.removeListener(
      _onPreviewPosition,
    );
    _stripController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final project = context.read<SlideshowProject>();
    if (project.selectedPhotoIndex != null) {
      if (project.isPreviewPlaying) {
        project.stopPreviewPlayback();
        setState(() => _liveMode = _LiveMode.idle);
        return;
      }
      project.startLiveClip();
      setState(() {
        _liveToken++;
        _liveMode = _LiveMode.full;
      });
      return;
    }
    try {
      await project.togglePreviewPlayback();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Preview failed: $e')));
    }
  }

  String _fmt(double sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).floor().toString().padLeft(2, '0');
    return '$m:$s';
  }

  double _timelineDuration(SlideshowProject project) {
    return project.estimatedDurationSec;
  }

  Widget _timeText(SlideshowProject project) {
    final duration = _timelineDuration(project);
    final previewDuration = project.estimatedDurationSec;
    return ValueListenableBuilder<double>(
      valueListenable: project.previewPositionListenable,
      builder: (_, pos, _) {
        final timelinePosition = previewDuration > 0
            ? pos / previewDuration * duration
            : pos;
        return Text(
          '${_fmt(timelinePosition.clamp(0.0, duration).toDouble())} / '
          '${_fmt(duration)}',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  void _dismissTool() {
    setState(() => _tool = null);
  }

  void _openTextTools() {
    final project = context.read<SlideshowProject>();
    project.stopPreviewPlayback();
    // Navbar Text always starts a *new* text. Edit existing via canvas Edit handle.
    _textController.text = '';
    setState(() {
      _tool = null;
      _musicToolsOpen = false;
      _effectsToolsOpen = false;
      _textToolsOpen = true;
      _selectedTextOverlayId = null;
      _photoTool = null;
    });
    project.clearTimelinePhotoSelection();
    // Focus input so keyboard opens for the new text.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  void _closeTextTools() {
    _textFocusNode.unfocus();
    setState(() {
      _textToolsOpen = false;
      _selectedTextOverlayId = null;
      _tool = null;
    });
    unawaited(context.read<SlideshowProject>().refreshLivePreview());
  }

  void _finishMusicPicker() {
    setState(() {
      _tool = null;
      _musicToolsOpen = true;
      _musicVolumeOpen = false;
      _musicEditOpen = false;
      // Unselected until user taps the music timeline.
      _musicTrackSelected = false;
    });
  }

  void _closeMusicTools() {
    setState(() {
      _musicToolsOpen = false;
      _musicVolumeOpen = false;
      _musicEditOpen = false;
      _musicTrackSelected = false;
      _tool = null;
    });
  }

  void _finishEffectsPicker() {
    final hasEffect =
        context.read<SlideshowProject>().selectedOverlayEffect != null;
    setState(() {
      _tool = null;
      _effectsToolsOpen = true;
      _effectsTrackSelected = hasEffect;
      _musicToolsOpen = false;
    });
  }

  void _closeEffectsTools() {
    setState(() {
      _effectsToolsOpen = false;
      _effectsTrackSelected = false;
      _tool = null;
    });
  }

  bool _hasEffectLane(SlideshowProject project) =>
      project.isEffectOverlayEnabled && project.selectedOverlayEffect != null;

  /// Under-photo rows: music and/or effect timeline lanes.
  double _underPhotosH(SlideshowProject project) {
    final music = project.music != null;
    final effect = _hasEffectLane(project);
    if (!music && !effect) return 0;
    final both = music && effect;
    final toolsOpen = _musicToolsOpen || _effectsToolsOpen;
    if (both) {
      // Thin line tightly above active bar (tools) or above other thin line (Done).
      final lowerH = toolsOpen ? _musicTrackHeight : _collapsedLineSlotH;
      return _musicUnderPhotosGap +
          _collapsedLineSlotH +
          _collapsedToActiveGap +
          lowerH +
          _effectBottomPad;
    }
    return _musicUnderPhotosGap + _musicTrackHeight + _effectBottomPad;
  }

  Future<void> _pickLocalMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;
    context.read<SlideshowProject>().addLocalMusicTrack(
      MusicTrack(path: path, title: result.files.single.name),
    );
  }

  /// Preview row shown inside SectionSheet for every tool.
  Widget _previewRow(SlideshowProject project) {
    final disabled = project.isProcessing || project.isPreparingPreview;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _timeText(project),
          ),
        ),
        Expanded(
          child: Center(
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: disabled ? null : _preview,
              icon: Icon(
                project.isPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 32,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 88),
      ],
    );
  }

  /// Idle editor chrome: time + play + undo/redo (same slot as slide headerRow).
  Widget _idlePreviewRow(SlideshowProject project) {
    final disabled = project.isProcessing || project.isPreparingPreview;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _timeText(project),
          ),
        ),
        Expanded(
          child: Center(
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: disabled ? null : _preview,
              icon: Icon(
                project.isPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 32,
              color: Colors.black87,
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: project.selectedPhotoIndex == null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: project.canUndo ? () => project.undo() : null,
                      icon: Icon(
                        Icons.undo_rounded,
                        color: project.canUndo
                            ? Colors.black87
                            : Colors.black26,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: project.canRedo ? () => project.redo() : null,
                      icon: Icon(
                        Icons.redo_rounded,
                        color: project.canRedo
                            ? Colors.black87
                            : Colors.black26,
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ],
    );
  }

  Widget _idleToolPanel(
    SlideshowProject project, {
    Widget? timelineContent,
    double height = _sheetHeight,
    double timelineHeaderHeight = _timelineHeaderHeight,
  }) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final playheadX = constraints.maxWidth / 2;
          return Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: timelineHeaderHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: _idlePreviewRow(project),
                    ),
                  ),
                  Expanded(
                    child: timelineContent ?? _photoStrip(project, playheadX),
                  ),
                ],
              ),
              // Playhead — same X as the centered play button, through the strip.
              if (timelineContent == null)
                Positioned(
                  left: playheadX - 1,
                  top: 40,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(width: 2, color: AppColors.primary),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _syncStripToPlayhead({required SlideshowProject project}) {
    if (!_stripReady) return;
    if (project.photos.isEmpty) return;
    final trackWidth = project.photos.fold<double>(
      0,
      (sum, photo) => sum + photo.durationSec * _pixelsPerSecond,
    );
    if (trackWidth <= 0) return;
    final photoDuration = trackWidth / _pixelsPerSecond;
    final timelinePosition =
        (project.previewPositionSec - (project.startingCard?.durationSec ?? 0))
            .clamp(0.0, photoDuration)
            .toDouble();
    final target = timelinePosition * _pixelsPerSecond;
    final max = _stripController.position.maxScrollExtent;
    final next = target.clamp(0.0, max).toDouble();
    if ((_stripOffset - next).abs() < 0.5) return;
    _syncingStrip = true;
    _stripController.jumpTo(next);
    _syncingStrip = false;
  }

  Widget _photoStrip(SlideshowProject project, double playheadX) {
    // Each clip width reflects that photo's independently editable duration.
    final leftPad = playheadX.clamp(0.0, 800.0).toDouble();
    final underH = _underPhotosH(project);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_musicTrackSelected) {
          setState(() {
            _musicTrackSelected = false;
            _musicVolumeOpen = false;
          });
        }
        if (_effectsTrackSelected) {
          setState(() => _effectsTrackSelected = false);
        }
        if (project.selectedPhotoIndex != null) {
          setState(() {
            _tool = null;
            _photoTool = null;
            _durationSliderValue = null;
          });
          project.clearTimelinePhotoSelection();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Photos + music/effect lanes as one block, vertically centered.
          final blockH = _thumbH + underH;
          final top = ((constraints.maxHeight - blockH) / 2).clamp(
            0.0,
            double.infinity,
          );
          final hasMusic = project.music != null;
          final hasEffect = _hasEffectLane(project);
          // Shared bottom slot for active music/effect tools timeline.
          final toolsOpen = _musicToolsOpen || _effectsToolsOpen;
          final lowerH = toolsOpen || !(hasMusic && hasEffect)
              ? _musicTrackHeight
              : _collapsedLineSlotH;
          final bottomSlotTop =
              top + _thumbH + underH - _effectBottomPad - lowerH;
          // Thin "other" line sits just above the active / lower timeline.
          final otherLineTop =
              bottomSlotTop - _collapsedToActiveGap - _collapsedLineSlotH;

          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: _thumbH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ListView.builder(
                      key: _photoStripListKey,
                      controller: _stripController,
                      scrollDirection: Axis.horizontal,
                      // Lock strip while trimming duration or reordering a clip.
                      physics: (_photoDurationDragging || _photoReordering)
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(leftPad, 0, playheadX, 0),
                      itemCount: project.photos.length,
                      itemBuilder: (context, photoIndex) {
                        final photo = project.photos[photoIndex];
                        final selected =
                            project.selectedPhotoIndex == photoIndex;
                        final durSec =
                            (selected && _livePhotoDurationSec != null)
                            ? _livePhotoDurationSec!
                            : photo.durationSec;
                        final clipWidth = durSec * _pixelsPerSecond;
                        final thumbnailCount = durSec.ceil();

                        Widget thumbRow({
                          required double width,
                          required double height,
                        }) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              children: [
                                for (var i = 0; i < thumbnailCount; i++)
                                  SizedBox(
                                    width: (width - i * _pixelsPerSecond)
                                        .clamp(0.0, _pixelsPerSecond)
                                        .toDouble(),
                                    height: height,
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.white70,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: CroppedPhotoView(
                                        photo: photo,
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.low,
                                        cacheWidth: 240,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        // Layout width = image only. Selection chrome is painted
                        // in the overlay above so handles overlap neighbors.
                        return SizedBox(
                          width: clipWidth,
                          height: _thumbH,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _tool = null;
                                      _photoTool = null;
                                      _durationSliderValue = null;
                                      _liveMode = _LiveMode.idle;
                                      _livePhotoDurationSec = null;
                                    });
                                    project.selectTimelinePhoto(photoIndex);
                                  },
                                  child: thumbRow(
                                    width: clipWidth,
                                    height: _thumbH,
                                  ),
                                ),
                              ),
                              if (photoIndex > 0 &&
                                  project.selectedPhotoIndex == null)
                                Positioned(
                                  left: -_transitionMarkerSize / 2,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: GestureDetector(
                                      onLongPress: () =>
                                          project.removePhoto(photoIndex),
                                      onTap: () {
                                        project.clearTimelinePhotoSelection();
                                        setState(() {
                                          _tool = EditorTool.slide;
                                          _photoTool = null;
                                        });
                                        if (!project.isPreviewReady &&
                                            !project.isPreparingPreview) {
                                          project.preparePreviewFrames();
                                        }
                                      },
                                      child: Container(
                                        width: _transitionMarkerSize,
                                        height: _transitionMarkerSize,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x33000000),
                                              blurRadius: 4,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.compare_arrows_rounded,
                                          size: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (project.selectedPhotoIndex != null)
                      ListenableBuilder(
                        listenable: _stripController,
                        builder: (context, _) {
                          final sel = project.selectedPhotoIndex!;
                          if (sel < 0 || sel >= project.photos.length) {
                            return const SizedBox.shrink();
                          }
                          final photo = project.photos[sel];
                          final durSec =
                              _livePhotoDurationSec ?? photo.durationSec;
                          final clipW = durSec * _pixelsPerSecond;
                          var startPx = 0.0;
                          for (var i = 0; i < sel; i++) {
                            startPx +=
                                project.photos[i].durationSec *
                                _pixelsPerSecond;
                          }
                          final scroll = _stripOffset;
                          const handleW = _SelectedPhotoClip.handleW;
                          final left = leftPad + startPx - scroll - handleW;

                          Widget thumbRow({
                            required double width,
                            required double height,
                          }) {
                            final thumbnailCount = durSec.ceil();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
                                children: [
                                  for (var i = 0; i < thumbnailCount; i++)
                                    SizedBox(
                                      width: (width - i * _pixelsPerSecond)
                                          .clamp(0.0, _pixelsPerSecond)
                                          .toDouble(),
                                      height: height,
                                      child: DecoratedBox(
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.white70,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                        child: CroppedPhotoView(
                                          photo: photo,
                                          fit: BoxFit.fill,
                                          filterQuality: FilterQuality.low,
                                          cacheWidth: 240,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }

                          return Positioned(
                            left: left + (_photoReordering ? _reorderDragDx : 0),
                            top: 0,
                            width: clipW + handleW * 2,
                            height: _thumbH,
                            child: _SelectedPhotoClip(
                              // Stable across index changes so long-press isn't cancelled.
                              key: ValueKey('sel-photo-${photo.id}'),
                              height: _thumbH,
                              durationSec: photo.durationSec,
                              pixelsPerSecond: _pixelsPerSecond,
                              thumbBuilder: (w, h) =>
                                  thumbRow(width: w, height: h),
                              onScrollTimeline: _scrollTimelineByDx,
                              onDragStart: () {
                                if (!_photoDurationDragging) {
                                  setState(() => _photoDurationDragging = true);
                                }
                              },
                              onLiveDuration: (sec) {
                                setState(() => _livePhotoDurationSec = sec);
                              },
                              onDragEnd: () {
                                setState(() {
                                  _photoDurationDragging = false;
                                  _livePhotoDurationSec = null;
                                });
                              },
                              onCommitDuration: (sec) {
                                project.changePhotoDuration(sel, sec);
                              },
                              onReorderStart: () {
                                setState(() {
                                  _photoReordering = true;
                                  _reorderDragDx = 0;
                                  _photoDurationDragging = true;
                                });
                              },
                              onReorderDelta: (dx) {
                                _applyPhotoReorderDrag(
                                  project: project,
                                  selectedIndex: sel,
                                  deltaDx: dx,
                                );
                              },
                              onReorderEnd: () {
                                setState(() {
                                  _photoReordering = false;
                                  _reorderDragDx = 0;
                                  _photoDurationDragging = false;
                                });
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (project.selectedPhotoIndex == null)
                // + stays on top; clips slide underneath while playing.
                Positioned(
                  left: _stripPadLeft,
                  top: top,
                  height: _thumbH,
                  child: GestureDetector(
                    onTap: () {
                      final at = _photoIndexAtPlayhead(project);
                      context.push('/gallery?insert=1&at=$at');
                    },
                    child: Container(
                      width: _plusW,
                      height: _thumbH,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              // --- Music / Effect lanes ---
              // Tools open: active interactive timeline always in the same bottom slot.
              // Done: thin lines — effect on top, music below.
              if (toolsOpen) ...[
                if (_musicToolsOpen) ...[
                  if (hasEffect)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: otherLineTop,
                      height: _collapsedLineSlotH,
                      child: _EffectCollapsedLine(
                        project: project,
                        stripController: _stripController,
                        leftPad: leftPad,
                        pixelsPerSecond: _pixelsPerSecond,
                      ),
                    ),
                  if (hasMusic)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: bottomSlotTop,
                      height: _musicTrackHeight,
                      child: _MusicTimelineLane(
                        project: project,
                        stripController: _stripController,
                        leftPad: leftPad,
                        pixelsPerSecond: _pixelsPerSecond,
                        selected: _musicTrackSelected,
                        onSelect: () {
                          setState(() {
                            _musicToolsOpen = true;
                            _musicTrackSelected = true;
                            _musicVolumeOpen = false;
                            _effectsTrackSelected = false;
                            project.clearTimelinePhotoSelection();
                          });
                        },
                        onScrollTimeline: _scrollTimelineByDx,
                      ),
                    ),
                ] else if (_effectsToolsOpen) ...[
                  if (hasMusic)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: otherLineTop,
                      height: _collapsedLineSlotH,
                      child: _MusicCollapsedLine(
                        project: project,
                        stripController: _stripController,
                        leftPad: leftPad,
                        pixelsPerSecond: _pixelsPerSecond,
                      ),
                    ),
                  if (hasEffect)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: bottomSlotTop,
                      height: _musicTrackHeight,
                      child: _EffectTimelineLane(
                        project: project,
                        stripController: _stripController,
                        leftPad: leftPad,
                        pixelsPerSecond: _pixelsPerSecond,
                        selected: _effectsTrackSelected,
                        onSelect: () {
                          setState(() {
                            _effectsToolsOpen = true;
                            _effectsTrackSelected = true;
                            _musicTrackSelected = false;
                            _musicToolsOpen = false;
                            project.clearTimelinePhotoSelection();
                          });
                        },
                        onScrollTimeline: _scrollTimelineByDx,
                      ),
                    ),
                ],
              ] else ...[
                if (hasEffect)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: hasMusic ? otherLineTop : bottomSlotTop,
                    height: hasMusic ? _collapsedLineSlotH : _musicTrackHeight,
                    child: _EffectCollapsedLine(
                      project: project,
                      stripController: _stripController,
                      leftPad: leftPad,
                      pixelsPerSecond: _pixelsPerSecond,
                    ),
                  ),
                if (hasMusic)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: bottomSlotTop,
                    height: hasEffect ? _collapsedLineSlotH : _musicTrackHeight,
                    child: _MusicCollapsedLine(
                      project: project,
                      stripController: _stripController,
                      leftPad: leftPad,
                      pixelsPerSecond: _pixelsPerSecond,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _editorToolbar() {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final t in EditorTool.values)
            if (!_toolsHiddenThisRelease.contains(t))
              EditorToolIcon(
                assetPath: _toolAsset(t),
                icon: _toolIcon(t),
                label: _toolLabel(t),
                selected: _tool == t,
                onTap: () {
                  if (_tool == t) {
                    _dismissTool();
                    return;
                  }
                  if (t == EditorTool.music) {
                    final p = context.read<SlideshowProject>();
                    p.stopPreviewPlayback();
                    if (p.music != null) {
                      // Reopen music tools + interactive timeline.
                      setState(() {
                        _tool = null;
                        _musicToolsOpen = true;
                        _musicVolumeOpen = false;
                        _musicEditOpen = false;
                        _musicTrackSelected = false;
                        _effectsToolsOpen = false;
                        _textToolsOpen = false;
                      });
                      return;
                    }
                  }
                  if (t == EditorTool.effects) {
                    final p = context.read<SlideshowProject>();
                    // Stop playback first — opening Effects during play caused ANR.
                    p.stopPreviewPlayback();
                    if (p.isEffectOverlayEnabled &&
                        p.selectedOverlayEffect != null) {
                      setState(() {
                        _tool = null;
                        _effectsToolsOpen = true;
                        _effectsTrackSelected = true;
                        _musicToolsOpen = false;
                        _textToolsOpen = false;
                      });
                      return;
                    }
                  }
                  if (t == EditorTool.text) {
                    _openTextTools();
                    return;
                  }
                  setState(() {
                    _tool = t;
                    _textToolsOpen = false;
                    if (t == EditorTool.ratio) {
                      _canvasSheetTab = _CanvasSheetTab.ratio;
                    } else if (t == EditorTool.bg) {
                      _canvasSheetTab = _CanvasSheetTab.background;
                    }
                    if (t == EditorTool.effects) {
                      _musicToolsOpen = false;
                    }
                    if (t == EditorTool.music) {
                      _effectsToolsOpen = false;
                    }
                  });
                  if (t == EditorTool.slide) {
                    final p = context.read<SlideshowProject>();
                    if (!p.isPreviewReady && !p.isPreparingPreview) {
                      p.preparePreviewFrames();
                    }
                  }
                },
              ),
        ],
      ),
    );
  }

  Widget _musicEditorToolbar(SlideshowProject project) {
    final active = _musicTrackSelected;
    final actions =
        <({String id, String label, String? asset, IconData? icon})>[
          (id: 'add', label: 'Add', asset: 'add_music.png', icon: null),
          (id: 'replace', label: 'Replace', asset: 'replace.png', icon: null),
          (id: 'edit', label: 'Edit', asset: 'edit.png', icon: null),
          (id: 'volume', label: 'Volume', asset: 'volume.png', icon: null),
          (
            id: 'beatsync',
            label: 'Beat-sync',
            asset: null,
            icon: Icons.graphic_eq,
          ),
          // Last index — remove selected music (None).
          (id: 'delete', label: 'Delete', asset: 'delete.png', icon: null),
        ];
    final color = active ? AppColors.textDark : AppColors.textMuted;
    return Container(
      height: _photoToolbarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 54, right: 6),
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i == 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: VerticalDivider(
                        width: 12,
                        thickness: 1,
                        color: AppColors.border.withValues(
                          alpha: active ? 1 : 0.5,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 72,
                    child: InkWell(
                      onTap: () => _handleMusicToolTap(project, actions[i].id),
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        opacity: active || actions[i].id == 'add' ? 1 : 0.45,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (actions[i].asset != null)
                              Image.asset(
                                'assets/images/editor/music_tools/${actions[i].asset}',
                                width: 28,
                                height: 28,
                                color: color,
                                colorBlendMode: BlendMode.srcIn,
                              )
                            else
                              Icon(actions[i].icon, size: 26, color: color),
                            const SizedBox(height: 4),
                            Text(
                              actions[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            bottom: 10,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 38,
                child: IconButton(
                  tooltip: 'Back to editor tools',
                  onPressed: _closeMusicTools,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _musicVolumeSheet(SlideshowProject project) {
    final music = project.music;
    final volume = (music?.volume ?? 100).toDouble();
    return Container(
      height: _photoToolbarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _musicVolumeOpen = false),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const Icon(Icons.volume_up_outlined, color: AppColors.textMuted),
          Expanded(
            child: Slider(
              value: volume,
              min: 0,
              max: 100,
              divisions: 20,
              activeColor: AppColors.primary,
              onChanged: music == null
                  ? null
                  : (v) => project.setMusicVolume(v.round()),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${volume.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _effectsEditorToolbar(SlideshowProject project) {
    final active = _effectsTrackSelected;
    final actions = <({String id, String label, IconData icon})>[
      (id: 'add', label: 'Add', icon: Icons.auto_awesome),
      (id: 'delete', label: 'Delete', icon: Icons.delete_outline_rounded),
      (
        id: 'clip_start',
        label: 'Clip start',
        icon: Icons.keyboard_double_arrow_left_rounded,
      ),
      (
        id: 'clip_end',
        label: 'Clip end',
        icon: Icons.keyboard_double_arrow_right_rounded,
      ),
    ];
    final color = active ? AppColors.textDark : AppColors.textMuted;
    return Container(
      height: _photoToolbarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 54, right: 6),
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i == 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: VerticalDivider(
                        width: 12,
                        thickness: 1,
                        color: AppColors.border.withValues(
                          alpha: active ? 1 : 0.5,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 76,
                    child: InkWell(
                      onTap: () =>
                          _handleEffectsToolTap(project, actions[i].id),
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        opacity: active || actions[i].id == 'add' ? 1 : 0.45,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(actions[i].icon, size: 26, color: color),
                            const SizedBox(height: 4),
                            Text(
                              actions[i].label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            bottom: 10,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 38,
                child: IconButton(
                  tooltip: 'Back to editor tools',
                  onPressed: _closeEffectsTools,
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleEffectsToolTap(SlideshowProject project, String id) {
    if (!_effectsTrackSelected && id != 'add') return;
    switch (id) {
      case 'add':
        setState(() {
          _tool = EditorTool.effects;
          _effectsToolsOpen = false;
        });
        return;
      case 'delete':
        project.clearOverlayEffect();
        setState(() {
          _effectsTrackSelected = false;
        });
        return;
      case 'clip_start':
        {
          // Nudge start earlier (left) a little — not full fill.
          const step = 0.5;
          final end =
              project.overlayTimelineEndSec ?? project.estimatedDurationSec;
          final start = (project.overlayTimelineStartSec - step).clamp(
            0.0,
            end - 0.5,
          );
          if (start < project.overlayTimelineStartSec - 0.001) {
            project.commitOverlayTimelineRange(start, end);
          }
          return;
        }
      case 'clip_end':
        {
          // Nudge end later (right) a little — not full fill.
          const step = 0.5;
          final videoEnd = project.estimatedDurationSec;
          final start = project.overlayTimelineStartSec;
          final curEnd = project.overlayTimelineEndSec ?? videoEnd;
          final end = (curEnd + step).clamp(start + 0.5, videoEnd);
          if (end > curEnd + 0.001) {
            project.commitOverlayTimelineRange(start, end);
          }
          return;
        }
    }
  }

  void _handleMusicToolTap(SlideshowProject project, String id) {
    // Only Add works while the music track is unselected.
    if (!_musicTrackSelected && id != 'add') return;
    switch (id) {
      case 'add':
      case 'replace':
        setState(() {
          _musicVolumeOpen = false;
          _musicEditOpen = false;
          _tool = EditorTool.music;
        });
        return;
      case 'volume':
        setState(() {
          _musicEditOpen = false;
          _musicVolumeOpen = true;
        });
        return;
      case 'edit':
        setState(() {
          _musicVolumeOpen = false;
          _musicEditOpen = true;
        });
        return;
      case 'delete':
        project.setMusic(null);
        setState(() {
          _musicTrackSelected = false;
          _musicVolumeOpen = false;
          _musicEditOpen = false;
        });
        return;
      case 'beatsync':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Beat-sync coming soon')));
    }
  }

  Widget _photoEditorToolbar(SlideshowProject project) {
    const actions = [
      (tool: _PhotoTool.duration, label: 'Duration', iconAsset: 'duration.png'),
      (
        tool: _PhotoTool.animation,
        label: 'Animation',
        iconAsset: 'animation.png',
      ),
      (tool: _PhotoTool.delete, label: 'Delete', iconAsset: 'delete.png'),
      (tool: _PhotoTool.background, label: 'Background', iconAsset: 'bg.png'),
      (tool: _PhotoTool.crop, label: 'Crop', iconAsset: 'crop.png'),
      (tool: _PhotoTool.mirror, label: 'Mirror', iconAsset: 'mirror.png'),
      (tool: _PhotoTool.flip, label: 'Flip', iconAsset: 'flip.png'),
      (tool: _PhotoTool.rotate, label: 'Rotate', iconAsset: 'rotate.png'),
      (tool: _PhotoTool.replace, label: 'Replace', iconAsset: 'replace.png'),
    ];
    return Container(
      height: _photoToolbarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 54, right: 6),
              children: [
                for (final action in actions)
                  SizedBox(
                    width: 72,
                    child: InkWell(
                      onTap: () => _handlePhotoToolTap(project, action.tool),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: action.iconAsset == 'animation.png' ? 4 : 0,
                          ),
                          Image.asset(
                            'assets/images/editor/photo_tools/${action.iconAsset}',
                            width: 28,
                            height: action.iconAsset == 'animation.png'
                                ? 23
                                : 28,
                            color: AppColors.iconNormal,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                          SizedBox(
                            height: action.iconAsset == 'animation.png' ? 6 : 4,
                          ),
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            bottom: 10,
            child: Material(
              color: AppColors.surfaceAlt,
              elevation: 3,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 38,
                child: IconButton(
                  tooltip: 'Back to editor tools',
                  onPressed: () {
                    setState(() {
                      _photoTool = null;
                      _tool = null;
                    });
                    project.clearTimelinePhotoSelection();
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePhotoToolTap(
    SlideshowProject project,
    _PhotoTool tool,
  ) async {
    final index = project.selectedPhotoIndex;
    if (index == null || index >= project.photos.length) return;
    final photo = project.photos[index];

    if (tool == _PhotoTool.delete) {
      project.removePhoto(index);
      setState(() => _photoTool = null);
      return;
    }
    if (tool == _PhotoTool.mirror) {
      project.updatePhoto(index, photo.copyWith(mirrored: !photo.mirrored));
      return;
    }
    if (tool == _PhotoTool.flip) {
      project.updatePhoto(index, photo.copyWith(flipped: !photo.flipped));
      return;
    }
    if (tool == _PhotoTool.rotate) {
      project.updatePhoto(
        index,
        photo.copyWith(
          rotationQuarterTurns: (photo.rotationQuarterTurns + 1) % 4,
        ),
      );
      return;
    }
    if (tool == _PhotoTool.replace) {
      await _replaceSelectedPhoto(project, index, photo);
      return;
    }
    if (tool == _PhotoTool.crop) {
      context.push('/crop');
      return;
    }

    setState(() {
      _photoTool = tool;
      if (tool == _PhotoTool.animation) {
        _animationPhase = _AnimationPhase.inAnimation;
      }
    });
  }

  Future<void> _replaceSelectedPhoto(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final temp = await getTemporaryDirectory();
    final extension = p.extension(picked.name).isEmpty
        ? '.jpg'
        : p.extension(picked.name);
    final output = File(
      p.join(
        temp.path,
        'replacement_${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    if (picked.path != null) {
      await File(picked.path!).copy(output.path);
    } else if (picked.bytes != null) {
      await output.writeAsBytes(picked.bytes!, flush: true);
    } else {
      return;
    }
    project.updatePhoto(index, photo.copyWith(path: output.path));
  }

  Widget _photoEditSheet(
    SlideshowProject project, {
    double? heightOverride,
    bool compactContent = false,
  }) {
    final index = project.selectedPhotoIndex;
    if (index == null || index >= project.photos.length) {
      return const SizedBox.shrink();
    }
    final photo = project.photos[index];
    final tool = _photoTool!;
    final height = heightOverride ?? _sheetHeight;
    return SectionSheet(
      title: _photoToolLabel(tool),
      height: height,
      compactHeader: compactContent,
      showTopDivider: !compactContent,
      center: tool == _PhotoTool.background
          ? _canvasTabHeader(compact: compactContent)
          : null,
      beforeConfirm:
          tool == _PhotoTool.background &&
              _canvasSheetTab == _CanvasSheetTab.background
          ? IconButton(
              onPressed: () {
                project.applyBackgroundToAll(index);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Background applied to all images'),
                      duration: Duration(seconds: 2),
                    ),
                  );
              },
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: compactContent
                  ? const BoxConstraints(minWidth: 32, minHeight: 20)
                  : null,
              icon: const _ApplyAllIcon(),
            )
          : null,
      onClose: () => setState(() => _photoTool = null),
      onConfirm: () {
        if (tool == _PhotoTool.background &&
            _canvasSheetTab == _CanvasSheetTab.ratio) {
          project.setAspect(project.aspectRatio);
        }
        setState(() => _photoTool = null);
      },
      child: switch (tool) {
        _PhotoTool.duration => _photoDurationPanel(
          project,
          index,
          photo,
          compact: compactContent,
        ),
        _PhotoTool.animation => _photoAnimationPanel(
          project,
          index,
          photo,
          compact: compactContent,
        ),
        _PhotoTool.background => _photoBackgroundPanel(
          project,
          index,
          photo,
          compact: compactContent,
        ),
        _PhotoTool.crop => _photoCropPanel(project, index, photo),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _editorCanvasSheet(
    SlideshowProject project, {
    required double height,
  }) {
    final photo = project.photos.isEmpty ? null : project.photos.first;
    return SectionSheet(
      title: 'Background',
      height: height,
      compactHeader: true,
      showTopDivider: false,
      center: _canvasTabHeader(compact: true),
      beforeConfirm:
          _canvasSheetTab == _CanvasSheetTab.background && photo != null
          ? IconButton(
              onPressed: () {
                project.applyBackgroundToAll(0);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('Background applied to all images'),
                      duration: Duration(seconds: 2),
                    ),
                  );
              },
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 20),
              icon: const _ApplyAllIcon(),
            )
          : null,
      onClose: _dismissTool,
      onConfirm: () {
        if (_canvasSheetTab == _CanvasSheetTab.ratio) {
          project.setAspect(project.aspectRatio);
        }
        _dismissTool();
      },
      child: _canvasSheetTab == _CanvasSheetTab.ratio
          ? _canvasRatioRow(project)
          : _canvasBackgroundBody(
              project,
              0,
              photo,
              compact: true,
              applyToAll: true,
            ),
    );
  }

  Widget _photoDurationPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo, {
    bool compact = false,
  }) {
    final duration = _durationSliderValue ?? photo.durationSec;
    return Padding(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 20)
          : const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current Screen Duration',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${duration.toStringAsFixed(1)}s',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            min: 1,
            max: 10,
            divisions: 18,
            value: duration.clamp(1.0, 10.0).toDouble(),
            onChanged: (value) => setState(() => _durationSliderValue = value),
            onChangeEnd: (value) {
              project.changePhotoDuration(index, value);
              setState(() => _durationSliderValue = null);
            },
          ),
        ],
      ),
    );
  }

  Widget _photoAnimationPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo, {
    bool compact = false,
  }) {
    final selected = switch (_animationPhase) {
      _AnimationPhase.inAnimation => photo.animationIn,
      _AnimationPhase.outAnimation => photo.animationOut,
    };
    const inOptions = <PhotoAnimationType>[
      PhotoAnimationType.none,
      PhotoAnimationType.fade,
      PhotoAnimationType.slightZoom,
      PhotoAnimationType.zoomIn,
      PhotoAnimationType.shake,
      PhotoAnimationType.shake2,
      PhotoAnimationType.mirror,
      PhotoAnimationType.slideUp,
      PhotoAnimationType.slideRight,
      PhotoAnimationType.slideDown,
      PhotoAnimationType.slideLeft,
      PhotoAnimationType.dynamicZoom,
      PhotoAnimationType.wiper,
      PhotoAnimationType.pendulum,
      PhotoAnimationType.upAndDown,
      PhotoAnimationType.leftAndRight,
      PhotoAnimationType.spinRight,
      PhotoAnimationType.spinLeft,
      PhotoAnimationType.spinUpper,
    ];
    final options = _animationPhase == _AnimationPhase.inAnimation
        ? inOptions
        : const <PhotoAnimationType>[
            PhotoAnimationType.none,
            PhotoAnimationType.fade,
            PhotoAnimationType.zoomOut,
            PhotoAnimationType.mirrorOutside,
            PhotoAnimationType.bottomOut,
            PhotoAnimationType.leftOut,
            PhotoAnimationType.rightOut,
            PhotoAnimationType.topOut,
            PhotoAnimationType.dynamicZoomOut,
            PhotoAnimationType.flipLeft,
            PhotoAnimationType.flipLower,
            PhotoAnimationType.flipRight,
            PhotoAnimationType.slideOutTop,
            PhotoAnimationType.slideOutBottom,
            PhotoAnimationType.rotateFade,
            PhotoAnimationType.flyOutLeft,
            PhotoAnimationType.flyOutRight,
            PhotoAnimationType.flyOutUp,
          ];
    final thumb = compact ? 56.0 : 56.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
          child: Row(
            children: [
              for (final phase in _AnimationPhase.values)
                InkWell(
                  onTap: () => setState(() {
                    _animationPhase = phase;
                    _inDurationDrag = null;
                    _outDurationDrag = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Text(
                          switch (phase) {
                            _AnimationPhase.inAnimation => 'In',
                            _AnimationPhase.outAnimation => 'Out',
                          },
                          style: TextStyle(
                            fontSize: compact ? 13 : 15,
                            color: _animationPhase == phase
                                ? AppColors.textDark
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        Container(
                          width: 18,
                          height: 2,
                          color: _animationPhase == phase
                              ? AppColors.textDark
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4.4),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(0, 0, 12, 2),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 0),
            itemBuilder: (context, i) {
              final animation = options[i];
              final isSelected = selected == animation;
              return InkWell(
                onTap: () {
                  final updated = switch (_animationPhase) {
                    _AnimationPhase.inAnimation => photo.copyWith(
                      animationIn: animation,
                    ),
                    _AnimationPhase.outAnimation => photo.copyWith(
                      animationOut: animation,
                    ),
                  };
                  project.updatePhoto(index, updated);
                  final clearing = animation == PhotoAnimationType.none;
                  if (!clearing) project.startLiveClip();
                  setState(() {
                    _liveToken++;
                    _liveMode = clearing
                        ? _LiveMode.idle
                        : _animationPhase == _AnimationPhase.inAnimation
                        ? _LiveMode.inPhase
                        : _LiveMode.outPhase;
                  });
                },
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      Container(
                        width: thumb,
                        height: thumb,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: animation == PhotoAnimationType.none
                            ? const ColoredBox(
                                color: Color(0xFFF2F2F2),
                                child: Center(
                                  child: Icon(
                                    Icons.block,
                                    color: Color(0xFF9E9E9E),
                                    size: 28,
                                  ),
                                ),
                              )
                            : _MotionThumb(
                                type: animation,
                                phase: _animationPhase,
                              ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _animationLabel(animation, _animationPhase),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _animationDurationBar(project, index, photo),
      ],
    );
  }

  Widget _animationDurationBar(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo,
  ) {
    final max = photo.durationSec < 0.1 ? 0.1 : photo.durationSec;
    final hasIn = photo.animationIn != PhotoAnimationType.none;
    final hasOut = photo.animationOut != PhotoAnimationType.none;
    var inSec = _inDurationDrag ?? photo.animationInDurationSec;
    var outSec = _outDurationDrag ?? photo.animationOutDurationSec;
    if (hasIn) {
      inSec = inSec.clamp(0.1, max).toDouble();
    } else {
      inSec = 0;
    }
    if (hasOut) {
      outSec = outSec.clamp(0.1, max).toDouble();
    } else {
      outSec = 0;
    }
    if (hasIn && hasOut && inSec + outSec > max) {
      outSec = (max - inSec).clamp(0.1, max).toDouble();
      if (inSec + outSec > max) {
        inSec = (max - outSec).clamp(0.1, max).toDouble();
      }
    }
    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textDark,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          const SizedBox(width: 24, child: Text('In', style: labelStyle)),
          Expanded(
            child: _InOutDurationBar(
              maxSec: max,
              inSec: inSec,
              outSec: outSec,
              inEnabled: hasIn,
              outEnabled: hasOut,
              onChanged: (nextIn, nextOut) {
                setState(() {
                  _inDurationDrag = nextIn;
                  _outDurationDrag = nextOut;
                });
              },
              onChangeEnd: (nextIn, nextOut) {
                setState(() {
                  _inDurationDrag = null;
                  _outDurationDrag = null;
                });
                project.updatePhoto(
                  index,
                  photo.copyWith(
                    animationInDurationSec: hasIn
                        ? nextIn
                        : photo.animationInDurationSec,
                    animationOutDurationSec: hasOut
                        ? nextOut
                        : photo.animationOutDurationSec,
                  ),
                );
              },
            ),
          ),
          const SizedBox(
            width: 28,
            child: Text('Out', textAlign: TextAlign.right, style: labelStyle),
          ),
        ],
      ),
    );
  }

  static const _canvasColors = <int>[
    0xFFFFFFFF,
    0xFFE0E0E0,
    0xFFBDBDBD,
    0xFF9E9E9E,
    0xFF757575,
    0xFF616161,
    0xFF424242,
    0xFF212121,
    0xFF000000,
    0xFFFFCDD2,
    0xFFF8BBD0,
    0xFFF48FB1,
    0xFFEC407A,
    0xFFE91E63,
    0xFFC2185B,
    0xFFF44336,
    0xFFE53935,
    0xFFD32F2F,
    0xFFC62828,
    0xFFB71C1C,
    0xFFFFF8E1,
    0xFFFFF59D,
    0xFFFFEE58,
    0xFFFFC107,
    0xFFFF9800,
    0xFFFF5722,
    0xFFE65100,
    0xFFE1BEE7,
    0xFFCE93D8,
    0xFFBA68C8,
    0xFFAB47BC,
    0xFF8E24AA,
    0xFF6A1B9A,
    0xFF4A148C,
    0xFFE3F2FD,
    0xFFBBDEFB,
    0xFF90CAF9,
    0xFF64B5F6,
    0xFF42A5F5,
    0xFF1E88E5,
    0xFF1565C0,
    0xFF0D47A1,
    0xFFE0F7FA,
    0xFF80DEEA,
    0xFF4DD0E1,
    0xFF00BCD4,
    0xFF0097A7,
    0xFF006064,
    0xFFF1F8E9,
    0xFFDCEDC8,
    0xFFC5E1A5,
    0xFFAED581,
    0xFF8BC34A,
    0xFF689F38,
    0xFF33691E,
    0xFF1B5E20,
    0xFFF9FBE7,
    0xFFF0F4C3,
    0xFFE6EE9C,
    0xFFDCE775,
    0xFFD4E157,
    0xFFC0CA33,
    0xFFEFEBE9,
    0xFFD7CCC8,
    0xFFBCAAA4,
    0xFFA1887F,
    0xFF8D6E63,
    0xFF6D4C41,
    0xFF4E342E,
    0xFF3E2723,
  ];

  static const _blurSigmas = <double>[0, 1.2, 2.4, 4, 6.5];

  Widget _canvasTabHeader({required bool compact}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tab in _CanvasSheetTab.values)
          InkWell(
            onTap: () => setState(() {
              _canvasSheetTab = tab;
              final photoSelected =
                  context.read<SlideshowProject>().selectedPhotoIndex != null;
              if (!photoSelected &&
                  (_tool == EditorTool.ratio || _tool == EditorTool.bg)) {
                _tool = tab == _CanvasSheetTab.ratio
                    ? EditorTool.ratio
                    : EditorTool.bg;
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab == _CanvasSheetTab.ratio ? 'Ratio' : 'Background',
                    style: TextStyle(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: _canvasSheetTab == tab
                          ? AppColors.textDark
                          : AppColors.textMuted,
                    ),
                  ),
                  Container(
                    width: tab == _CanvasSheetTab.ratio ? 28 : 72,
                    height: 2,
                    color: _canvasSheetTab == tab
                        ? AppColors.textDark
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _photoBackgroundPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo, {
    bool compact = false,
  }) {
    return _canvasSheetTab == _CanvasSheetTab.ratio
        ? _canvasRatioRow(project)
        : _canvasBackgroundBody(project, index, photo, compact: compact);
  }

  Widget _canvasRatioRow(SlideshowProject project) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: AspectPreset.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final preset = AspectPreset.values[i];
        final selected = project.aspectRatio == preset;
        return GestureDetector(
          onTap: () => project.setAspect(preset),
          child: SizedBox(
            width: 64,
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F3F3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFE0E0E0),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: _ratioGlyph(preset.ratio),
                ),
                const SizedBox(height: 4),
                Text(
                  preset.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primaryDark
                        : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ratioGlyph(double ratio) {
    const box = 28.0;
    final width = ratio >= 1 ? box : box * ratio;
    final height = ratio >= 1 ? box / ratio : box;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF9E9E9E), width: 1.4),
      ),
    );
  }

  Widget _canvasBackgroundBody(
    SlideshowProject project,
    int index,
    SlideshowPhoto? photo, {
    required bool compact,
    bool applyToAll = false,
  }) {
    final labelStyle = TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textDark,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text('Blur', style: labelStyle),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: compact ? 48 : 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var level = 0; level < _blurSigmas.length; level++) ...[
                if (level > 0) const SizedBox(width: 10),
                _blurChoice(
                  sigma: _blurSigmas[level],
                  selected: photo?.backgroundBlurLevel == level,
                  onTap: () {
                    if (applyToAll) {
                      project.setAllPhotoBackgrounds(blurLevel: level);
                    } else if (photo != null) {
                      project.updatePhoto(
                        index,
                        photo.copyWith(backgroundBlurLevel: level),
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text('Color', style: labelStyle),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: compact ? 35 : 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _canvasColors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, i) {
              final color = _canvasColors[i];
              final selected =
                  photo != null &&
                  photo.backgroundBlurLevel == null &&
                  photo.backgroundArgb == color;
              return GestureDetector(
                onTap: () {
                  if (applyToAll) {
                    project.setAllPhotoBackgrounds(
                      color: color,
                      clearBlur: true,
                    );
                  } else if (photo != null) {
                    project.updatePhoto(
                      index,
                      photo.copyWith(
                        backgroundArgb: color,
                        clearBackgroundBlur: true,
                      ),
                    );
                  }
                },
                child: Container(
                  width: compact ? 34 : 32,
                  height: compact ? 28 : 32,
                  decoration: BoxDecoration(
                    color: Color(color),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFFBDBDBD),
                      width: selected ? 2 : 0.6,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _blurChoice({
    required double sigma,
    required bool selected,
    required VoidCallback onTap,
  }) {
    Widget image = Image.asset(
      'assets/images/editor/animation_thumb.png',
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
    if (sigma > 0.4) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: image,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFBDBDBD),
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(7), child: image),
      ),
    );
  }

  Widget _photoCropPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo,
  ) {
    const ratios = <({String label, double? ratio})>[
      (label: 'Free', ratio: null),
      (label: '1:1', ratio: 1),
      (label: '4:5', ratio: 4 / 5),
      (label: '9:16', ratio: 9 / 16),
      (label: '16:9', ratio: 16 / 9),
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      itemCount: ratios.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final option = ratios[i];
        final selected = photo.cropAspectRatio == option.ratio;
        return InkWell(
          onTap: () => project.updatePhoto(
            index,
            option.ratio == null
                ? photo.copyWith(clearCropAspectRatio: true)
                : photo.copyWith(cropAspectRatio: option.ratio),
          ),
          child: Container(
            width: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySoft : Colors.white,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(option.label, style: const TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  String _photoToolLabel(_PhotoTool tool) => switch (tool) {
    _PhotoTool.duration => 'Duration',
    _PhotoTool.animation => 'Animation',
    _PhotoTool.delete => 'Delete',
    _PhotoTool.background => 'Background',
    _PhotoTool.crop => 'Crop',
    _PhotoTool.mirror => 'Mirror',
    _PhotoTool.flip => 'Flip',
    _PhotoTool.rotate => 'Rotate',
    _PhotoTool.replace => 'Replace',
  };

  String _animationLabel(PhotoAnimationType animation, _AnimationPhase phase) =>
      switch (animation) {
        PhotoAnimationType.none => 'None',
        PhotoAnimationType.fade => switch (phase) {
          _AnimationPhase.inAnimation => 'Fade in',
          _AnimationPhase.outAnimation => 'Fade out',
        },
        PhotoAnimationType.slightZoom => switch (phase) {
          _AnimationPhase.inAnimation => 'Slight zoom',
          _ => 'Slight zoom',
        },
        PhotoAnimationType.zoomIn => 'Zoom in',
        PhotoAnimationType.zoomOut => 'Zoom out',
        PhotoAnimationType.shake => 'Shake 1',
        PhotoAnimationType.shake2 => 'Shake 2',
        PhotoAnimationType.mirror => switch (phase) {
          _AnimationPhase.inAnimation => 'Mirror',
          _ => 'Mirror',
        },
        PhotoAnimationType.slideUp => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide up',
          _ => 'Slide up',
        },
        PhotoAnimationType.slideRight => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide right',
          _ => 'Slide right',
        },
        PhotoAnimationType.slideDown => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide down',
          _ => 'Slide down',
        },
        PhotoAnimationType.slideLeft => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide left',
          _ => 'Slide left',
        },
        PhotoAnimationType.dynamicZoom => switch (phase) {
          _AnimationPhase.inAnimation => 'Dynamic zoom',
          _ => 'Dynamic zoom',
        },
        PhotoAnimationType.dynamicZoomAlt => 'Dynamic zoom',
        PhotoAnimationType.wiper => 'Wiper',
        PhotoAnimationType.pendulum => 'Pendulum',
        PhotoAnimationType.upAndDown => 'Up and down',
        PhotoAnimationType.leftAndRight => 'Left and right',
        PhotoAnimationType.spinRight => 'Spin right',
        PhotoAnimationType.spinLeft => 'Spin left',
        PhotoAnimationType.spinUpper => 'Spin upper',
        PhotoAnimationType.mirrorOutside => 'Mirror',
        PhotoAnimationType.bottomOut => 'Bottom out',
        PhotoAnimationType.leftOut => 'Left out',
        PhotoAnimationType.rightOut => 'Right out',
        PhotoAnimationType.topOut => 'Top out',
        PhotoAnimationType.dynamicZoomOut => 'Dynamic zoom',
        PhotoAnimationType.flipLeft => 'Flip left',
        PhotoAnimationType.flipLower => 'Flip lower',
        PhotoAnimationType.flipRight => 'Flip right',
        PhotoAnimationType.slideOutTop => 'Slide out top',
        PhotoAnimationType.slideOutBottom => 'Slide out bottom',
        PhotoAnimationType.rotateFade => 'Rotate fade',
        PhotoAnimationType.flyOutLeft => 'Fly out left',
        PhotoAnimationType.flyOutRight => 'Fly out right',
        PhotoAnimationType.flyOutUp => 'Fly out up',
      };

  @override
  Widget build(BuildContext context) {
    final project = context.watch<SlideshowProject>();
    final (ow, oh) = project.outputSize;
    final aspect = ow / oh;
    final photoToolReplacesTimeline =
        project.selectedPhotoIndex != null &&
        (_photoTool == _PhotoTool.duration ||
            _photoTool == _PhotoTool.animation ||
            _photoTool == _PhotoTool.background);
    final inlineSheetHeight = _sheetHeight - _timelineHeaderHeight;
    final replacedSheetExtra = photoToolReplacesTimeline
        ? _photoToolbarHeight
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      // Keep preview fixed; text sheet / keyboard overlay instead of resizing body.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Editor'),
        actions: [
          if (_textToolsOpen)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TealPillButton(label: 'Done', onPressed: _closeTextTools),
            )
          else if (project.selectedPhotoIndex != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TealPillButton(
                label: 'Done',
                onPressed: () {
                  setState(() {
                    _photoTool = null;
                    _tool = null;
                    _liveMode = _LiveMode.idle;
                  });
                  project.clearTimelinePhotoSelection();
                },
              ),
            )
          else if (_musicToolsOpen)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TealPillButton(label: 'Done', onPressed: _closeMusicTools),
            )
          else if (_effectsToolsOpen)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TealPillButton(
                label: 'Done',
                onPressed: _closeEffectsTools,
              ),
            )
          else if (_tool != EditorTool.frame &&
              _tool != EditorTool.music &&
              _tool != EditorTool.effects &&
              !_musicEditOpen)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TealPillButton(
                label: 'Export',
                enabled:
                    project.photos.length >= AppConstants.minPhotos &&
                    !project.isProcessing,
                onPressed: () => context.push('/export'),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          Expanded(
            child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                  child: Center(
              child: AspectRatio(
                      aspectRatio: aspect,
                child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black),
                  child: ClipRRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                          if (project.selectedPhotoIndex case final sel?
                              when sel >= 0 && sel < project.photos.length)
                            _LiveClipPreview(
                              key: ValueKey(sel),
                              photoIndex: sel,
                              photo: project.photos[sel],
                              backgroundArgb:
                                  project.photos[sel].backgroundArgb ??
                                  project.backgroundArgb,
                              backgroundBlurLevel:
                                  project.photos[sel].backgroundBlurLevel,
                              replayToken: _liveToken,
                              mode: _liveMode,
                              inSecOverride: _inDurationDrag,
                              outSecOverride: _outDurationDrag,
                              // Capture [sel] — selection can clear before
                              // the animation ticker fires onFraction again.
                              onFraction: (fraction) =>
                                  project.setLivePreviewClock(sel, fraction),
                              onFinished: () {
                                project.finishLiveClip();
                                if (mounted) {
                                  setState(() => _liveMode = _LiveMode.idle);
                                }
                              },
                            )
                        else
                            RepaintBoundary(
                              child:
                                  ValueListenableBuilder<
                                    ({int index, double fraction})?
                                  >(
                                    valueListenable: project.scrubLive,
                                    builder: (context, scrub, _) {
                                      if (scrub != null &&
                                          !project.isPreviewReady &&
                                          scrub.index < project.photos.length) {
                                        final photo =
                                            project.photos[scrub.index];
                                        return _LiveClipPreview(
                                          key: ValueKey('scrub-${scrub.index}'),
                                          photoIndex: scrub.index,
                                          photo: photo,
                                          backgroundArgb:
                                              photo.backgroundArgb ??
                                              project.backgroundArgb,
                                          backgroundBlurLevel:
                                              photo.backgroundBlurLevel,
                                          replayToken: 0,
                                          mode: _LiveMode.idle,
                                          holdFraction: scrub.fraction,
                                          onFraction: (_) {},
                                          onFinished: () {},
                                        );
                                      }
                                      return ValueListenableBuilder<Uint8List?>(
                                        valueListenable:
                                            project.previewFrameListenable,
                                        builder: (context, bytes, _) {
                                          if (bytes != null) {
                                            return Image.memory(
                                              bytes,
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                              filterQuality: FilterQuality.low,
                                            );
                                          }
                                          if (project.photos.isNotEmpty) {
                                            return Image.file(
                                              File(project.photos.first.path),
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                              filterQuality: FilterQuality.high,
                                            );
                                          }
                                          return const Center(
                            child: Text(
                              'No preview',
                                              style: TextStyle(
                                                color: Colors.white54,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                            ),
                          ),
                        if (project.selectedFrameAsset != null)
                            IgnorePointer(
                              child: Image.asset(
                            project.selectedFrameAsset!,
                                key: ValueKey(project.selectedFrameAsset),
                                fit: BoxFit.fill,
                                gaplessPlayback: false,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          // Live effect layer (CapCut-style) — no frame bake / no loading.
                          if (project.isEffectOverlayEnabled &&
                              project.selectedOverlayEffect != null)
                            _LiveEffectOverlayLayer(
                              key: ValueKey(project.selectedOverlayEffect!.id),
                              project: project,
                              effect: project.selectedOverlayEffect!,
                            ),
                          // Live text: tap to select/move; Edit opens sheet.
                          LiveTextOverlaysLayer(
                            project: project,
                            selectedOverlayId: _selectedTextOverlayId,
                            onSelectedOverlayId: (id) {
                              setState(() {
                                _selectedTextOverlayId = id;
                                if (id != null) {
                                  final o = project.overlays
                                      .where((e) => e.id == id)
                                      .firstOrNull;
                                  if (o?.text != null) {
                                    _textController.text = o!.text!;
                                  }
                                }
                              });
                            },
                            onEditOverlay: (id) {
                              final o = project.overlays
                                  .where((e) => e.id == id)
                                  .firstOrNull;
                              setState(() {
                                _selectedTextOverlayId = id;
                                _textController.text = o?.text ?? '';
                                _tool = null;
                                _musicToolsOpen = false;
                                _effectsToolsOpen = false;
                                _photoTool = null;
                                _textToolsOpen = true;
                              });
                              project.clearTimelinePhotoSelection();
                              project.stopPreviewPlayback();
                            },
                            editing: _textToolsOpen,
                          ),
                          // Loading while transition preview frames are prepared.
                          if (project.isPreparingPreview)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Preparing preview…',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Export-only progress.
                        if (project.isProcessing)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                      color: AppColors.primary,
                                    value: project.processProgress > 0
                                        ? project.processProgress
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                      'Exporting ${(project.processProgress * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),

          // Text sheet overlays — keep idle chrome underneath so preview size/position stays fixed.
          if (_textToolsOpen) ...[
            _idleToolPanel(project),
            _editorToolbar(),
          ] else if (photoToolReplacesTimeline) ...[
            _idleToolPanel(
              project,
              height:
                  _timelineHeaderHeight +
                  inlineSheetHeight +
                  replacedSheetExtra,
              timelineHeaderHeight: _timelineHeaderHeight,
              timelineContent: _photoEditSheet(
                project,
                heightOverride: inlineSheetHeight + replacedSheetExtra,
                compactContent: true,
              ),
            ),
          ] else if (_tool == EditorTool.ratio || _tool == EditorTool.bg) ...[
            _idleToolPanel(
              project,
              height:
                  _timelineHeaderHeight +
                  inlineSheetHeight +
                  _photoToolbarHeight,
              timelineHeaderHeight: _timelineHeaderHeight,
              timelineContent: _editorCanvasSheet(
                project,
                height: inlineSheetHeight + _photoToolbarHeight,
              ),
            ),
          ] else if (_tool == EditorTool.music) ...[
            // Fixed height = idle panel + toolbar slot (no extra music bump).
            Container(
              height: _sheetHeight + _photoToolbarHeight,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _timelineHeaderHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: _idlePreviewRow(project),
                    ),
                  ),
                  Expanded(
                    child: _MusicPickerSheet(
                      project: project,
                      onClose: _finishMusicPicker,
                      onConfirm: _finishMusicPicker,
                      onOpenLibrary: () => context.push('/music'),
                      onPickLocal: _pickLocalMusic,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_tool == EditorTool.effects) ...[
            Container(
              height: _sheetHeight + _photoToolbarHeight,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _timelineHeaderHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: _idlePreviewRow(project),
                    ),
                  ),
                  Expanded(
                    child: _EffectsPickerSheet(
                      project: project,
                      onClose: _finishEffectsPicker,
                      onConfirm: _finishEffectsPicker,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_musicToolsOpen && _musicEditOpen) ...[
            // Timeline strip hidden; same body height as idle (_sheetHeight).
            Container(
              height: _sheetHeight,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _timelineHeaderHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: _idlePreviewRow(project),
                    ),
                  ),
                  Expanded(
                    child: _MusicEditSheet(
                      project: project,
                      onClose: () => setState(() => _musicEditOpen = false),
                      onConfirm: () => setState(() => _musicEditOpen = false),
                    ),
                  ),
                ],
              ),
            ),
            _musicEditorToolbar(project),
          ] else ...[
            // One shared idle strip for normal editing + photo selection so the
            // ScrollController is not remounted onto a second ListView.
            if (_tool == null)
              _idleToolPanel(project)
            else
              SectionSheet(
                title: _toolLabel(_tool!),
                height: _sheetHeight,
                headerRow: SizedBox(
                  height: _timelineHeaderHeight,
                  child: _idlePreviewRow(project),
                ),
                onClose: _dismissTool,
                onConfirm: _dismissTool,
                child: _buildPanel(project),
              ),

            if (project.selectedPhotoIndex != null) ...[
              if (_photoTool == null)
                _photoEditorToolbar(project)
              else
                _photoEditSheet(project),
            ] else if (_musicToolsOpen)
              _musicVolumeOpen
                  ? _musicVolumeSheet(project)
                  : _musicEditorToolbar(project)
            else if (_effectsToolsOpen)
              _effectsEditorToolbar(project)
            else
              _editorToolbar(),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
          if (_textToolsOpen)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _textFocusNode,
                builder: (context, _) {
                  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
                  final safeBottom = MediaQuery.paddingOf(context).bottom;
                  final keyboardOpen =
                      keyboard > 0 || _textFocusNode.hasFocus;
                  final hasOverlay = _selectedTextOverlayId != null;
                  // Typing: input bar only (tabs hide under keyboard). Idle + overlay: full panel.
                  final bodyH = (hasOverlay && !keyboardOpen)
                      ? TextToolsSheet.sheetBodyHeight
                      : 64.0;
                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    // Lift sheet with keyboard; preview stays put (resizeToAvoidBottomInset: false).
                    padding: EdgeInsets.only(
                      bottom: keyboard > 0 ? keyboard : safeBottom,
                    ),
                    child: Material(
                      elevation: 12,
                      color: Colors.white,
                      clipBehavior: Clip.hardEdge,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        height: bodyH,
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: TextToolsSheet(
                          project: project,
                          controller: _textController,
                          focusNode: _textFocusNode,
                          selectedOverlayId: _selectedTextOverlayId,
                          onSelectedOverlayId: (id) =>
                              setState(() => _selectedTextOverlayId = id),
                          onClose: _closeTextTools,
                          onConfirm: () => setState(() {}),
                          compactKeyboardPhase: !hasOverlay || keyboardOpen,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _toolLabel(EditorTool t) => switch (t) {
    EditorTool.slide => 'Slide',
    EditorTool.text => 'Text',
    EditorTool.effects => 'Effects',
    EditorTool.starting => 'Starting',
    EditorTool.ending => 'Ending',
    EditorTool.music => 'Music',
    EditorTool.frame => 'Frame',
    EditorTool.filter => 'Filter',
    EditorTool.sticker => 'Sticker',
    EditorTool.ratio => 'Ratio',
    EditorTool.bg => 'BG',
  };

  String? _toolAsset(EditorTool t) => switch (t) {
    EditorTool.slide => 'assets/images/editor/slide.png',
    EditorTool.text => 'assets/images/editor/text.png',
    EditorTool.effects => 'assets/images/editor/effects.png',
    EditorTool.starting => 'assets/images/editor/starting.png',
    EditorTool.ending => 'assets/images/editor/ending.png',
    EditorTool.music => 'assets/images/editor/music.png',
    EditorTool.frame => 'assets/images/editor/frame.png',
    EditorTool.filter => 'assets/images/editor/filter.png',
    EditorTool.sticker => 'assets/images/editor/sticker.png',
    EditorTool.bg => 'assets/images/editor/bg.png',
    EditorTool.ratio => null,
  };

  IconData _toolIcon(EditorTool t) => switch (t) {
    EditorTool.slide => Icons.view_carousel_outlined,
    EditorTool.text => Icons.text_fields,
    EditorTool.effects => Icons.auto_awesome,
    EditorTool.starting => Icons.skip_previous_outlined,
    EditorTool.ending => Icons.skip_next_outlined,
    EditorTool.music => Icons.music_note_outlined,
    EditorTool.frame => Icons.crop_din_outlined,
    EditorTool.filter => Icons.filter_vintage_outlined,
    EditorTool.sticker => Icons.emoji_emotions_outlined,
    EditorTool.ratio => Icons.aspect_ratio,
    EditorTool.bg => Icons.format_color_fill_outlined,
  };

  Widget _buildPanel(SlideshowProject project) {
    return switch (_tool!) {
      EditorTool.slide => _SlideTransitions(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
      EditorTool.text => _TextPanel(
        controller: _textController,
        project: project,
        onApplied: () => project.refreshLivePreview(),
      ),
      EditorTool.effects => const SizedBox.shrink(),
      EditorTool.starting => _TitleCardPanel(
        label: 'Starting',
        card: project.startingCard,
        onChanged: (c) {
          project.setStartingCard(c);
          project.refreshLivePreview();
        },
        onClear: () => project.setStartingCard(null),
      ),
      EditorTool.ending => _TitleCardPanel(
        label: 'Ending',
        card: project.endingCard,
        onChanged: (c) {
          project.setEndingCard(c);
          project.refreshLivePreview();
        },
        onClear: () => project.setEndingCard(null),
      ),
      EditorTool.music => const SizedBox.shrink(),
      EditorTool.frame => _FramePanel(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
      EditorTool.filter => _FilterPanel(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
      EditorTool.sticker => _StickerPanel(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
      EditorTool.ratio => _RatioPanel(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
      EditorTool.bg => _BgPanel(
        project: project,
        onChanged: () => project.refreshLivePreview(),
      ),
    };
  }
}

/// Music Edit sheet — trim clip start/end + fade in/out (screenshot).
class _MusicEditSheet extends StatefulWidget {
  const _MusicEditSheet({
    required this.project,
    required this.onClose,
    required this.onConfirm,
  });

  final SlideshowProject project;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  State<_MusicEditSheet> createState() => _MusicEditSheetState();
}

class _MusicEditSheetState extends State<_MusicEditSheet> {
  static const _peach = ui.Color(0xFFD5D2CF);
  static const _waveHMax = 44.0;
  static const _minClip = 1.0;
  static const _handleHit = 28.0;
  static const _titleH = 34.0; // 10px tighter than before (pink gap)

  late double _clipStart;
  late double _clipEnd;
  late bool _fadeIn;
  late bool _fadeOut;
  late bool _hadCustomClipEnd;
  double _trackDur = 0;
  bool _loadingDur = true;

  @override
  void initState() {
    super.initState();
    final m = widget.project.music!;
    _clipStart = m.clipStartSec;
    _fadeIn = m.fadeIn;
    _fadeOut = m.fadeOut;
    _hadCustomClipEnd = m.clipEndSec != null;
    final known = m.duration?.inMilliseconds;
    if (known != null && known > 0) {
      _trackDur = known / 1000.0;
      _clipEnd = (m.clipEndSec ?? _trackDur).clamp(
        _clipStart + _minClip,
        _trackDur,
      );
      _loadingDur = false;
    } else {
      _clipEnd = m.clipEndSec ?? 0;
    }
    _loadDuration();
  }

  Future<void> _loadDuration() async {
    final m = widget.project.music;
    if (m == null) return;
    final player = AudioPlayer();
    try {
      final Duration? d = m.isAsset
          ? await player.setAsset(m.path)
          : await player.setFilePath(m.path);
      final resolved = d ?? player.duration;
      if (resolved != null && resolved.inMilliseconds > 0 && mounted) {
        setState(() {
          _trackDur = resolved.inMilliseconds / 1000.0;
          // No saved end → always full track (works for long songs too).
          if (!_hadCustomClipEnd) {
            _clipEnd = _trackDur;
          } else {
            _clipEnd = _clipEnd.clamp(_clipStart + _minClip, _trackDur);
          }
          _clipStart = _clipStart.clamp(
            0.0,
            math.max(0.0, _clipEnd - _minClip),
          );
          _loadingDur = false;
        });
        widget.project.setMusicClip(duration: resolved);
      } else if (mounted) {
        setState(() {
          if (_trackDur <= 0) _trackDur = 60;
          if (!_hadCustomClipEnd) _clipEnd = _trackDur;
          _loadingDur = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_trackDur <= 0) _trackDur = 60;
          if (!_hadCustomClipEnd) _clipEnd = _trackDur;
          _loadingDur = false;
        });
      }
    } finally {
      await player.dispose();
    }
  }

  String _fmt(double sec) {
    final s = sec.clamp(0, 35999).floor();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  void _commit() {
    widget.project.setMusicClip(
      clipStartSec: _clipStart,
      clipEndSec: _clipEnd,
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
      duration: Duration(milliseconds: (_trackDur * 1000).round()),
    );
    widget.onConfirm();
  }

  void _cancel() {
    widget.onClose();
  }

  double _secToX(double sec, double width) {
    if (_trackDur <= 0) return 0;
    return (sec / _trackDur) * width;
  }

  void _dragHandle({
    required bool isStart,
    required double dx,
    required double width,
  }) {
    if (width <= 0 || _trackDur <= 0) return;
    final dSec = (dx / width) * _trackDur;
    setState(() {
      if (isStart) {
        _clipStart = (_clipStart + dSec).clamp(0.0, _clipEnd - _minClip);
      } else {
        _clipEnd = (_clipEnd + dSec).clamp(_clipStart + _minClip, _trackDur);
      }
    });
  }

  Widget _fadeToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 24,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? const Color(0xFFE8F5F3) : const Color(0xFFE8E8E8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value ? AppColors.primary : const Color(0xFFD0D0D0),
              ),
            ),
            // ON = knob on the right (matches screenshot).
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: value ? AppColors.primary : const Color(0xFFBFBFBF),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cutHandle({
    required bool isStart,
    required double width,
    required double waveH,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) =>
          _dragHandle(isStart: isStart, dx: d.delta.dx, width: width),
      child: SizedBox(
        width: _handleHit,
        height: waveH,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 2, height: waveH, color: Colors.white),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF7DE8DE), Color(0xFF00BFA5)],
                ),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Waveform cut box — height fits parent (green box), no overflow.
  Widget _cutContainer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const timeH = 14.0;
        const gap = 2.0;
        final maxWave = constraints.hasBoundedHeight
            ? (constraints.maxHeight - timeH - gap).clamp(24.0, _waveHMax)
            : _waveHMax;
        final waveH = maxWave.toDouble();
        final startX = _secToX(_clipStart, w);
        final endX = _secToX(_clipEnd, w);
        const timeStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
          height: 1.0,
        );

        return SizedBox(
          width: w,
          height: timeH + gap + waveH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: timeH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (startX - 16).clamp(0.0, math.max(0.0, w - 36)),
                      child: Text(_fmt(_clipStart), style: timeStyle),
                    ),
                    Positioned(
                      left: (endX - 16).clamp(0.0, math.max(0.0, w - 36)),
                      child: Text(_fmt(_clipEnd), style: timeStyle),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              SizedBox(
                height: waveH,
                width: w,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _peach,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: CustomPaint(
                          painter: _EditWavePainter(
                            startSec: _clipStart,
                            endSec: _clipEnd,
                            totalSec: _trackDur,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: startX - _handleHit / 2,
                      top: 0,
                      bottom: 0,
                      child: _cutHandle(isStart: true, width: w, waveH: waveH),
                    ),
                    Positioned(
                      left: endX - _handleHit / 2,
                      top: 0,
                      bottom: 0,
                      child: _cutHandle(isStart: false, width: w, waveH: waveH),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.project.music;
    if (music == null) {
      return const SizedBox.shrink();
    }

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: _titleH,
            child: Row(
              children: [
                IconButton(
                  onPressed: _cancel,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                ),
                Expanded(child: SheetTitle(music.title)),
                IconButton(
                  onPressed: _commit,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Column(
                children: [
                  Expanded(
                    child: _loadingDur
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _cutContainer(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _fadeToggle(
                        label: 'Fade In',
                        value: _fadeIn,
                        onChanged: (v) => setState(() => _fadeIn = v),
                      ),
                      _fadeToggle(
                        label: 'Fade Out',
                        value: _fadeOut,
                        onChanged: (v) => setState(() => _fadeOut = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditWavePainter extends CustomPainter {
  _EditWavePainter({
    required this.startSec,
    required this.endSec,
    required this.totalSec,
  });

  final double startSec;
  final double endSec;
  final double totalSec;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSec <= 0 || size.width <= 0) return;
    final startX = (startSec / totalSec) * size.width;
    final endX = (endSec / totalSec) * size.width;
    final bars = math.max(40, (size.width / 4).floor());
    final inactive = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars; i++) {
      final t = bars == 1 ? 0.0 : i / (bars - 1);
      final x = t * size.width;
      final wave =
          math.sin(t * math.pi * 9.5) * 0.38 +
          math.sin(t * math.pi * 3.1 + 0.6) * 0.32 +
          math.sin(t * math.pi * 15 + 1.2) * 0.12 +
          0.48;
      final h = (8.0 + wave.clamp(0.2, 1.0) * (size.height - 16)).clamp(
        8.0,
        size.height - 6,
      );
      final y0 = (size.height - h) / 2;
      final y1 = (size.height + h) / 2;
      final active = x >= startX && x <= endX;
      if (active) {
        final paint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5CE1D6), Color(0xFF00BFA5)],
          ).createShader(Rect.fromLTWH(x - 1, y0, 3, h))
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x, y0), Offset(x, y1), paint);
      } else {
        canvas.drawLine(Offset(x, y0), Offset(x, y1), inactive);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EditWavePainter old) =>
      old.startSec != startSec ||
      old.endSec != endSec ||
      old.totalSec != totalSec;
}

/// Thin non-editable line spanning the music clip's timelineStart→timelineEnd.
class _MusicCollapsedLine extends StatefulWidget {
  const _MusicCollapsedLine({
    required this.project,
    required this.stripController,
    required this.leftPad,
    required this.pixelsPerSecond,
  });

  final SlideshowProject project;
  final ScrollController stripController;
  final double leftPad;
  final double pixelsPerSecond;

  @override
  State<_MusicCollapsedLine> createState() => _MusicCollapsedLineState();
}

class _MusicCollapsedLineState extends State<_MusicCollapsedLine> {
  @override
  void initState() {
    super.initState();
    widget.stripController.addListener(_onStrip);
    widget.project.addListener(_onProject);
  }

  @override
  void didUpdateWidget(covariant _MusicCollapsedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stripController != widget.stripController) {
      oldWidget.stripController.removeListener(_onStrip);
      widget.stripController.addListener(_onStrip);
    }
    if (oldWidget.project != widget.project) {
      oldWidget.project.removeListener(_onProject);
      widget.project.addListener(_onProject);
    }
  }

  @override
  void dispose() {
    widget.stripController.removeListener(_onStrip);
    widget.project.removeListener(_onProject);
    super.dispose();
  }

  void _onStrip() {
    if (mounted) setState(() {});
  }

  void _onProject() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.project.music;
    if (music == null) return const SizedBox.shrink();

    final offset = widget.stripController.hasClients
        ? widget.stripController.offset
        : 0.0;
    final videoDur = widget.project.estimatedDurationSec;
    final startSec = music.timelineStartSec.clamp(0.0, videoDur);
    final endSec = (music.timelineEndSec ?? videoDur).clamp(
      startSec + 0.05,
      videoDur,
    );
    final trackLeft = widget.leftPad - offset;
    final barLeft = trackLeft + startSec * widget.pixelsPerSecond;
    final barWidth = math.max(
      (endSec - startSec) * widget.pixelsPerSecond,
      2.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final lineH = _EditorScreenState._musicPlaceholderH;
        final lineTop = ((constraints.maxHeight - lineH) / 2).clamp(
          0.0,
          double.infinity,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: barLeft,
              width: barWidth,
              top: lineTop,
              height: lineH,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFB8C4F0),
                  borderRadius: BorderRadius.all(Radius.circular(1)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Selected photo clip: white shell + chevron trim handles + hold-drag reorder.
/// Painted in an overlay so left/right handles overlap neighboring clips.
/// Duration: drag `<` / `>` handles. Reorder: long-press body, drag left/right.
class _SelectedPhotoClip extends StatefulWidget {
  const _SelectedPhotoClip({
    super.key,
    required this.height,
    required this.durationSec,
    required this.pixelsPerSecond,
    required this.thumbBuilder,
    required this.onCommitDuration,
    required this.onLiveDuration,
    required this.onScrollTimeline,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onReorderStart,
    required this.onReorderDelta,
    required this.onReorderEnd,
  });

  static const handleW = 22.0;

  final double height;
  final double durationSec;
  final double pixelsPerSecond;
  final Widget Function(double width, double height) thumbBuilder;
  final ValueChanged<double> onCommitDuration;
  final ValueChanged<double> onLiveDuration;

  /// Pan the photo strip opposite to the finger (same as music lane).
  final ValueChanged<double> onScrollTimeline;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onReorderStart;
  final ValueChanged<double> onReorderDelta;
  final VoidCallback onReorderEnd;

  @override
  State<_SelectedPhotoClip> createState() => _SelectedPhotoClipState();
}

class _SelectedPhotoClipState extends State<_SelectedPhotoClip> {
  static const _minSec = 1.0;
  static const _maxSec = 10.0;
  static const _shellPadV = 3.0;

  double? _liveDuration;
  double _holdOriginDx = 0;
  bool _dragging = false;
  bool _reordering = false;

  double get _duration =>
      (_liveDuration ?? widget.durationSec).clamp(_minSec, _maxSec);

  void _beginDrag() {
    if (_dragging || _reordering) return;
    _dragging = true;
    _liveDuration = widget.durationSec;
    widget.onDragStart();
    widget.onLiveDuration(_liveDuration!);
  }

  void _applyDeltaSec(double deltaSec) {
    if (!_dragging || deltaSec.abs() < 0.0001) return;
    final next = (_liveDuration! + deltaSec).clamp(_minSec, _maxSec).toDouble();
    if ((next - _liveDuration!).abs() < 0.0001) return;
    setState(() => _liveDuration = next);
    widget.onLiveDuration(next);
  }

  void _endDrag() {
    if (!_dragging) return;
    final sec = _duration;
    _dragging = false;
    _liveDuration = null;
    widget.onCommitDuration(sec);
    widget.onDragEnd();
  }

  void _beginReorder() {
    if (_reordering || _dragging) return;
    _reordering = true;
    _holdOriginDx = 0;
    HapticFeedback.mediumImpact();
    widget.onReorderStart();
  }

  void _applyReorderDelta(double deltaDx) {
    if (!_reordering || deltaDx.abs() < 0.01) return;
    widget.onReorderDelta(deltaDx);
  }

  void _endReorder() {
    if (!_reordering) return;
    _reordering = false;
    _holdOriginDx = 0;
    widget.onReorderEnd();
  }

  Widget _handle({required bool isStart}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      // Lock ListView scroll before the drag arena resolves.
      onPointerDown: (_) => widget.onDragStart(),
      onPointerUp: (_) {
        if (!_dragging) widget.onDragEnd();
      },
      onPointerCancel: (_) {
        if (!_dragging) widget.onDragEnd();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) {
          HapticFeedback.selectionClick();
          _beginDrag();
        },
        onHorizontalDragUpdate: (d) {
          if (d.delta.dx == 0) return;
          // Left handle: drag left grows; right handle: drag right grows.
          final signedDx = isStart ? -d.delta.dx : d.delta.dx;
          _applyDeltaSec(signedDx / widget.pixelsPerSecond);
          // Finger left → strip pans right (music-lane style).
          widget.onScrollTimeline(-d.delta.dx);
        },
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          width: _SelectedPhotoClip.handleW,
          height: double.infinity,
          child: Icon(
            isStart ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            size: 20,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clipW = _duration * widget.pixelsPerSecond;
    final totalW = clipW + _SelectedPhotoClip.handleW * 2;
    final thumbH = widget.height - _shellPadV * 2;
    final showBadge = clipW >= 48;

    return SizedBox(
      width: totalW,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _shellPadV),
          child: Row(
            children: [
              _handle(isStart: true),
              SizedBox(
                width: clipW,
                height: thumbH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Long-press body → reorder left/right. Duration = handles only.
                  onLongPressStart: (_) => _beginReorder(),
                  onLongPressMoveUpdate: (d) {
                    final dx = d.localOffsetFromOrigin.dx;
                    final delta = dx - _holdOriginDx;
                    _holdOriginDx = dx;
                    _applyReorderDelta(delta);
                  },
                  onLongPressEnd: (_) => _endReorder(),
                  onLongPressCancel: _endReorder,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.thumbBuilder(clipW, thumbH),
                      if (showBadge)
                        Positioned(
                          left: 4,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_duration.toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _handle(isStart: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Music row: local drag state so < > handles move smoothly (no full-tree rebuild).
class _MusicTimelineLane extends StatefulWidget {
  const _MusicTimelineLane({
    required this.project,
    required this.stripController,
    required this.leftPad,
    required this.pixelsPerSecond,
    required this.selected,
    required this.onSelect,
    required this.onScrollTimeline,
  });

  final SlideshowProject project;
  final ScrollController stripController;
  final double leftPad;
  final double pixelsPerSecond;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double dx) onScrollTimeline;

  static const handleW = 28.0;

  @override
  State<_MusicTimelineLane> createState() => _MusicTimelineLaneState();
}

class _MusicTimelineLaneState extends State<_MusicTimelineLane> {
  double? _liveStart;
  double? _liveEnd;
  bool _interacting = false;
  double _holdOriginDx = 0;

  @override
  void initState() {
    super.initState();
    widget.stripController.addListener(_onStrip);
    widget.project.addListener(_onProject);
  }

  @override
  void didUpdateWidget(covariant _MusicTimelineLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stripController != widget.stripController) {
      oldWidget.stripController.removeListener(_onStrip);
      widget.stripController.addListener(_onStrip);
    }
    if (oldWidget.project != widget.project) {
      oldWidget.project.removeListener(_onProject);
      widget.project.addListener(_onProject);
    }
  }

  @override
  void dispose() {
    widget.stripController.removeListener(_onStrip);
    widget.project.removeListener(_onProject);
    super.dispose();
  }

  void _onStrip() {
    if (mounted) setState(() {});
  }

  void _onProject() {
    if (_interacting || !mounted) return;
    setState(() {});
  }

  (double, double) _range() {
    final videoDur = widget.project.estimatedDurationSec;
    final music = widget.project.music!;
    final start = (_liveStart ?? music.timelineStartSec).clamp(0.0, videoDur);
    final end = (_liveEnd ?? music.timelineEndSec ?? videoDur).clamp(
      start + 0.5,
      videoDur,
    );
    return (start, end);
  }

  void _beginInteract() {
    final (s, e) = _range();
    _interacting = true;
    _liveStart = s;
    _liveEnd = e;
  }

  void _clampLive(double videoDur) {
    const minLen = 0.5;
    final s = (_liveStart ?? 0).clamp(0.0, videoDur - minLen);
    final e = (_liveEnd ?? videoDur).clamp(s + minLen, videoDur);
    _liveStart = s;
    _liveEnd = e;
  }

  /// Left/right handles resize the music clip on the timeline (edge follows finger).
  void _trimByDx({required bool isStart, required double dxPx}) {
    final videoDur = widget.project.estimatedDurationSec;
    final dSec = dxPx / widget.pixelsPerSecond;
    if (!_interacting) _beginInteract();
    setState(() {
      if (isStart) {
        // Drag left → start earlier (bar grows left); drag right → start later.
        _liveStart = (_liveStart! + dSec).clamp(0.0, _liveEnd! - 0.5);
      } else {
        _liveEnd = (_liveEnd! + dSec).clamp(_liveStart! + 0.5, videoDur);
      }
      _clampLive(videoDur);
    });
  }

  void _moveByDx(double dxPx) {
    final videoDur = widget.project.estimatedDurationSec;
    final dSec = dxPx / widget.pixelsPerSecond;
    if (!_interacting) _beginInteract();
    setState(() {
      final len = _liveEnd! - _liveStart!;
      final ns = (_liveStart! + dSec).clamp(0.0, videoDur - len);
      _liveStart = ns;
      _liveEnd = ns + len;
    });
  }

  void _commitInteract() {
    if (!_interacting || _liveStart == null || _liveEnd == null) return;
    widget.project.setMusicTimelineRange(_liveStart!, _liveEnd!);
    _interacting = false;
    _liveStart = null;
    _liveEnd = null;
    if (mounted) setState(() {});
  }

  Widget _gradientTrack(MusicTrack track) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF650CFF), Color(0xFF120799)],
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _MusicWavePainter()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.white, size: 12),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `<` / `>` : music edge follows finger; timeline scrolls the opposite way.
  Widget _handle({required bool isStart, required IconData icon}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => _beginInteract(),
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx == 0) return;
        // Music clip edge moves with the finger…
        _trimByDx(isStart: isStart, dxPx: d.delta.dx);
        // …while the photo/music timeline pans the opposite direction.
        widget.onScrollTimeline(-d.delta.dx);
      },
      onHorizontalDragEnd: (_) => _commitInteract(),
      onHorizontalDragCancel: _commitInteract,
      child: SizedBox(
        width: _MusicTimelineLane.handleW,
        height: double.infinity,
        child: Icon(icon, size: 16, color: Colors.black87),
      ),
    );
  }

  Widget _body(MusicTrack track) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onSelect,
      onLongPressStart: (_) {
        _beginInteract();
        _holdOriginDx = 0;
        HapticFeedback.selectionClick();
      },
      onLongPressMoveUpdate: (d) {
        final dx = d.localOffsetFromOrigin.dx;
        final delta = dx - _holdOriginDx;
        _holdOriginDx = dx;
        if (delta.abs() <= 0.01) return;
        // Hold+drag: music clip follows finger…
        _moveByDx(delta);
        // …image timeline pans the opposite way.
        widget.onScrollTimeline(-delta);
      },
      onLongPressEnd: (_) => _commitInteract(),
      onLongPressCancel: _commitInteract,
      onHorizontalDragUpdate: (d) {
        if (_interacting && _liveStart != null) return;
        widget.onScrollTimeline(d.delta.dx);
      },
      child: _gradientTrack(track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.project.music;
    if (music == null) return const SizedBox.shrink();

    final offset = widget.stripController.hasClients
        ? widget.stripController.offset
        : 0.0;
    final videoDur = widget.project.estimatedDurationSec;
    final (startSec, endSec) = _range();
    final trackLeft = widget.leftPad - offset;
    final trackWidth = math.max(videoDur * widget.pixelsPerSecond, 120.0);
    final barLeft = trackLeft + startSec * widget.pixelsPerSecond;
    final barWidth = math.max(
      (endSec - startSec) * widget.pixelsPerSecond,
      72.0,
    );
    final selected = widget.selected;
    final posLeft = barLeft - (selected ? _MusicTimelineLane.handleW : 0);
    final posWidth = barWidth + (selected ? _MusicTimelineLane.handleW * 2 : 0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => widget.onScrollTimeline(d.delta.dx),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: trackLeft,
            width: trackWidth,
            top: 2,
            bottom: 2,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x33F8BBD0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: posLeft,
            width: posWidth,
            top: 0,
            bottom: 0,
            child: selected
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x29000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        _handle(isStart: true, icon: Icons.chevron_left),
                        Expanded(child: _body(music)),
                        _handle(isStart: false, icon: Icons.chevron_right),
                      ],
                    ),
                  )
                : _body(music),
          ),
        ],
      ),
    );
  }
}

class _MusicWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final bars = math.max(16, (size.width / 3.5).floor());
    for (var i = 0; i < bars; i++) {
      final t = bars == 1 ? 0.0 : i / (bars - 1);
      final wave =
          math.sin(t * math.pi * 6.5) * 0.4 +
          math.sin(t * math.pi * 2.4 + 1.1) * 0.35 +
          0.5;
      final h = (3.0 + wave.clamp(0.12, 1.0) * (size.height - 6)).clamp(
        3.0,
        size.height - 2,
      );
      final x = t * size.width;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thin line for effect when Effects tools are closed (same start/end as bar).
class _EffectCollapsedLine extends StatefulWidget {
  const _EffectCollapsedLine({
    required this.project,
    required this.stripController,
    required this.leftPad,
    required this.pixelsPerSecond,
  });

  final SlideshowProject project;
  final ScrollController stripController;
  final double leftPad;
  final double pixelsPerSecond;

  @override
  State<_EffectCollapsedLine> createState() => _EffectCollapsedLineState();
}

class _EffectCollapsedLineState extends State<_EffectCollapsedLine> {
  @override
  void initState() {
    super.initState();
    widget.stripController.addListener(_tick);
    widget.project.addListener(_tick);
  }

  @override
  void didUpdateWidget(covariant _EffectCollapsedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stripController != widget.stripController) {
      oldWidget.stripController.removeListener(_tick);
      widget.stripController.addListener(_tick);
    }
    if (oldWidget.project != widget.project) {
      oldWidget.project.removeListener(_tick);
      widget.project.addListener(_tick);
    }
  }

  @override
  void dispose() {
    widget.stripController.removeListener(_tick);
    widget.project.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.project.isEffectOverlayEnabled ||
        widget.project.selectedOverlayEffect == null) {
      return const SizedBox.shrink();
    }
    final offset = widget.stripController.hasClients
        ? widget.stripController.offset
        : 0.0;
    final videoDur = widget.project.estimatedDurationSec;
    final startSec = widget.project.overlayTimelineStartSec.clamp(
      0.0,
      videoDur,
    );
    final endSec = (widget.project.overlayTimelineEndSec ?? videoDur).clamp(
      startSec + 0.05,
      videoDur,
    );
    final trackLeft = widget.leftPad - offset;
    final barLeft = trackLeft + startSec * widget.pixelsPerSecond;
    final barWidth = math.max(
      (endSec - startSec) * widget.pixelsPerSecond,
      2.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final lineH = _EditorScreenState._musicPlaceholderH;
        final lineTop = ((constraints.maxHeight - lineH) / 2).clamp(
          0.0,
          double.infinity,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: barLeft,
              width: barWidth,
              top: lineTop,
              height: lineH,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFC5B0F5),
                  borderRadius: BorderRadius.all(Radius.circular(1)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Effect row — same interaction model as music (trim handles + hold-move).
class _EffectTimelineLane extends StatefulWidget {
  const _EffectTimelineLane({
    required this.project,
    required this.stripController,
    required this.leftPad,
    required this.pixelsPerSecond,
    required this.selected,
    required this.onSelect,
    required this.onScrollTimeline,
  });

  final SlideshowProject project;
  final ScrollController stripController;
  final double leftPad;
  final double pixelsPerSecond;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double dx) onScrollTimeline;

  static const handleW = 28.0;

  @override
  State<_EffectTimelineLane> createState() => _EffectTimelineLaneState();
}

class _EffectTimelineLaneState extends State<_EffectTimelineLane> {
  double? _liveStart;
  double? _liveEnd;
  bool _interacting = false;
  double _holdOriginDx = 0;

  @override
  void initState() {
    super.initState();
    widget.stripController.addListener(_onStrip);
    widget.project.addListener(_onProject);
  }

  @override
  void didUpdateWidget(covariant _EffectTimelineLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stripController != widget.stripController) {
      oldWidget.stripController.removeListener(_onStrip);
      widget.stripController.addListener(_onStrip);
    }
    if (oldWidget.project != widget.project) {
      oldWidget.project.removeListener(_onProject);
      widget.project.addListener(_onProject);
    }
  }

  @override
  void dispose() {
    widget.stripController.removeListener(_onStrip);
    widget.project.removeListener(_onProject);
    super.dispose();
  }

  void _onStrip() {
    if (mounted) setState(() {});
  }

  void _onProject() {
    if (_interacting || !mounted) return;
    setState(() {});
  }

  (double, double) _range() {
    final videoDur = widget.project.estimatedDurationSec;
    final start = (_liveStart ?? widget.project.overlayTimelineStartSec).clamp(
      0.0,
      videoDur,
    );
    final end = (_liveEnd ?? widget.project.overlayTimelineEndSec ?? videoDur)
        .clamp(start + 0.5, videoDur);
    return (start, end);
  }

  void _beginInteract() {
    final (s, e) = _range();
    _interacting = true;
    _liveStart = s;
    _liveEnd = e;
  }

  void _clampLive(double videoDur) {
    const minLen = 0.5;
    final s = (_liveStart ?? 0).clamp(0.0, videoDur - minLen);
    final e = (_liveEnd ?? videoDur).clamp(s + minLen, videoDur);
    _liveStart = s;
    _liveEnd = e;
  }

  void _trimByDx({required bool isStart, required double dxPx}) {
    final videoDur = widget.project.estimatedDurationSec;
    final dSec = dxPx / widget.pixelsPerSecond;
    if (!_interacting) _beginInteract();
    setState(() {
      if (isStart) {
        _liveStart = (_liveStart! + dSec).clamp(0.0, _liveEnd! - 0.5);
      } else {
        _liveEnd = (_liveEnd! + dSec).clamp(_liveStart! + 0.5, videoDur);
      }
      _clampLive(videoDur);
    });
  }

  void _moveByDx(double dxPx) {
    final videoDur = widget.project.estimatedDurationSec;
    final dSec = dxPx / widget.pixelsPerSecond;
    if (!_interacting) _beginInteract();
    setState(() {
      final len = _liveEnd! - _liveStart!;
      final ns = (_liveStart! + dSec).clamp(0.0, videoDur - len);
      _liveStart = ns;
      _liveEnd = ns + len;
    });
  }

  void _commitInteract() {
    if (!_interacting || _liveStart == null || _liveEnd == null) return;
    widget.project.commitOverlayTimelineRange(_liveStart!, _liveEnd!);
    _interacting = false;
    _liveStart = null;
    _liveEnd = null;
    if (mounted) setState(() {});
  }

  Widget _handle({required bool isStart, required IconData icon}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => _beginInteract(),
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx == 0) return;
        _trimByDx(isStart: isStart, dxPx: d.delta.dx);
        widget.onScrollTimeline(-d.delta.dx);
      },
      onHorizontalDragEnd: (_) => _commitInteract(),
      onHorizontalDragCancel: _commitInteract,
      child: SizedBox(
        width: _EffectTimelineLane.handleW,
        height: double.infinity,
        child: Icon(icon, size: 16, color: Colors.black87),
      ),
    );
  }

  Widget _body(OverlayEffect effect) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onSelect,
      onLongPressStart: (_) {
        _beginInteract();
        _holdOriginDx = 0;
        HapticFeedback.selectionClick();
      },
      onLongPressMoveUpdate: (d) {
        final dx = d.localOffsetFromOrigin.dx;
        final delta = dx - _holdOriginDx;
        _holdOriginDx = dx;
        if (delta.abs() <= 0.01) return;
        _moveByDx(delta);
        widget.onScrollTimeline(-delta);
      },
      onLongPressEnd: (_) => _commitInteract(),
      onLongPressCancel: _commitInteract,
      onHorizontalDragUpdate: (d) {
        if (_interacting && _liveStart != null) return;
        widget.onScrollTimeline(d.delta.dx);
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF7B2FFF), Color(0xFF3A0CA3)],
          ),
          borderRadius: BorderRadius.circular(2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Image.asset(
                  effect.thumbPath,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.black26,
                    child: SizedBox(width: 22, height: 22),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                effect.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.project.selectedOverlayEffect;
    if (effect == null || !widget.project.isEffectOverlayEnabled) {
      return const SizedBox.shrink();
    }

    final offset = widget.stripController.hasClients
        ? widget.stripController.offset
        : 0.0;
    final videoDur = widget.project.estimatedDurationSec;
    final (startSec, endSec) = _range();
    final trackLeft = widget.leftPad - offset;
    final trackWidth = math.max(videoDur * widget.pixelsPerSecond, 120.0);
    final barLeft = trackLeft + startSec * widget.pixelsPerSecond;
    final barWidth = math.max(
      (endSec - startSec) * widget.pixelsPerSecond,
      72.0,
    );
    final selected = widget.selected;
    final posLeft = barLeft - (selected ? _EffectTimelineLane.handleW : 0);
    final posWidth =
        barWidth + (selected ? _EffectTimelineLane.handleW * 2 : 0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => widget.onScrollTimeline(d.delta.dx),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: trackLeft,
            width: trackWidth,
            top: 2,
            bottom: 2,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x337B2FFF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: posLeft,
            width: posWidth,
            top: 0,
            bottom: 0,
            child: selected
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x29000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        _handle(isStart: true, icon: Icons.chevron_left),
                        Expanded(child: _body(effect)),
                        _handle(isStart: false, icon: Icons.chevron_right),
                      ],
                    ),
                  )
                : _body(effect),
          ),
        ],
      ),
    );
  }
}

/// Live FX overlay via raster frames + BlendMode.screen
/// (VideoPlayer textures ignore Flutter blend modes → black bg used to show).
class _LiveEffectOverlayLayer extends StatefulWidget {
  const _LiveEffectOverlayLayer({
    super.key,
    required this.project,
    required this.effect,
  });

  final SlideshowProject project;
  final OverlayEffect effect;

  @override
  State<_LiveEffectOverlayLayer> createState() =>
      _LiveEffectOverlayLayerState();
}

class _LiveEffectOverlayLayerState extends State<_LiveEffectOverlayLayer> {
  final List<ui.Image> _frames = [];
  int _loadGen = 0;
  int _frameIndex = 0;
  bool _ready = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.project.previewPositionListenable.addListener(_onClock);
    widget.project.addListener(_onProject);
    unawaited(_loadFrames(widget.effect));
  }

  @override
  void didUpdateWidget(covariant _LiveEffectOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect.id != widget.effect.id) {
      unawaited(_loadFrames(widget.effect));
    }
    if (oldWidget.project != widget.project) {
      oldWidget.project.previewPositionListenable.removeListener(_onClock);
      oldWidget.project.removeListener(_onProject);
      widget.project.previewPositionListenable.addListener(_onClock);
      widget.project.addListener(_onProject);
    }
  }

  @override
  void dispose() {
    widget.project.previewPositionListenable.removeListener(_onClock);
    widget.project.removeListener(_onProject);
    _disposeFrames();
    super.dispose();
  }

  void _onClock() => _syncToClock();

  void _onProject() {
    if (mounted) _syncToClock();
  }

  void _disposeFrames() {
    for (final f in _frames) {
      f.dispose();
    }
    _frames.clear();
    _ready = false;
  }

  Future<void> _loadFrames(OverlayEffect effect) async {
    final gen = ++_loadGen;
    _disposeFrames();
    if (mounted) setState(() {});
    try {
      final (pw, ph) = widget.project.previewSize;
      final (w, h) = EffectOverlayService.cappedSize(pw, ph, maxSide: 360);
      final files = await EffectOverlayService.previewFrames(
        effect: effect,
        width: w,
        height: h,
      );
      if (!mounted || gen != _loadGen) return;
      final decoded = <ui.Image>[];
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        decoded.add(frame.image);
        if (!mounted || gen != _loadGen) {
          for (final img in decoded) {
            img.dispose();
          }
          return;
        }
      }
      if (!mounted || gen != _loadGen) {
        for (final img in decoded) {
          img.dispose();
        }
        return;
      }
      _frames
        ..clear()
        ..addAll(decoded);
      widget.project.setOverlaySourceDuration(
        _frames.length / EffectOverlayService.previewFps,
      );
      setState(() => _ready = true);
      _syncToClock();
    } catch (_) {
      if (mounted && gen == _loadGen) {
        setState(() => _ready = false);
      }
    }
  }

  void _syncToClock() {
    if (!_ready || _frames.isEmpty || !mounted) return;
    final visible = widget.project.isLiveEffectVisible;
    final local = widget.project.liveEffectLocalSec();
    final idx =
        (local * EffectOverlayService.previewFps).floor() % _frames.length;
    if (visible != _visible || idx != _frameIndex) {
      setState(() {
        _visible = visible;
        _frameIndex = idx;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_visible || _frames.isEmpty) {
      return const SizedBox.shrink();
    }
    final image = _frames[_frameIndex.clamp(0, _frames.length - 1)];
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScreenEffectPainter(image: image, blend: widget.effect.blend),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScreenEffectPainter extends CustomPainter {
  _ScreenEffectPainter({required this.image, required this.blend});

  final ui.Image image;
  final OverlayBlendMode blend;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (blend == OverlayBlendMode.chromaGreen) {
      // Soft fallback: screen still removes most keyed greens poorly;
      // prefer screen for black-bg packs (current assets).
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image,
        fit: BoxFit.cover,
        blendMode: BlendMode.screen,
        filterQuality: FilterQuality.low,
      );
      return;
    }
    paintImage(
      canvas: canvas,
      rect: rect,
      image: image,
      fit: BoxFit.cover,
      blendMode: BlendMode.screen,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _ScreenEffectPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.blend != blend;
}

enum _MusicSourceTab { myMusic, local }

/// Music picker sheet — same white chrome as other editor tool sheets.
class _MusicPickerSheet extends StatefulWidget {
  const _MusicPickerSheet({
    required this.project,
    required this.onClose,
    required this.onConfirm,
    required this.onOpenLibrary,
    required this.onPickLocal,
  });

  final SlideshowProject project;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final VoidCallback onOpenLibrary;
  final VoidCallback onPickLocal;

  @override
  State<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<_MusicPickerSheet>
    with WidgetsBindingObserver {
  /// Sheet opens with My Music selected by default.
  _MusicSourceTab _source = _MusicSourceTab.myMusic;
  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _previewPath;
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_previewPlayer.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Home / Recents while previewing a track → pause immediately.
      unawaited(_pausePreviewForBackground());
    }
  }

  Future<void> _pausePreviewForBackground() async {
    try {
      await _previewPlayer.pause();
    } catch (_) {}
    if (!mounted) {
      _previewPlaying = false;
      return;
    }
    if (_previewPlaying) {
      setState(() => _previewPlaying = false);
    }
  }

  Future<void> _stopPreview() async {
    try {
      await _previewPlayer.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _previewPath = null;
        _previewPlaying = false;
      });
    } else {
      _previewPath = null;
      _previewPlaying = false;
    }
  }

  Future<void> _playTrack(MusicTrack track) async {
    try {
      widget.project.setMusic(track);
      // Avoid clashing with editor slideshow preview audio.
      widget.project.stopPreviewPlayback();
      if (track.isAsset) {
        await _previewPlayer.setAsset(track.path);
      } else {
        await _previewPlayer.setFilePath(track.path);
      }
      await _previewPlayer.setVolume((track.volume / 100).clamp(0.0, 1.0));
      await _previewPlayer.play();
      if (!mounted) return;
      setState(() {
        _previewPath = track.path;
        _previewPlaying = true;
      });
                            } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Playback failed: $e')));
    }
  }

  Future<void> _onTrackTap(MusicTrack track) async {
    final isSel = widget.project.music?.path == track.path;
    if (isSel && _previewPath == track.path && _previewPlaying) {
      await _previewPlayer.pause();
      if (mounted) setState(() => _previewPlaying = false);
      return;
    }
    if (isSel && _previewPath == track.path && !_previewPlaying) {
      await _previewPlayer.play();
      if (mounted) setState(() => _previewPlaying = true);
      return;
    }
    await _playTrack(track);
  }

  Widget _trackTile(MusicTrack track, MusicTrack? selected) {
    final isSel = selected?.path == track.path;
    final isPlaying = isSel && _previewPath == track.path && _previewPlaying;
    return _MusicThumbTile(
      title: track.title,
      selected: isSel,
      onTap: () => _onTrackTap(track),
      child: SizedBox(
        width: 58,
        child: Center(
          child: Icon(
            isSel
                ? (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)
                : Icons.library_music,
            color: isSel ? AppColors.iconActive : AppColors.textDark,
            size: 28,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.project.music;
    final isLocal = _source == _MusicSourceTab.local;
    final tracks = isLocal
        ? widget.project.localMusicTracks
        : MusicTrack.popular;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                IconButton(
                  onPressed: () async {
                    await _stopPreview();
                    widget.onClose();
                  },
                  icon: const Icon(Icons.close, color: AppColors.textDark),
                ),
                const Expanded(child: Center(child: SheetTitle('Music'))),
                IconButton(
                  onPressed: () async {
                    await _stopPreview();
                    widget.onConfirm();
                  },
                  icon: const Icon(Icons.check, color: AppColors.primary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _MusicSourceButton(
                    image: 'assets/images/my_music.png',
                    label: 'My Music',
                    selected: _source == _MusicSourceTab.myMusic,
                    onTap: () async {
                      if (_source == _MusicSourceTab.myMusic) return;
                      await _stopPreview();
                      if (!mounted) return;
                      setState(() => _source = _MusicSourceTab.myMusic);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MusicSourceButton(
                    image: 'assets/images/local_music.png',
                    label: 'Local',
                    selected: isLocal,
                    onTap: () async {
                      if (_source == _MusicSourceTab.local) return;
                      await _stopPreview();
                      if (!mounted) return;
                      setState(() => _source = _MusicSourceTab.local);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: tracks.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                if (index == 0) {
                  if (isLocal) {
                    return _MusicThumbTile(
                      title: 'Import',
                      selected: false,
                      onTap: widget.onPickLocal,
                      child: SizedBox(
                        width: 58,
                        child: Center(
                          child: Image.asset(
                            'assets/images/local_music.png',
                            color: AppColors.primary,
                            width: 28,
                            height: 28,
                          ),
                        ),
                      ),
                    );
                  }
                  final isSel = selected == null;
                  return _MusicThumbTile(
                    title: 'None',
                    selected: isSel,
                    onTap: () async {
                      await _stopPreview();
                      widget.project.setMusic(null);
                    },
                    child: SizedBox(
                      width: 58,
                      child: Center(
                        child: Icon(
                          Icons.music_off_outlined,
                          color: isSel
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 28,
                        ),
                      ),
                    ),
                  );
                }
                return _trackTile(tracks[index - 1], selected);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MusicSourceButton extends StatelessWidget {
  const _MusicSourceButton({
    required this.image,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String image;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _selectedGradient = LinearGradient(
    colors: [Color(0xFF4DD0E1), Color(0xFF42A5F5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? _selectedGradient : null,
            color: selected ? null : const Color(0xFFEDEFFB),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(image, color: fg, width: 24),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MusicThumbTile extends StatelessWidget {
  const _MusicThumbTile({
    required this.title,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,

        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.23),
                      offset: Offset.zero,
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ],
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide tool content: horizontal list of transition tiles.
class _SlideTransitions extends StatelessWidget {
  const _SlideTransitions({required this.project, required this.onChanged});

  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final options = SlideTransitionOption.all;
    final selectedId = project.selectedSlideTransition.id;
    const accent = Color(0xFF4FC3F7);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(width: 0),
      itemBuilder: (context, i) {
        final option = options[i];
        final selected = option.id == selectedId;
        return GestureDetector(
          onTap: () {
            project.selectSlideTransition(option);
            onChanged();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 68,
            height: 68,
            child: Image.asset(
              option.isNone
                  ? 'assets/images/editor/transitions/default.png'
                  : option.assetPath!,
              fit: BoxFit.contain,
              color: selected ? accent : null,
              colorBlendMode: selected ? BlendMode.srcIn : null,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}

/// Effects picker — music-style sheet with only the 6 video FX.
class _EffectsPickerSheet extends StatefulWidget {
  const _EffectsPickerSheet({
    required this.project,
    required this.onClose,
    required this.onConfirm,
  });

  final SlideshowProject project;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  State<_EffectsPickerSheet> createState() => _EffectsPickerSheetState();
}

class _EffectsPickerSheetState extends State<_EffectsPickerSheet> {
  String? _previewId;

  @override
  void initState() {
    super.initState();
    // Ensure slideshow preview is not fighting effect-list VideoPlayers.
    widget.project.stopPreviewPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final effects = OverlayEffect.all;
    final selected = widget.project.selectedOverlayEffect;
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, color: AppColors.textDark),
                ),
                const Expanded(child: Center(child: SheetTitle('Effects'))),
                IconButton(
                  onPressed: () {
                    // Heavy frame rebuild only on confirm — not on each list tap.
                    widget.project.commitOverlayEffect(resetClip: false);
                    widget.onConfirm();
                  },
                  icon: const Icon(Icons.check, color: AppColors.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: effects.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
                final effect = effects[i];
                final isSel = selected?.id == effect.id;
                final playing = isSel && _previewId == effect.id;
                return _EffectOverlayTile(
                  effect: effect,
                  selected: isSel,
                  playing: playing,
                  onTap: () {
                    // Soft pick + in-list video only (no preview rebuild).
                    widget.project.previewPickOverlayEffect(effect);
                    setState(() => _previewId = effect.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectOverlayTile extends StatelessWidget {
  const _EffectOverlayTile({
    required this.effect,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  final OverlayEffect effect;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
        return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Container(
              width: 88,
              height: 72,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
                color: Colors.black,
              ),
              clipBehavior: Clip.antiAlias,
              child: _EffectLoopPreview(
                assetPath: effect.assetPath,
                thumbPath: effect.thumbPath,
                playing: playing,
              ),
            ),
            const SizedBox(height: 6),
                Text(
              effect.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                fontSize: 12,
                color: selected ? AppColors.primaryDark : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

/// List preview: paused on thumb until [playing], then muted loop in-tile.
class _EffectLoopPreview extends StatefulWidget {
  const _EffectLoopPreview({
    required this.assetPath,
    required this.thumbPath,
    required this.playing,
  });

  final String assetPath;
  final String thumbPath;
  final bool playing;

  @override
  State<_EffectLoopPreview> createState() => _EffectLoopPreviewState();
}

class _EffectLoopPreviewState extends State<_EffectLoopPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.playing) unawaited(_ensurePlaying());
  }

  @override
  void didUpdateWidget(covariant _EffectLoopPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _disposeController();
      if (widget.playing) unawaited(_ensurePlaying());
      return;
    }
    if (widget.playing && !oldWidget.playing) {
      unawaited(_ensurePlaying());
    } else if (!widget.playing && oldWidget.playing) {
      unawaited(_pauseOnly());
    }
  }

  Future<void> _ensurePlaying() async {
    var c = _controller;
    if (c == null) {
      c = VideoPlayerController.asset(widget.assetPath);
      _controller = c;
      try {
        await c.initialize();
        await c.setLooping(true);
        await c.setVolume(0);
        if (!mounted || !identical(_controller, c)) return;
        setState(() => _ready = true);
      } catch (_) {
        await c.dispose();
        if (identical(_controller, c)) _controller = null;
        if (mounted) setState(() => _ready = false);
        return;
      }
    }
    if (!widget.playing) return;
    try {
      await c.play();
    } catch (_) {}
  }

  Future<void> _pauseOnly() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _ready = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (widget.playing && _ready && c != null && c.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      );
    }
    return Image.asset(
      widget.thumbPath,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.auto_awesome, color: Colors.white54)),
    );
  }
}

class _FramePanel extends StatelessWidget {
  const _FramePanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  static const _accent = Color(0xFF00C6D7);
  static const _muted = Color(0xFF9E9E9E);
  static const _tile = 72.0;

  @override
  Widget build(BuildContext context) {
    final frames = FrameAsset.all;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      itemCount: frames.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          final selected = project.selectedFrameAsset == null;
          return _frameTile(
          selected: selected,
            label: 'Default',
            onTap: () {
              project.selectFrame(null);
              onChanged();
            },
            child: const Icon(Icons.block, size: 34, color: _muted),
          );
        }
        final frame = frames[i - 1];
        final selected = project.selectedFrameAsset == frame.assetPath;
        final n = i.toString().padLeft(2, '0');
        return _frameTile(
          selected: selected,
          label: 'Frame_$n',
          onTap: () {
            project.selectFrame(frame.assetPath);
            onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              frame.assetPath,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      },
    );
  }

  Widget _frameTile({
    required bool selected,
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final borderColor = selected ? _accent : const Color(0xFFD0D0D0);
    final labelColor = selected ? _accent : _muted;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _tile,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: borderColor,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      left: -2,
                      top: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: PhotoFilterPreset.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final f = PhotoFilterPreset.values[i];
        final selected = project.globalFilter == f;
        return GestureDetector(
          onTap: () {
            project.setGlobalFilter(f);
            onChanged();
          },
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.surfaceAlt,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Icon(
                  Icons.filter,
                  color: selected ? AppColors.primary : AppColors.iconNormal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                f.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textDark,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StickerPanel extends StatelessWidget {
  const _StickerPanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: StickerItem.all.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          return GestureDetector(
            onTap: () {
              project.clearOverlays();
              onChanged();
            },
            child: Container(
              width: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        final s = StickerItem.all[i - 1];
        return GestureDetector(
          onTap: () {
            project.addOverlay(
              SlideOverlay(
                id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
                kind: OverlayKind.sticker,
                stickerEmoji: s.emoji,
                ny: 0.35 + (project.overlays.length % 3) * 0.12,
                nx: 0.3 + (project.overlays.length % 4) * 0.12,
              ),
            );
            onChanged();
          },
          child: Container(
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.surfaceAlt,
            ),
            child: Text(s.emoji, style: const TextStyle(fontSize: 28)),
          ),
        );
      },
    );
  }
}

class _RatioPanel extends StatelessWidget {
  const _RatioPanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: AspectPreset.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final a = AspectPreset.values[i];
        final selected = project.aspectRatio == a;
        return GestureDetector(
          onTap: () {
            project.setAspect(a);
            onChanged();
          },
          child: Container(
            width: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
              color: selected ? AppColors.primarySoft : Colors.white,
            ),
            child: Text(
              a.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primaryDark : AppColors.textDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BgPanel extends StatelessWidget {
  const _BgPanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: BgOption.all.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final bg = BgOption.all[i];
        final selected = project.backgroundArgb == bg.argb;
        return GestureDetector(
          onTap: () {
            project.setBackground(bg.argb);
            onChanged();
          },
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(bg.argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(bg.label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({
    required this.controller,
    required this.project,
    required this.onApplied,
  });

  final TextEditingController controller;
  final SlideshowProject project;
  final VoidCallback onApplied;

  static const _colors = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFFFEB3B,
    0xFFFF5722,
    0xFF00BFA5,
    0xFF2196F3,
  ];

  @override
  Widget build(BuildContext context) {
        return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Add text overlay…',
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final c in _colors)
                Padding(
          padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      if (controller.text.trim().isEmpty) return;
                      project.addOverlay(
                        SlideOverlay(
                          id: 'text_${DateTime.now().millisecondsSinceEpoch}',
                          kind: OverlayKind.text,
                          text: controller.text.trim(),
                          colorArgb: c,
                          ny: 0.78,
                        ),
                      );
                      onApplied();
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final ids = project.overlays
                      .where((o) => o.kind == OverlayKind.text)
                      .map((o) => o.id)
                      .toList();
                  for (final id in ids) {
                    project.removeOverlay(id);
                  }
                  onApplied();
                },
                child: const Text('Clear text'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TitleCardPanel extends StatefulWidget {
  const _TitleCardPanel({
    required this.label,
    required this.card,
    required this.onChanged,
    required this.onClear,
  });

  final String label;
  final TitleCard? card;
  final ValueChanged<TitleCard> onChanged;
  final VoidCallback onClear;

  @override
  State<_TitleCardPanel> createState() => _TitleCardPanelState();
}

class _TitleCardPanelState extends State<_TitleCardPanel> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.card?.title ?? 'My Slideshow');
    _subtitle = TextEditingController(text: widget.card?.subtitle ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Title',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subtitle,
            decoration: const InputDecoration(
              labelText: 'Subtitle',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  widget.onChanged(
                    TitleCard(
                      title: _title.text.trim().isEmpty
                          ? widget.label
                          : _title.text.trim(),
                      subtitle: _subtitle.text.trim(),
                    ),
                  );
                },
                child: Text('Apply ${widget.label}'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: widget.onClear,
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveClipPreview extends StatefulWidget {
  const _LiveClipPreview({
    super.key,
    required this.photoIndex,
    required this.photo,
    required this.backgroundArgb,
    required this.backgroundBlurLevel,
    required this.replayToken,
    required this.mode,
    required this.onFraction,
    required this.onFinished,
    this.inSecOverride,
    this.outSecOverride,
    this.holdFraction,
  });

  final int photoIndex;
  final SlideshowPhoto photo;
  final int backgroundArgb;
  final int? backgroundBlurLevel;
  final int replayToken;
  final _LiveMode mode;
  final double? inSecOverride;
  final double? outSecOverride;

  /// When set, the clip stays on this fraction instead of playing.
  final double? holdFraction;
  final ValueChanged<double> onFraction;
  final VoidCallback onFinished;

  @override
  State<_LiveClipPreview> createState() => _LiveClipPreviewState();
}

class _LiveClipPreviewState extends State<_LiveClipPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: _clipDuration);
    if (widget.holdFraction != null) {
      _clock.value = widget.holdFraction!.clamp(0.0, 1.0);
      return;
    }
    _clock.value = _settledFraction();
    _scheduleRun();
  }

  @override
  void didUpdateWidget(covariant _LiveClipPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clock.duration = _clipDuration;
    if (widget.holdFraction != null) {
      _run++;
      _clock
        ..removeListener(_onTick)
        ..stop();
      _setClock(widget.holdFraction!.clamp(0.0, 1.0));
      return;
    }
    if (widget.replayToken != oldWidget.replayToken ||
        widget.mode != oldWidget.mode) {
      if (widget.mode == _LiveMode.idle &&
          widget.replayToken == oldWidget.replayToken) {
        _run++;
        _clock
          ..removeListener(_onTick)
          ..stop();
        return;
      }
      _scheduleRun();
    }
  }

  @override
  void dispose() {
    _run++;
    _clock
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  Duration get _clipDuration {
    final ms = (widget.photo.durationSec * 1000).round().clamp(100, 60000);
    return Duration(milliseconds: ms);
  }

  (double, double) _windows() {
    final photo = widget.photo;
    final max = photo.durationSec < 0.1 ? 0.1 : photo.durationSec;
    final hasIn = photo.animationIn != PhotoAnimationType.none;
    final hasOut = photo.animationOut != PhotoAnimationType.none;
    var inSec = widget.inSecOverride ?? photo.animationInDurationSec;
    var outSec = widget.outSecOverride ?? photo.animationOutDurationSec;
    inSec = hasIn ? inSec.clamp(0.1, max).toDouble() : 0;
    outSec = hasOut ? outSec.clamp(0.1, max).toDouble() : 0;
    if (hasIn && hasOut && inSec + outSec > max) {
      outSec = (max - inSec).clamp(0.1, max).toDouble();
      if (inSec + outSec > max) {
        inSec = (max - outSec).clamp(0.1, max).toDouble();
      }
    }
    return (inSec, outSec);
  }

  double _settledFraction() {
    final total = widget.photo.durationSec;
    if (total <= 0) return 1;
    final (inSec, _) = _windows();
    return (inSec / total).clamp(0.0, 1.0);
  }

  void _onTick() {
    widget.onFraction(_clock.value);
  }

  void _setClock(double value) {
    _clock.removeListener(_onTick);
    _clock.value = value;
  }

  void _finish(int run) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || run != _run) return;
      widget.onFinished();
    });
  }

  void _scheduleRun() {
    final run = ++_run;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || run != _run) return;
      _startRun(run);
    });
  }

  void _startRun(int run) {
    _clock
      ..removeListener(_onTick)
      ..stop();
    final total = widget.photo.durationSec <= 0
        ? 0.1
        : widget.photo.durationSec;
    final (inSec, outSec) = _windows();
    switch (widget.mode) {
      case _LiveMode.idle:
        _setClock(_settledFraction());
      case _LiveMode.inPhase:
        final end = (inSec / total).clamp(0.0, 1.0);
        _setClock(0);
        if (end <= 0.001) {
          _finish(run);
          return;
        }
        _clock
          ..addListener(_onTick)
          ..animateTo(
            end,
            duration: Duration(
              milliseconds: (inSec * 1000).round().clamp(80, 60000),
            ),
          ).whenComplete(() {
            if (!mounted || run != _run) return;
            _finish(run);
          });
      case _LiveMode.outPhase:
        final start = ((total - outSec) / total).clamp(0.0, 1.0);
        _setClock(start);
        if (outSec <= 0.001) {
          _finish(run);
          return;
        }
        _clock
          ..addListener(_onTick)
          ..animateTo(
            1,
            duration: Duration(
              milliseconds: (outSec * 1000).round().clamp(80, 60000),
            ),
          ).whenComplete(() {
            if (!mounted || run != _run) return;
            _finish(run);
          });
      case _LiveMode.full:
        _clock.duration = _clipDuration;
        _setClock(0);
        _clock
          ..addListener(_onTick)
          ..forward().whenComplete(() {
            if (!mounted || run != _run) return;
            _setClock(_settledFraction());
            _finish(run);
          });
    }
  }

  _GpuMotion _motionFor(double fraction) {
    final photo = widget.photo;
    final total = photo.durationSec <= 0 ? 0.1 : photo.durationSec;
    final (inSec, outSec) = _windows();
    final tSec = fraction.clamp(0.0, 1.0) * total;
    final outStart = total - outSec;
    if (photo.animationIn != PhotoAnimationType.none &&
        inSec > 0 &&
        tSec < outStart) {
      if (tSec <= inSec) {
        return _gpuMotion(photo.animationIn, (tSec / inSec).clamp(0.0, 1.0));
      }
      return const _GpuMotion();
    }
    if (photo.animationOut != PhotoAnimationType.none &&
        outSec > 0 &&
        tSec >= outStart) {
      final progress = ((tSec - outStart) / outSec).clamp(0.0, 1.0);
      return _gpuMotion(photo.animationOut, 1 - progress);
    }
    return const _GpuMotion();
  }

  Widget _blurFill(int level) {
    const sigmas = <double>[0, 4, 7, 11, 16];
    final sigma = sigmas[level.clamp(0, sigmas.length - 1)];
    Widget image = _photoImage(fit: BoxFit.cover);
    if (sigma > 0.4) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.mirror,
        ),
        child: image,
      );
    }
    return ClipRect(child: image);
  }

  Widget _photoImage({BoxFit fit = BoxFit.contain}) {
    Widget image = CroppedPhotoView(
      photo: widget.photo,
      fit: fit,
      filterQuality: FilterQuality.high,
    );
    final turns = widget.photo.rotationQuarterTurns % 4;
    if (turns != 0) {
      image = Transform.rotate(angle: turns * math.pi / 2, child: image);
    }
    if (widget.photo.mirrored) {
      image = Transform.flip(flipX: true, child: image);
    }
    if (widget.photo.flipped) {
      image = Transform.flip(flipY: true, child: image);
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.backgroundBlurLevel != null)
          _blurFill(widget.backgroundBlurLevel!)
        else
          ColoredBox(color: Color(widget.backgroundArgb)),
        AnimatedBuilder(
          animation: _clock,
          builder: (context, child) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final motion = _motionFor(_clock.value);
                if (motion.mirrorOpen != null) {
                  return _mirrorDoorOpen(
                    open: motion.mirrorOpen!,
                    size: size,
                    image: _photoImage,
                  );
                }
                Widget framed = Opacity(
                  opacity: motion.opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(
                      motion.dx * size.width,
                      motion.dy * size.height,
                    ),
                    child: Transform.rotate(
                      alignment: motion.alignment,
                      angle: motion.degrees * math.pi / 180,
                      child: Transform(
                        alignment: motion.alignment,
                        transform: Matrix4.diagonal3Values(
                          motion.scaleX.clamp(0.008, 3),
                          motion.scaleY.clamp(0.008, 3),
                          1,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                );
                if (motion.blurX > 0.4 || motion.blurY > 0.4) {
                  framed = ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: motion.blurX,
                      sigmaY: motion.blurY,
                    ),
                    child: framed,
                  );
                }
                return ClipRect(
          child: Stack(
                    fit: StackFit.expand,
            children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: _photoImage(),
                      ),
                      framed,
                    ],
                  ),
                );
              },
            );
          },
          child: _photoImage(),
        ),
      ],
    );
  }
}

class _GpuMotion {
  const _GpuMotion({
    this.opacity = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.dx = 0,
    this.dy = 0,
    this.degrees = 0,
    this.alignment = Alignment.center,
    this.blurX = 0,
    this.blurY = 0,
    this.mirrorOpen,
  });

  final double opacity;
  final double scaleX;
  final double scaleY;
  final double dx;
  final double dy;
  final double degrees;
  final Alignment alignment;
  final double blurX;
  final double blurY;
  final double? mirrorOpen;
}

({double progress, double scale, double dx, double dy, double blur}) _wiperPose(
  double t,
) {
  final progress = 1 - math.pow(1 - t, 2.4).toDouble();
  final sweep = 1 - progress;
  return (
    progress: progress,
    scale: 1.7 - 0.7 * progress,
    dx: -0.14 * math.sin(sweep * math.pi),
    dy: -0.24 * sweep,
    blur: 26 * sweep,
  );
}

_GpuMotion _gpuMotion(PhotoAnimationType type, double t) {
  return switch (type) {
    PhotoAnimationType.none => const _GpuMotion(),
    PhotoAnimationType.fade => _GpuMotion(opacity: t),
    PhotoAnimationType.slightZoom => _GpuMotion(
      scaleX: 1.12 - 0.12 * t,
      scaleY: 1.12 - 0.12 * t,
    ),
    PhotoAnimationType.zoomIn => _GpuMotion(
      scaleX: 0.78 + 0.22 * t,
      scaleY: 0.78 + 0.22 * t,
    ),
    PhotoAnimationType.zoomOut => _GpuMotion(
      scaleX: 1.22 - 0.22 * t,
      scaleY: 1.22 - 0.22 * t,
    ),
    PhotoAnimationType.shake => _GpuMotion(
      degrees: math.sin(t * math.pi * 8) * 8,
    ),
    PhotoAnimationType.shake2 => _GpuMotion(
      dx: math.sin(t * math.pi * 12) * 0.05,
      dy: math.cos(t * math.pi * 10) * 0.02,
    ),
    PhotoAnimationType.slideLeft => _GpuMotion(dx: -(1 - t)),
    PhotoAnimationType.slideUp => _GpuMotion(dy: (1 - t)),
    PhotoAnimationType.slideRight => _GpuMotion(dx: (1 - t)),
    PhotoAnimationType.slideDown => _GpuMotion(dy: -(1 - t)),
    PhotoAnimationType.dynamicZoom => _wiperGpu(t),
    PhotoAnimationType.wiper => _GpuMotion(
      degrees: math.sin(t * math.pi * 2) * 14,
      scaleX: 1.34 - 0.34 * t,
      scaleY: 1.34 - 0.34 * t,
      alignment: Alignment.bottomCenter,
    ),
    PhotoAnimationType.dynamicZoomAlt => _GpuMotion(
      scaleX: 1.28 - 0.28 * t,
      scaleY: 1.28 - 0.28 * t,
    ),
    PhotoAnimationType.pendulum => _GpuMotion(
      degrees: math.sin(t * math.pi * 2) * 14,
      alignment: Alignment.topCenter,
    ),
    PhotoAnimationType.upAndDown => _GpuMotion(
      dy: math.sin(t * math.pi * 2) * 0.06,
    ),
    PhotoAnimationType.mirror || PhotoAnimationType.mirrorOutside => _GpuMotion(
      mirrorOpen: t.clamp(0.0, 1.0),
    ),
    PhotoAnimationType.leftAndRight => _GpuMotion(
      dx: math.sin(t * math.pi * 2) * (1 - t * 0.35) * 0.1,
    ),
    PhotoAnimationType.spinRight => _GpuMotion(
      degrees: (1 - t) * 180,
      dx: (1 - t) * 1.15,
    ),
    PhotoAnimationType.spinLeft => _GpuMotion(
      degrees: -(1 - t) * 180,
      dx: -(1 - t) * 1.15,
    ),
    PhotoAnimationType.spinUpper => _GpuMotion(
      degrees: -(1 - t) * 180,
      dy: -(1 - t) * 1.15,
    ),
    PhotoAnimationType.bottomOut => _GpuMotion(dy: (1 - t)),
    PhotoAnimationType.leftOut => _GpuMotion(dx: -(1 - t)),
    PhotoAnimationType.rightOut => _GpuMotion(dx: (1 - t)),
    PhotoAnimationType.topOut => _GpuMotion(dy: -(1 - t)),
    PhotoAnimationType.dynamicZoomOut => _wiperGpu(t),
    PhotoAnimationType.flipLeft => _GpuMotion(
      degrees: -(1 - t) * 180,
      dx: -(1 - t) * 1.15,
    ),
    PhotoAnimationType.flipRight => _GpuMotion(
      degrees: (1 - t) * 180,
      dx: (1 - t) * 1.15,
    ),
    PhotoAnimationType.flipLower => _GpuMotion(
      degrees: (1 - t) * 180,
      dy: (1 - t) * 1.15,
    ),
    PhotoAnimationType.slideOutTop => _GpuMotion(
      opacity: 0.2 + 0.8 * t,
      dy: -(1 - t),
    ),
    PhotoAnimationType.slideOutBottom => _GpuMotion(
      opacity: 0.2 + 0.8 * t,
      dy: (1 - t),
    ),
    PhotoAnimationType.rotateFade => _GpuMotion(
      opacity: t,
      degrees: (1 - t) * 160,
    ),
    PhotoAnimationType.flyOutLeft => _flyOutGpu(t, spinSign: -1, x: -1, y: -1),
    PhotoAnimationType.flyOutRight => _flyOutGpu(t, spinSign: 1, x: 1, y: -1),
    PhotoAnimationType.flyOutUp => _flyOutGpu(
      t,
      spinSign: -1,
      x: 0,
      y: -1,
      yTravel: 0.42,
    ),
  };
}

class _MotionThumb extends StatefulWidget {
  const _MotionThumb({required this.type, required this.phase});

  final PhotoAnimationType type;
  final _AnimationPhase phase;

  @override
  State<_MotionThumb> createState() => _MotionThumbState();
}

class _MotionThumbState extends State<_MotionThumb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        var t = Curves.easeInOut.transform(_controller.value);
        if (widget.phase == _AnimationPhase.outAnimation) {
          t = 1 - t;
        }
        if (widget.type == PhotoAnimationType.mirror ||
            widget.type == PhotoAnimationType.mirrorOutside) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return _mirrorDoorOpen(
                open: t,
                size: constraints.biggest,
                perspective: 0.012,
                blurSigma: 8,
                image: () => Image.asset(
                  'assets/images/editor/animation_thumb.png',
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              );
            },
          );
        }
        final motion = _thumbMotion(widget.type, t);
        Widget framed = Opacity(
          opacity: motion.opacity,
          child: Transform.translate(
            offset: motion.offset,
            child: Transform.rotate(
              alignment: motion.alignment,
              angle: motion.turns * math.pi * 2,
              child: Transform(
                alignment: motion.alignment,
                transform: Matrix4.diagonal3Values(
                  motion.scaleX,
                  motion.scaleY,
                  1,
                ),
                child: child,
              ),
            ),
          ),
        );
        if (motion.blur > 0.4) {
          framed = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: motion.blur,
              sigmaY: motion.blur * 0.22,
            ),
            child: framed,
          );
        }
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Image.asset(
                  'assets/images/editor/animation_thumb.png',
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              framed,
            ],
          ),
        );
      },
      child: Image.asset(
        'assets/images/editor/animation_thumb.png',
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

Widget _mirrorDoorOpen({
  required double open,
  required Size size,
  required Widget Function() image,
  double perspective = 0.0014,
  double blurSigma = 22,
}) {
  if (size.width < 2 || size.height < 2) return image();
  final angle = (1 - open.clamp(0.0, 1.0)) * math.pi / 2;
  return ClipRect(
    child: Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: image(),
          ),
        ),
        _mirrorLeaf(
          left: true,
          angle: angle,
          size: size,
          perspective: perspective,
          image: image,
        ),
        _mirrorLeaf(
          left: false,
          angle: angle,
          size: size,
          perspective: perspective,
          image: image,
        ),
      ],
    ),
  );
}

Widget _mirrorLeaf({
  required bool left,
  required double angle,
  required Size size,
  required double perspective,
  required Widget Function() image,
}) {
  final half = size.width / 2;
  return Positioned(
    left: left ? 0 : half,
    top: 0,
    width: half,
    height: size.height,
    child: Transform(
      alignment: left ? Alignment.centerRight : Alignment.centerLeft,
      filterQuality: FilterQuality.medium,
      transform: Matrix4.identity()
        ..setEntry(3, 2, perspective)
        ..rotateY(left ? -angle : angle),
      child: ClipRect(
        child: OverflowBox(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: image(),
          ),
        ),
      ),
    ),
  );
}

enum _DurationHandle { inn, out }

class _InOutDurationBar extends StatefulWidget {
  const _InOutDurationBar({
    required this.maxSec,
    required this.inSec,
    required this.outSec,
    required this.inEnabled,
    required this.outEnabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double maxSec;
  final double inSec;
  final double outSec;
  final bool inEnabled;
  final bool outEnabled;
  final void Function(double inSec, double outSec) onChanged;
  final void Function(double inSec, double outSec) onChangeEnd;

  @override
  State<_InOutDurationBar> createState() => _InOutDurationBarState();
}

class _InOutDurationBarState extends State<_InOutDurationBar> {
  static const _handle = 22.0;
  static const _yellow = Color(0xFFD6E04A);
  _DurationHandle? _dragging;
  double? _lastIn;
  double? _lastOut;

  double _snap(double seconds) => ((seconds * 10).round() / 10).toDouble();

  (double, double) _valuesFor(double localX, double width) {
    final max = widget.maxSec < 0.1 ? 0.1 : widget.maxSec;
    final track = math.max(1.0, width - _handle);
    final fraction = ((localX - _handle / 2) / track).clamp(0.0, 1.0);
    var inSec = widget.inEnabled ? widget.inSec.clamp(0.1, max) : 0.0;
    var outSec = widget.outEnabled ? widget.outSec.clamp(0.1, max) : 0.0;
    if (_dragging == _DurationHandle.inn) {
      final cap = widget.outEnabled ? math.max(0.1, max - outSec) : max;
      inSec = (fraction * max).clamp(0.1, cap).toDouble();
    } else if (_dragging == _DurationHandle.out) {
      final cap = widget.inEnabled ? math.max(0.1, max - inSec) : max;
      outSec = ((1 - fraction) * max).clamp(0.1, cap).toDouble();
    }
    return (inSec.toDouble(), outSec.toDouble());
  }

  void _pickHandle(double localX, double width) {
    final max = widget.maxSec < 0.1 ? 0.1 : widget.maxSec;
    final track = math.max(1.0, width - _handle);
    final dx = localX - _handle / 2;
    final inX = widget.inEnabled ? (widget.inSec / max) * track : double.nan;
    final outX = widget.outEnabled
        ? (1 - widget.outSec / max) * track
        : double.nan;
    const slop = 36.0;
    final nearIn = widget.inEnabled && (dx - inX).abs() <= slop;
    final nearOut = widget.outEnabled && (dx - outX).abs() <= slop;
    if (nearIn && nearOut) {
      _dragging = (dx - inX).abs() <= (dx - outX).abs()
          ? _DurationHandle.inn
          : _DurationHandle.out;
    } else if (nearIn) {
      _dragging = _DurationHandle.inn;
    } else if (nearOut) {
      _dragging = _DurationHandle.out;
    } else {
      _dragging = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final max = widget.maxSec < 0.1 ? 0.1 : widget.maxSec;
        final track = math.max(1.0, width - _handle);
        final inLimit = widget.inEnabled
            ? (widget.inSec / max).clamp(0.0, 1.0)
            : 0.0;
        final outLimit = widget.outEnabled
            ? (widget.outSec / max).clamp(0.0, 1.0)
            : 0.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.inEnabled || widget.outEnabled
              ? (details) => _pickHandle(details.localPosition.dx, width)
              : null,
          onHorizontalDragUpdate: (details) {
            if (_dragging == null) return;
            final next = _valuesFor(details.localPosition.dx, width);
            _lastIn = next.$1;
            _lastOut = next.$2;
            widget.onChanged(next.$1, next.$2);
          },
          onHorizontalDragEnd: (_) {
            if (_dragging == null) return;
            widget.onChangeEnd(
              _snap(_lastIn ?? widget.inSec),
              _snap(_lastOut ?? widget.outSec),
            );
            _dragging = null;
          },
          onHorizontalDragCancel: () => _dragging = null,
          child: SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
              Positioned(
                  left: _handle / 2,
                  right: _handle / 2,
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xFFE0E0E0)),
                        ),
                        if (inLimit > 0)
                          Positioned(
                            left: 0,
                            width: inLimit * track,
                            top: 0,
                            bottom: 0,
                            child: const ColoredBox(color: _yellow),
                          ),
                        if (outLimit > 0)
                          Positioned(
                            right: 0,
                            width: outLimit * track,
                            top: 0,
                            bottom: 0,
                            child: const ColoredBox(color: _yellow),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.inEnabled)
                  Positioned(
                    left: inLimit * track,
                    child: const _DurationArrow(
                      icon: Icons.chevron_right,
                      active: true,
                    ),
                  )
                else
                  Positioned(
                    left: 0,
                    child: const _DurationArrow(
                      icon: Icons.chevron_right,
                      active: false,
                    ),
                  ),
                if (widget.outEnabled)
                  Positioned(
                    left: (1 - outLimit) * track,
                    child: const _DurationArrow(
                      icon: Icons.chevron_left,
                      active: true,
                    ),
                  )
                else
                  Positioned(
                    left: track,
                    child: const _DurationArrow(
                      icon: Icons.chevron_left,
                      active: false,
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}

class _DurationArrow extends StatelessWidget {
  const _DurationArrow({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFEDEDED),
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? const Color(0xFFD0D0D0) : const Color(0xFFD8D8D8),
        ),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: 16,
        color: active ? const Color(0xFF424242) : const Color(0xFFBDBDBD),
      ),
    );
  }
}

class _ThumbMotion {
  const _ThumbMotion({
    this.opacity = 1,
    this.scaleX = 1,
    this.scaleY = 1,
    this.offset = Offset.zero,
    this.turns = 0,
    this.alignment = Alignment.center,
    this.blur = 0,
  });

  final double opacity;
  final double scaleX;
  final double scaleY;
  final Offset offset;
  final double turns;
  final Alignment alignment;
  final double blur;
}

/// Spins flat, pinches through a diagonal edge, then shrinks along [x] and [y].
({double scale, double pinch, double degrees, double dx, double dy})
_flyOutPose(
  double t, {
  required double spinSign,
  required double x,
  required double y,
  double xTravel = 0.36,
  double yTravel = 0.2,
}) {
  final exit = (1 - t).clamp(0.0, 1.0);
  final spin = 1 - math.pow(1 - math.min(exit / 0.5, 1.0), 1.8).toDouble();
  final flip = math.min(exit / 0.62, 1.0);
  final shrink = math.pow(exit, 1.05).toDouble();
  final drift = math.pow(math.max(exit - 0.28, 0) / 0.72, 1.35).toDouble();
  return (
    scale: 1 - shrink * 0.84,
    pinch: math.cos(flip * math.pi).abs().clamp(0.012, 1.0),
    degrees: spinSign * spin * 52,
    dx: x * drift * xTravel,
    dy: y * drift * yTravel,
  );
}

_GpuMotion _flyOutGpu(
  double t, {
  required double spinSign,
  required double x,
  required double y,
  double xTravel = 0.36,
  double yTravel = 0.2,
}) {
  final pose = _flyOutPose(
    t,
    spinSign: spinSign,
    x: x,
    y: y,
    xTravel: xTravel,
    yTravel: yTravel,
  );
  return _GpuMotion(
    scaleX: pose.scale,
    scaleY: pose.scale * pose.pinch,
    degrees: pose.degrees,
    dx: pose.dx,
    dy: pose.dy,
  );
}

_ThumbMotion _flyOutThumb(
  double t, {
  required double spinSign,
  required double x,
  required double y,
  double xTravel = 0.36,
  double yTravel = 0.2,
}) {
  final pose = _flyOutPose(
    t,
    spinSign: spinSign,
    x: x,
    y: y,
    xTravel: xTravel,
    yTravel: yTravel,
  );
  return _ThumbMotion(
    scaleX: pose.scale,
    scaleY: pose.scale * pose.pinch,
    turns: pose.degrees / 360,
    offset: Offset(pose.dx * 72, pose.dy * 72),
  );
}

_GpuMotion _wiperGpu(double t) {
  final pose = _wiperPose(t);
  return _GpuMotion(
    scaleX: pose.scale,
    scaleY: pose.scale,
    dx: pose.dx,
    dy: pose.dy,
    blurX: pose.blur,
    blurY: pose.blur * 0.22,
  );
}

_ThumbMotion _wiperThumb(double t) {
  final pose = _wiperPose(t);
  return _ThumbMotion(
    scaleX: pose.scale,
    scaleY: pose.scale,
    offset: Offset(pose.dx * 52, pose.dy * 52),
    blur: pose.blur * 0.35,
  );
}

_ThumbMotion _thumbMotion(PhotoAnimationType type, double t) {
  const travel = 56.0;
  return switch (type) {
    PhotoAnimationType.none => const _ThumbMotion(),
    PhotoAnimationType.fade => _ThumbMotion(opacity: 0.15 + 0.85 * t),
    PhotoAnimationType.slightZoom => _ThumbMotion(
      scaleX: 1.1 - 0.1 * t,
      scaleY: 1.1 - 0.1 * t,
    ),
    PhotoAnimationType.zoomIn => _ThumbMotion(
      scaleX: 0.72 + 0.28 * t,
      scaleY: 0.72 + 0.28 * t,
    ),
    PhotoAnimationType.zoomOut => _ThumbMotion(
      scaleX: 1.28 - 0.28 * t,
      scaleY: 1.28 - 0.28 * t,
    ),
    PhotoAnimationType.shake => _ThumbMotion(
      turns: math.sin(t * math.pi * 8) * 8 / 360,
    ),
    PhotoAnimationType.shake2 => _ThumbMotion(
      offset: Offset(
        math.sin(t * math.pi * 6) * 4,
        math.cos(t * math.pi * 4) * 2,
      ),
    ),
    PhotoAnimationType.slideLeft => _ThumbMotion(
      offset: Offset(-(1 - t) * travel, 0),
    ),
    PhotoAnimationType.slideRight => _ThumbMotion(
      offset: Offset((1 - t) * travel, 0),
    ),
    PhotoAnimationType.slideUp => _ThumbMotion(
      offset: Offset(0, (1 - t) * travel),
    ),
    PhotoAnimationType.slideDown => _ThumbMotion(
      offset: Offset(0, -(1 - t) * travel),
    ),
    PhotoAnimationType.dynamicZoom => _wiperThumb(t),
    PhotoAnimationType.wiper => _ThumbMotion(
      turns: math.sin(t * math.pi * 2) * 14 / 360,
      scaleX: 1.34 - 0.34 * t,
      scaleY: 1.34 - 0.34 * t,
      alignment: Alignment.bottomCenter,
    ),
    PhotoAnimationType.dynamicZoomAlt => _ThumbMotion(
      scaleX: 1.28 - 0.28 * t,
      scaleY: 1.28 - 0.28 * t,
    ),
    PhotoAnimationType.pendulum => _ThumbMotion(
      turns: math.sin(t * math.pi * 2) * 14 / 360,
      alignment: Alignment.topCenter,
    ),
    PhotoAnimationType.upAndDown => _ThumbMotion(
      offset: Offset(0, math.sin(t * math.pi * 2) * 6),
    ),
    PhotoAnimationType.leftAndRight => _ThumbMotion(
      offset: Offset(math.sin(t * math.pi * 2) * 12, 0),
    ),
    PhotoAnimationType.spinRight => _ThumbMotion(
      turns: (1 - t) * 0.5,
      offset: Offset((1 - t) * travel, 0),
    ),
    PhotoAnimationType.spinLeft => _ThumbMotion(
      turns: -(1 - t) * 0.5,
      offset: Offset(-(1 - t) * travel, 0),
    ),
    PhotoAnimationType.spinUpper => _ThumbMotion(
      turns: -(1 - t) * 0.5,
      offset: Offset(0, -(1 - t) * travel),
    ),
    PhotoAnimationType.mirror => _ThumbMotion(scaleX: t < 0.5 ? 1 : -1),
    PhotoAnimationType.mirrorOutside => _ThumbMotion(
      scaleX: (t * 2 - 1).clamp(-1, 1),
      offset: Offset((1 - t) * 22, 0),
    ),
    PhotoAnimationType.bottomOut => _ThumbMotion(
      offset: Offset(0, (1 - t) * travel),
    ),
    PhotoAnimationType.leftOut => _ThumbMotion(
      offset: Offset(-(1 - t) * travel, 0),
    ),
    PhotoAnimationType.rightOut => _ThumbMotion(
      offset: Offset((1 - t) * travel, 0),
    ),
    PhotoAnimationType.topOut => _ThumbMotion(
      offset: Offset(0, -(1 - t) * travel),
    ),
    PhotoAnimationType.dynamicZoomOut => _wiperThumb(t),
    PhotoAnimationType.flipLeft => _ThumbMotion(
      turns: -(1 - t) * 0.5,
      offset: Offset(-(1 - t) * travel, 0),
    ),
    PhotoAnimationType.flipLower => _ThumbMotion(
      turns: (1 - t) * 0.5,
      offset: Offset(0, (1 - t) * travel),
    ),
    PhotoAnimationType.flipRight => _ThumbMotion(
      turns: (1 - t) * 0.5,
      offset: Offset((1 - t) * travel, 0),
    ),
    PhotoAnimationType.slideOutTop => _ThumbMotion(
      opacity: 0.2 + 0.8 * t,
      offset: Offset(0, -(1 - t) * travel),
    ),
    PhotoAnimationType.slideOutBottom => _ThumbMotion(
      opacity: 0.2 + 0.8 * t,
      offset: Offset(0, (1 - t) * travel),
    ),
    PhotoAnimationType.rotateFade => _ThumbMotion(
      opacity: 0.15 + 0.85 * t,
      turns: (1 - t) * 0.5,
    ),
    PhotoAnimationType.flyOutLeft => _flyOutThumb(
      t,
      spinSign: -1,
      x: -1,
      y: -1,
    ),
    PhotoAnimationType.flyOutRight => _flyOutThumb(t, spinSign: 1, x: 1, y: -1),
    PhotoAnimationType.flyOutUp => _flyOutThumb(
      t,
      spinSign: -1,
      x: 0,
      y: -1,
      yTravel: 0.42,
    ),
  };
}

class _ApplyAllIcon extends StatelessWidget {
  const _ApplyAllIcon();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size(22, 22),
      painter: _ApplyAllIconPainter(),
    );
  }
}

class _ApplyAllIconPainter extends CustomPainter {
  const _ApplyAllIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF212121)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    final check = Paint()
      ..color = const Color(0xFF212121)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void diamond(Offset center, double halfW, double halfH) {
      final path = Path()
        ..moveTo(center.dx, center.dy - halfH)
        ..lineTo(center.dx + halfW, center.dy)
        ..lineTo(center.dx, center.dy + halfH)
        ..lineTo(center.dx - halfW, center.dy)
        ..close();
      canvas.drawPath(path, stroke);
    }

    diamond(const Offset(9, 5.2), 6.2, 2.6);
    diamond(const Offset(9, 9.2), 6.2, 2.6);
    diamond(const Offset(8.2, 13.4), 5.4, 2.4);

    final mark = Path()
      ..moveTo(12.2, 16.2)
      ..lineTo(14.4, 18.4)
      ..lineTo(19.2, 12.6);
    canvas.drawPath(mark, check);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
