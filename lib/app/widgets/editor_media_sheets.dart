import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import 'editTool_sheet.dart';

/// CapCut-style Text sheet for video editor (same chrome as slideshow).
class EditorTextToolSheet extends StatelessWidget {
  const EditorTextToolSheet({
    super.key,
    required this.height,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.onConfirm,
    required this.onChanged,
  });

  final double height;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SectionSheet(
      title: 'Text',
      height: height,
      compactHeader: true,
      showTopDivider: false,
      onClose: onClose,
      onConfirm: onConfirm,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              onChanged: onChanged,
              onSubmitted: (_) => onConfirm(),
              decoration: InputDecoration(
                hintText: 'Enter text',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap ✓ to place text on the preview',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slideshow-matching Music picker (My Music / Local + track strip).
class EditorMusicPickerSheet extends StatefulWidget {
  const EditorMusicPickerSheet({
    super.key,
    required this.height,
    required this.selected,
    required this.localTracks,
    required this.onClose,
    required this.onConfirm,
    required this.onSelect,
    required this.onOpenLibrary,
    required this.onImportLocal,
    /// When true, parent owns preview+BGM (video editor). Sheet only selects.
    this.syncWithHostPreview = false,
    this.hostPlaying = false,
    this.onRetapSelected,
  });

  final double height;
  final MusicTrack? selected;
  final List<MusicTrack> localTracks;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final ValueChanged<MusicTrack?> onSelect;
  final VoidCallback onOpenLibrary;
  final VoidCallback onImportLocal;
  final bool syncWithHostPreview;
  final bool hostPlaying;
  final VoidCallback? onRetapSelected;

  @override
  State<EditorMusicPickerSheet> createState() => _EditorMusicPickerSheetState();
}

enum _MusicSourceTab { myMusic, local }

class _EditorMusicPickerSheetState extends State<EditorMusicPickerSheet> {
  _MusicSourceTab _source = _MusicSourceTab.myMusic;
  final AudioPlayer _preview = AudioPlayer();
  String? _previewPath;
  bool _playing = false;

  @override
  void dispose() {
    unawaited(_preview.dispose());
    super.dispose();
  }

  Future<void> _stopPreview() async {
    try {
      await _preview.stop();
    } catch (_) {}
    if (!mounted) {
      _previewPath = null;
      _playing = false;
      return;
    }
    setState(() {
      _previewPath = null;
      _playing = false;
    });
  }

  Future<void> _onTrackTap(MusicTrack track) async {
    final isSel = widget.selected?.path == track.path;

    // Video editor: music is mixed into the main preview — no second player.
    if (widget.syncWithHostPreview) {
      if (isSel) {
        widget.onRetapSelected?.call();
        return;
      }
      widget.onSelect(track);
      return;
    }

    if (isSel && _playing && _previewPath == track.path) {
      await _preview.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    widget.onSelect(track);
    try {
      if (_previewPath != track.path) {
        if (track.isAsset) {
          await _preview.setAsset(track.path);
        } else {
          await _preview.setFilePath(track.path);
        }
        _previewPath = track.path;
      }
      await _preview.play();
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = _source == _MusicSourceTab.local;
    final tracks = isLocal ? widget.localTracks : MusicTrack.popular;
    final selected = widget.selected;
    final playing = widget.syncWithHostPreview ? widget.hostPlaying : _playing;

    return SizedBox(
      height: widget.height,
      child: ColoredBox(
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
                // Slideshow parity: My Music → None + tracks; Local → Import + tracks.
                itemCount: tracks.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    if (isLocal) {
                      return _MusicThumbTile(
                        title: 'Import',
                        selected: false,
                        onTap: widget.onImportLocal,
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
                    final noneSel = selected == null;
                    return _MusicThumbTile(
                      title: 'None',
                      selected: noneSel,
                      onTap: () async {
                        await _stopPreview();
                        widget.onSelect(null);
                      },
                      child: SizedBox(
                        width: 58,
                        child: Center(
                          child: Icon(
                            Icons.music_off_outlined,
                            color: noneSel
                                ? AppColors.primary
                                : AppColors.textMuted,
                            size: 28,
                          ),
                        ),
                      ),
                    );
                  }
                  final track = tracks[index - 1];
                  final isSel = selected?.path == track.path;
                  final isPlaying = isSel && playing;
                  return _MusicThumbTile(
                    title: track.title,
                    selected: isSel,
                    onTap: () => unawaited(_onTrackTap(track)),
                    child: SizedBox(
                      width: 58,
                      child: Center(
                        child: Icon(
                          isSel
                              ? (isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded)
                              : Icons.library_music,
                          color: isSel
                              ? AppColors.iconActive
                              : AppColors.textDark,
                          size: 28,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slideshow-matching Effects picker (horizontal FX thumbs).
class EditorEffectsPickerSheet extends StatelessWidget {
  const EditorEffectsPickerSheet({
    super.key,
    required this.height,
    required this.selectedId,
    required this.onClose,
    required this.onConfirm,
    required this.onSelect,
  });

  final double height;
  final String? selectedId;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final ValueChanged<OverlayEffect?> onSelect;

  @override
  Widget build(BuildContext context) {
    final effects = OverlayEffect.all;
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: AppColors.textDark),
                  ),
                  const Expanded(child: Center(child: SheetTitle('Effects'))),
                  IconButton(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: effects.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    final noneSel = selectedId == null;
                    return _EffectTile(
                      label: 'None',
                      selected: noneSel,
                      onTap: () => onSelect(null),
                      child: const ColoredBox(
                        color: Color(0xFF2C2C2E),
                        child: Center(
                          child: Icon(
                            Icons.block,
                            color: Colors.white54,
                            size: 28,
                          ),
                        ),
                      ),
                    );
                  }
                  final effect = effects[i - 1];
                  final isSel = selectedId == effect.id;
                  return _EffectTile(
                    label: effect.name,
                    selected: isSel,
                    onTap: () => onSelect(effect),
                    child: Image.asset(
                      effect.thumbPath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.black,
                        child: Icon(Icons.auto_awesome, color: Colors.white54),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
            gradient: selected ? AppColors.primaryGradient : null,
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.23),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: PrimarySelectedBorder(
                  selected: selected,
                  borderRadius: 10,
                  width: 2,
                  backgroundColor: Colors.white,
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 6),
            selected
                ? PrimaryGradientMask(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _EffectTile extends StatelessWidget {
  const _EffectTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            SizedBox(
              width: 88,
              height: 72,
              child: PrimarySelectedBorder(
                selected: selected,
                borderRadius: 2,
                width: 2,
                backgroundColor: Colors.black,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: child,
                ),
              ),
            ),
            const SizedBox(height: 6),
            selected
                ? PrimaryGradientMask(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppColors.textDark,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
