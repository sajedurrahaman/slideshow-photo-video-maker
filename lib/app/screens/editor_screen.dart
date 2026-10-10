import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import '../widgets/editTool_sheet.dart';

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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorTool? _tool;
  _PhotoTool? _photoTool;
  _AnimationPhase _animationPhase = _AnimationPhase.inAnimation;
  double? _durationSliderValue;
  double? _inDurationDrag;
  double? _outDurationDrag;
  final _textController = TextEditingController();
  final _stripController = ScrollController();

  static const _sheetHeight = 180.0;
  static const _timelineHeaderHeight = 48.0;
  static const _photoToolbarHeight = 72.0;
  static const _plusW = 52.0;
  static const _pixelsPerSecond = 44.0;
  static const _thumbH = 60.0;
  static const _transitionMarkerSize = 22.0;
  static const _stripPadLeft = 16.0;

  SlideshowProject? _listenedProject;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the editor paint first so Next→route is not blocked by decode.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      await context.read<SlideshowProject>().refreshLivePreview();
    });
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

  void _onPreviewPosition() {
    if (!mounted || _tool != null) return;
    if (!_stripController.hasClients) return;
    final project = _listenedProject;
    if (project == null) return;
    _syncStripToPlayhead(project: project);
  }

  @override
  void dispose() {
    _listenedProject?.previewPositionListenable.removeListener(
      _onPreviewPosition,
    );
    _stripController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final project = context.read<SlideshowProject>();
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

  /// Preview row shown inside SectionSheet for every tool.
  Widget _previewRow(SlideshowProject project) {
    final disabled = project.isProcessing || project.isPreparingPreview;
    final isSlide = _tool == EditorTool.slide;

    if (isSlide) {
      return Row(
        children: [
          _timeText(project),
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
                color: project.isPreviewReady ? Colors.black87 : Colors.black38,
              ),
            ),
          ),
          const SizedBox(width: 64),
        ],
      );
    }

    return Row(
      children: [
        _timeText(project),
        const Spacer(),
        IconButton(
          onPressed: disabled ? null : _preview,
          icon: Icon(
            project.isPreviewPlaying
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
          ),
          color: project.isPreviewReady
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ],
    );
  }

  /// Idle editor chrome: time + play + undo/redo (same slot as slide headerRow).
  Widget _idlePreviewRow(SlideshowProject project) {
    final disabled = project.isProcessing || project.isPreparingPreview;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _timeText(project),
        Center(
          child: IconButton(
            padding: EdgeInsets.only(left: 12),
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
        if (project.selectedPhotoIndex == null)
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: project.canUndo ? () => project.undo() : null,
                icon: Icon(
                  Icons.undo_rounded,
                  color: project.canUndo ? Colors.black87 : Colors.black26,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: project.canRedo ? () => project.redo() : null,
                icon: Icon(
                  Icons.redo_rounded,
                  color: project.canRedo ? Colors.black87 : Colors.black26,
                ),
              ),
            ],
          )
        else
          const SizedBox(width: 96),
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
    if (!_stripController.hasClients) return;
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
    if ((_stripController.offset - next).abs() < 0.5) return;
    _stripController.jumpTo(next);
  }

  Widget _photoStrip(SlideshowProject project, double playheadX) {
    // Each clip width reflects that photo's independently editable duration.
    final leftPad = playheadX.clamp(0.0, 800.0).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: project.selectedPhotoIndex == null
          ? null
          : () {
              setState(() {
                _tool = null;
                _photoTool = null;
                _durationSliderValue = null;
              });
              project.clearTimelinePhotoSelection();
            },
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: _stripController,
              scrollDirection: Axis.horizontal,
              physics: project.isPreviewPlaying
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(leftPad, 0, playheadX, 44),
              itemCount: project.photos.length,
              itemBuilder: (context, photoIndex) {
                final photo = project.photos[photoIndex];
                final selected = project.selectedPhotoIndex == photoIndex;
                final clipWidth = photo.durationSec * _pixelsPerSecond;
                final canShowDuration = clipWidth >= 72;
                final thumbnailCount = photo.durationSec.ceil();
                return Align(
                  alignment: Alignment.center,
                  child: SizedBox(
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
                              });
                              project.selectTimelinePhoto(photoIndex);
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < thumbnailCount; i++)
                                        SizedBox(
                                          width:
                                              (clipWidth - i * _pixelsPerSecond)
                                                  .clamp(0.0, _pixelsPerSecond)
                                                  .toDouble(),
                                          height: _thumbH,
                                          child: DecoratedBox(
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                right: BorderSide(
                                                  color: Colors.white70,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            child: Image.file(
                                              File(photo.path),
                                              fit: BoxFit.fill,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Positioned(
                                    left: 2,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: _durationHandle(
                                        icon: Icons.chevron_left_rounded,
                                        onTap: () =>
                                            project.changePhotoDuration(
                                              photoIndex,
                                              photo.durationSec - 0.5,
                                            ),
                                      ),
                                    ),
                                  ),
                                if (selected)
                                  Positioned(
                                    right: 2,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: _durationHandle(
                                        icon: Icons.chevron_right_rounded,
                                        onTap: () =>
                                            project.changePhotoDuration(
                                              photoIndex,
                                              photo.durationSec + 0.5,
                                            ),
                                      ),
                                    ),
                                  ),
                                if (selected && canShowDuration)
                                  Positioned(
                                    left: 20,
                                    top: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 1,
                                      ),
                                      color: Colors.black54,
                                      child: Text(
                                        '${photo.durationSec.toStringAsFixed(1)}s',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (selected)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: AppColors.iconActive,
                                            width: 6.4,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
                                    borderRadius: BorderRadius.circular(6),
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
                  ),
                );
              },
            ),
          ),
          if (project.selectedPhotoIndex == null)
            // + stays on top; clips slide underneath while playing.
            Positioned(
              left: _stripPadLeft,
              top: 0,
              bottom: 34,
              child: Center(
                child: GestureDetector(
                  onTap: () => context.push('/gallery'),
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
                    child: const Icon(Icons.add, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _durationHandle({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 16,
        height: 19,
        alignment: Alignment.center,
        color: AppColors.primary,
        child: Icon(icon, size: 16, color: Colors.black87),
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
                setState(() => _tool = t);
                if (t == EditorTool.slide) {
                  final p = context.read<SlideshowProject>();
                  if (!p.isPreviewReady && !p.isPreparingPreview) {
                    p.preparePreviewFrames();
                  }
                }
                if (t == EditorTool.music) context.push('/music');
              },
            ),
        ],
      ),
    );
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
      onClose: () => setState(() => _photoTool = null),
      onConfirm: () => setState(() => _photoTool = null),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
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
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
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

  Widget _photoBackgroundPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo, {
    bool compact = false,
  }) {
    const colors = <int?>[
      null,
      0xFFFFFFFF,
      0xFFBDBDBD,
      0xFF424242,
      0xFF000000,
      0xFFFFCDD2,
      0xFFFF8A80,
      0xFFFF5252,
      0xFF80DEEA,
      0xFF90CAF9,
      0xFFB39DDB,
      0xFFA5D6A7,
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 4 : 20),
      itemCount: colors.length,
      separatorBuilder: (_, _) => SizedBox(width: compact ? 8 : 12),
      itemBuilder: (context, i) {
        final color = colors[i];
        final active = photo.backgroundArgb == color;
        return InkWell(
          onTap: () => project.updatePhoto(
            index,
            color == null
                ? photo.copyWith(clearBackgroundArgb: true)
                : photo.copyWith(backgroundArgb: color),
          ),
          child: Column(
            children: [
              Container(
                width: compact ? 36 : 48,
                height: compact ? 36 : 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color == null ? Colors.white : Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? AppColors.primary : AppColors.border,
                    width: active ? 3 : 1,
                  ),
                ),
                child: color == null
                    ? const Icon(Icons.auto_awesome_motion, size: 18)
                    : null,
              ),
              SizedBox(height: compact ? 2 : 5),
              Text(
                color == null ? 'Default' : _backgroundName(color),
                style: TextStyle(fontSize: compact ? 9 : 10),
              ),
            ],
          ),
        );
      },
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
          _AnimationPhase.inAnimation => 'Slight zoom in',
          _ => 'Slight zoom',
        },
        PhotoAnimationType.zoomIn => 'Zoom in',
        PhotoAnimationType.zoomOut => 'Zoom out',
        PhotoAnimationType.shake => 'Shake 1',
        PhotoAnimationType.shake2 => 'Shake 2',
        PhotoAnimationType.mirror => switch (phase) {
          _AnimationPhase.inAnimation => 'Mirror in',
          _ => 'Mirror',
        },
        PhotoAnimationType.slideUp => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide up (inside)',
          _ => 'Slide up',
        },
        PhotoAnimationType.slideRight => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide right (inside)',
          _ => 'Slide right',
        },
        PhotoAnimationType.slideDown => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide down (inside)',
          _ => 'Slide down',
        },
        PhotoAnimationType.slideLeft => switch (phase) {
          _AnimationPhase.inAnimation => 'Slide left (inside)',
          _ => 'Slide left',
        },
        PhotoAnimationType.dynamicZoom => switch (phase) {
          _AnimationPhase.inAnimation => 'Dynamic zoom in',
          _ => 'Dynamic zoom',
        },
        PhotoAnimationType.dynamicZoomAlt => 'Dynamic zoom',
        PhotoAnimationType.wiper => 'Wipe',
        PhotoAnimationType.pendulum => 'Pendulum',
        PhotoAnimationType.upAndDown => 'Up and down',
        PhotoAnimationType.leftAndRight => 'Left and right',
        PhotoAnimationType.spinRight => 'Spin right (inside)',
        PhotoAnimationType.spinLeft => 'Spin left (inside)',
        PhotoAnimationType.spinUpper => 'Spin upper (inside)',
        PhotoAnimationType.mirrorOutside => 'Mirror (outside)',
        PhotoAnimationType.bottomOut => 'Bottom out',
        PhotoAnimationType.leftOut => 'Left out',
        PhotoAnimationType.rightOut => 'Right out',
        PhotoAnimationType.topOut => 'Top out',
        PhotoAnimationType.dynamicZoomOut => 'Dynamic zoom out',
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

  String _backgroundName(int color) => switch (color) {
    0xFFFFFFFF => 'White',
    0xFFBDBDBD => 'Gray',
    0xFF424242 => 'Dark',
    0xFF000000 => 'Black',
    0xFFFFCDD2 => 'Rose',
    0xFFFF8A80 => 'Coral',
    0xFFFF5252 => 'Red',
    0xFF80DEEA => 'Cyan',
    0xFF90CAF9 => 'Blue',
    0xFFB39DDB => 'Violet',
    0xFFA5D6A7 => 'Green',
    _ => 'Color',
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
      appBar: AppBar(
        title: const Text('Editor'),
        actions: [
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
      body: Column(
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
                          RepaintBoundary(
                            child: ValueListenableBuilder<Uint8List?>(
                              valueListenable: project.previewFrameListenable,
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
                                  );
                                }
                                return const Center(
                                  child: Text(
                                    'No preview',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                );
                              },
                            ),
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

          if (project.selectedPhotoIndex != null) ...[
            if (photoToolReplacesTimeline)
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
              )
            else
              _idleToolPanel(project),
            if (_photoTool == null)
              _photoEditorToolbar(project)
            else if (!photoToolReplacesTimeline)
              _photoEditSheet(project),
          ] else ...[
            if (_tool == null)
              _idleToolPanel(project)
            else
              SectionSheet(
                title: _toolLabel(_tool!),
                height: 180,
                headerRow: _previewRow(project),
                onClose: _dismissTool,
                onConfirm: _dismissTool,
                child: _buildPanel(project),
              ),

            _editorToolbar(),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
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
      EditorTool.effects => _EffectsPanel(project: project),
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
      EditorTool.music => const Center(
        child: Text(
          'Open Music from the toolbar',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
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

class _EffectsPanel extends StatelessWidget {
  const _EffectsPanel({required this.project});
  final SlideshowProject project;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: AppThemes.all.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final theme = AppThemes.all[i];
        final selected = project.selectedTheme.id == theme.id;
        return GestureDetector(
          onTap: () => project.selectTheme(theme),
          child: Container(
            width: 96,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
              color: selected ? AppColors.primarySoft : Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: selected ? AppColors.primary : AppColors.iconNormal,
                ),
                const Spacer(),
                Text(
                  theme.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
}

class _FramePanel extends StatelessWidget {
  const _FramePanel({required this.project, required this.onChanged});
  final SlideshowProject project;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final frames = FrameAsset.all;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: frames.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          final selected = project.selectedFrameAsset == null;
          return GestureDetector(
            onTap: () {
              project.selectFrame(null);
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
              ),
              child: const Text('None', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        final frame = frames[i - 1];
        final selected = project.selectedFrameAsset == frame.assetPath;
        return GestureDetector(
          onTap: () {
            project.selectFrame(frame.assetPath);
            onChanged();
          },
          child: Container(
            width: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(frame.assetPath, fit: BoxFit.cover),
          ),
        );
      },
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
        final motion = _thumbMotion(widget.type, t);
        return ClipRect(
          child: Opacity(
            opacity: motion.opacity,
            child: Transform.translate(
              offset: motion.offset,
              child: Transform.rotate(
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
  });

  final double opacity;
  final double scaleX;
  final double scaleY;
  final Offset offset;
  final double turns;
  final Alignment alignment;
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
      offset: Offset(math.sin(t * math.pi * 4) * 3, 0),
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
    PhotoAnimationType.dynamicZoom => _ThumbMotion(
      scaleX: 1 + 0.28 * t,
      scaleY: 1 + 0.28 * t,
    ),
    PhotoAnimationType.dynamicZoomAlt => _ThumbMotion(
      scaleX: 1.28 - 0.28 * t,
      scaleY: 1.28 - 0.28 * t,
    ),
    PhotoAnimationType.wiper => _ThumbMotion(
      offset: Offset((0.5 - t) * 20, 0),
    ),
    PhotoAnimationType.pendulum => _ThumbMotion(
      offset: Offset(math.sin(t * math.pi) * 10, 0),
    ),
    PhotoAnimationType.upAndDown => _ThumbMotion(
      offset: Offset(0, math.sin(t * math.pi * 2) * 6),
    ),
    PhotoAnimationType.leftAndRight => _ThumbMotion(
      offset: Offset(math.sin(t * math.pi * 2) * 12, 0),
    ),
    PhotoAnimationType.spinRight => _ThumbMotion(turns: (1 - t) * 0.25),
    PhotoAnimationType.spinLeft => _ThumbMotion(turns: -(1 - t) * 0.25),
    PhotoAnimationType.spinUpper => _ThumbMotion(scaleY: 0.2 + 0.8 * t),
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
    PhotoAnimationType.dynamicZoomOut => _ThumbMotion(
      scaleX: 0.45 + 0.55 * t,
      scaleY: 0.45 + 0.55 * t,
    ),
    PhotoAnimationType.flipLeft => _ThumbMotion(
      scaleX: math.max(0.05, t),
      alignment: Alignment.centerLeft,
    ),
    PhotoAnimationType.flipLower => _ThumbMotion(
      scaleY: math.max(0.05, t),
      alignment: Alignment.bottomCenter,
    ),
    PhotoAnimationType.flipRight => _ThumbMotion(
      scaleX: math.max(0.05, t),
      alignment: Alignment.centerRight,
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
    PhotoAnimationType.flyOutLeft => _ThumbMotion(
      opacity: 0.15 + 0.85 * t,
      scaleX: 0.4 + 0.6 * t,
      scaleY: 0.4 + 0.6 * t,
      offset: Offset(-(1 - t) * travel, 0),
    ),
    PhotoAnimationType.flyOutRight => _ThumbMotion(
      opacity: 0.15 + 0.85 * t,
      scaleX: 0.4 + 0.6 * t,
      scaleY: 0.4 + 0.6 * t,
      offset: Offset((1 - t) * travel, 0),
    ),
    PhotoAnimationType.flyOutUp => _ThumbMotion(
      opacity: 0.15 + 0.85 * t,
      scaleX: 0.4 + 0.6 * t,
      scaleY: 0.4 + 0.6 * t,
      offset: Offset(0, -(1 - t) * travel),
    ),
  };
}
