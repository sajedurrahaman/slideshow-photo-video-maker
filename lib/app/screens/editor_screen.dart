import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import '../widgets/app_chrome.dart';

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
  EditorTool _tool = EditorTool.slide;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SlideshowProject>().refreshLivePreview();
    });
  }

  @override
  void dispose() {
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                    ),
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
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.low,
                                  );
                                }
                                if (project.photos.isNotEmpty) {
                                  return Image.file(
                                    File(project.photos.first.path),
                                    fit: BoxFit.cover,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _tool == EditorTool.slide
                ? Row(
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: project.previewPositionListenable,
                        builder: (_, pos, _) => Text(
                          '${_fmt(pos)} / ${_fmt(project.estimatedDurationSec)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: IconButton(
                            onPressed: (project.isProcessing ||
                                    project.isPreparingPreview)
                                ? null
                                : _preview,
                            icon: Icon(
                              project.isPreviewPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            iconSize: 32,
                            color: project.isPreviewReady
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ),
                      const SizedBox(width: 64),
                    ],
                  )
                : Row(
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: project.previewPositionListenable,
                        builder: (_, pos, _) => Text(
                          '${_fmt(pos)} / ${_fmt(project.estimatedDurationSec)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: (project.isProcessing ||
                                project.isPreparingPreview)
                            ? null
                            : _preview,
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
                  ),
          ),
          // Thumbnail strip hidden while Slide tool is open (ref design).
          if (_tool != EditorTool.slide)
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: project.photos.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  if (i == project.photos.length) {
                    return GestureDetector(
                      onTap: () => context.push('/gallery'),
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: const Icon(Icons.add, color: AppColors.primary),
                      ),
                    );
                  }
                  final photo = project.photos[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(photo.path),
                          width: 56,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => project.removePhoto(i),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.remove,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          // Tool panel
          if (_tool == EditorTool.slide)
            _SlidePanel(
              project: project,
              onClose: () {},
              onConfirm: () => project.refreshLivePreview(),
            )
          else
            SectionSheet(
              title: _toolLabel(_tool),
              height: _panelHeight(_tool),
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

  double _panelHeight(EditorTool tool) => switch (tool) {
    EditorTool.text => 200,
    EditorTool.starting || EditorTool.ending => 210,
    _ => 160,
  };

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
    return switch (_tool) {
      EditorTool.slide => const SizedBox.shrink(),
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

/// Figma-style Slide sheet: close / title / check + transition tiles.
class _SlidePanel extends StatelessWidget {
  const _SlidePanel({
    required this.project,
    required this.onClose,
    required this.onConfirm,
  });

  final SlideshowProject project;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final options = SlideTransitionOption.all;
    final selectedId = project.selectedSlideTransition.id;

    return Container(
      height: 150,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 22),
                  color: AppColors.textMuted,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Slide',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4FC3F7),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 48,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4FC3F7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check, size: 24),
                  color: const Color(0xFF4FC3F7),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(4),
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final option = options[i];
                final selected = option.id == selectedId;
                const accent = Color(0xFF4FC3F7);
                return GestureDetector(
                  onTap: () => project.selectSlideTransition(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(4),
                    child: option.isNone
                        ? Image.asset(
                            "assets/images/editor/transitions/default.png",
                            fit: BoxFit.contain,
                            color: selected ? accent : null,
                            colorBlendMode: selected ? BlendMode.srcIn : null,
                            filterQuality: FilterQuality.medium,
                          )
                        : Image.asset(
                            option.assetPath!,
                            fit: BoxFit.contain,
                            color: selected ? accent : null,
                            colorBlendMode: selected ? BlendMode.srcIn : null,
                            filterQuality: FilterQuality.medium,
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
