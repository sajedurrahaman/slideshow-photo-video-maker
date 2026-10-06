import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditorTool? _tool = EditorTool.slide;
  final _textController = TextEditingController();
  final _stripController = ScrollController();

  static const _sheetHeight = 180.0;
  static const _plusW = 52.0;
  static const _plusGap = 12.0;
  static const _thumbW = 88.0;
  static const _thumbH = 68.0;
  static const _minus = 22.0;
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
    final playheadX = MediaQuery.sizeOf(context).width / 2;
    _syncStripToPlayhead(
      project: project,
      playheadX: playheadX,
      thumbsLeft: 0,
    );
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

  Widget _timeText(SlideshowProject project) {
    return ValueListenableBuilder<double>(
      valueListenable: project.previewPositionListenable,
      builder: (_, pos, _) => Text(
        '${_fmt(pos)} / ${_fmt(project.estimatedDurationSec)}',
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
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
              color: Colors.black87,
            ),
          ),
        ),
        IconButton(
          onPressed: project.canUndo ? () => project.undo() : null,
          icon: Icon(
            Icons.undo_rounded,
            color: project.canUndo ? Colors.black87 : Colors.black26,
          ),
        ),
        IconButton(
          onPressed: project.canRedo ? () => project.redo() : null,
          icon: Icon(
            Icons.redo_rounded,
            color: project.canRedo ? Colors.black87 : Colors.black26,
          ),
        ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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

  void _syncStripToPlayhead({
    required SlideshowProject project,
    required double playheadX,
    required double thumbsLeft,
  }) {
    if (!_stripController.hasClients) return;
    final n = project.photos.length;
    final duration = project.estimatedDurationSec;
    if (n == 0 || duration <= 0) return;
    final p = (project.previewPositionSec / duration).clamp(0.0, 1.0);
    final target = p * (n * _thumbW);
    final max = _stripController.position.maxScrollExtent;
    final next = target.clamp(0.0, max);
    if ((_stripController.offset - next).abs() < 0.5) return;
    _stripController.jumpTo(next);
  }

  Widget _photoStrip(SlideshowProject project, double playheadX) {
    final thumbsLeft = _stripPadLeft + _plusW + _plusGap;
    final leftPad = (playheadX - thumbsLeft).clamp(0.0, 400.0);

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: _stripPadLeft),
          child: GestureDetector(
            onTap: () => context.push('/gallery'),
            child: Container(
              width: _plusW,
              height: _thumbH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(width: _plusGap),
        Expanded(
          child: ListView.builder(
            controller: _stripController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            physics: project.isPreviewPlaying
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(leftPad, 30, playheadX, 30.5),
            itemCount: project.photos.length,
            itemBuilder: (context, photoIndex) {
              final photo = project.photos[photoIndex];
              return SizedBox(
                width: _thumbW,
                height: _thumbH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.5),
                          child: Image.file(
                            File(photo.path),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    if (photoIndex > 0)
                      Positioned(
                        left: -_minus / 2,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: () => project.removePhoto(photoIndex),
                            child: Container(
                              width: _minus,
                              height: _minus,
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
                                Icons.remove,
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
        ),
      ],
    );
  }

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

          // Bottom toolbar
          Container(
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
                      if (t == EditorTool.music) {
                        context.push('/music');
                      }
                    },
                  ),
              ],
            ),
          ),
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
