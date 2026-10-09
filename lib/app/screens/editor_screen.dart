import 'dart:io';
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

enum _AnimationPhase { inAnimation, outAnimation, loop }

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
  final _textController = TextEditingController();
  final _stripController = ScrollController();

  static const _sheetHeight = 180.0;
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

  Widget _idleToolPanel(SlideshowProject project) {
    return Container(
      height: _sheetHeight,
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
                  Padding(
                    padding: const EdgeInsets.only(left: 14, right: 6),
                    child: _idlePreviewRow(project),
                  ),
                  Expanded(child: _photoStrip(project, playheadX)),
                ],
              ),
              // Playhead — same X as the centered play button, through the strip.
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

    return Stack(
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
                                      onTap: () => project.changePhotoDuration(
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
                                      onTap: () => project.changePhotoDuration(
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
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (photoIndex > 0 && project.selectedPhotoIndex == null)
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
      height: 72,
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
                          Image.asset(
                            'assets/images/editor/photo_tools/${action.iconAsset}',
                            width: 28,
                            height: 28,
                            color: AppColors.iconNormal,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                          const SizedBox(height: 4),
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

  Widget _photoEditSheet(SlideshowProject project) {
    final index = project.selectedPhotoIndex;
    if (index == null || index >= project.photos.length) {
      return const SizedBox.shrink();
    }
    final photo = project.photos[index];
    final tool = _photoTool!;
    final height = tool == _PhotoTool.animation ? 220.0 : 180.0;
    return SectionSheet(
      title: _photoToolLabel(tool),
      height: height,
      onClose: () => setState(() => _photoTool = null),
      onConfirm: () => setState(() => _photoTool = null),
      child: switch (tool) {
        _PhotoTool.duration => _photoDurationPanel(project, index, photo),
        _PhotoTool.animation => _photoAnimationPanel(project, index, photo),
        _PhotoTool.background => _photoBackgroundPanel(project, index, photo),
        _PhotoTool.crop => _photoCropPanel(project, index, photo),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _photoDurationPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo,
  ) {
    final duration = _durationSliderValue ?? photo.durationSec;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
    SlideshowPhoto photo,
  ) {
    final selected = switch (_animationPhase) {
      _AnimationPhase.inAnimation => photo.animationIn,
      _AnimationPhase.outAnimation => photo.animationOut,
      _AnimationPhase.loop => photo.animationLoop,
    };
    final options = PhotoAnimationType.values;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final phase in _AnimationPhase.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextButton(
                  onPressed: () => setState(() => _animationPhase = phase),
                  child: Text(
                    switch (phase) {
                      _AnimationPhase.inAnimation => 'In',
                      _AnimationPhase.outAnimation => 'Out',
                      _AnimationPhase.loop => 'Loop',
                    },
                    style: TextStyle(
                      color: _animationPhase == phase
                          ? AppColors.primary
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                    _AnimationPhase.loop => photo.copyWith(
                      animationLoop: animation,
                    ),
                  };
                  project.updatePhoto(index, updated);
                },
                child: SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primarySoft
                              : AppColors.surfaceAlt,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _animationIcon(animation),
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.iconNormal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _animationLabel(animation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? AppColors.primaryDark
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _photoBackgroundPanel(
    SlideshowProject project,
    int index,
    SlideshowPhoto photo,
  ) {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: colors.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
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
                width: 48,
                height: 48,
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
              const SizedBox(height: 5),
              Text(
                color == null ? 'Default' : _backgroundName(color),
                style: const TextStyle(fontSize: 10),
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

  String _animationLabel(PhotoAnimationType animation) => switch (animation) {
    PhotoAnimationType.none => 'None',
    PhotoAnimationType.fade => 'Fade',
    PhotoAnimationType.slightZoom => 'Slight zoom',
    PhotoAnimationType.zoomIn => 'Zoom in',
    PhotoAnimationType.zoomOut => 'Zoom out',
    PhotoAnimationType.shake => 'Shake',
    PhotoAnimationType.slideUp => 'Slide up',
    PhotoAnimationType.slideRight => 'Slide right',
    PhotoAnimationType.slideDown => 'Slide down',
  };

  IconData _animationIcon(PhotoAnimationType animation) => switch (animation) {
    PhotoAnimationType.none => Icons.block,
    PhotoAnimationType.fade => Icons.gradient,
    PhotoAnimationType.slightZoom => Icons.zoom_out_map,
    PhotoAnimationType.zoomIn => Icons.zoom_in,
    PhotoAnimationType.zoomOut => Icons.zoom_out,
    PhotoAnimationType.shake => Icons.vibration,
    PhotoAnimationType.slideUp => Icons.keyboard_arrow_up,
    PhotoAnimationType.slideRight => Icons.keyboard_arrow_right,
    PhotoAnimationType.slideDown => Icons.keyboard_arrow_down,
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
            _idleToolPanel(project),
            if (_photoTool == null)
              _photoEditorToolbar(project)
            else
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
