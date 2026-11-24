import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../core/responsive/app_responsive.dart';
import '../core/theme/app_theme.dart';
import '../widgets/editTool_sheet.dart';

enum VideoEditorTool {
  edit,
  text,
  music,
  effects,
  filters,
  sticker,
  aspectRatio,
  background,
}

/// CapCut-style video editor chrome with ClipCraft (slideshow) colors.
class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key, required this.videoPaths});

  final List<String> videoPaths;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  late List<String> _clips;
  VideoPlayerController? _controller;
  int _activeIndex = 0;
  bool _ready = false;
  bool _playing = false;
  VideoEditorTool? _tool;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _tick;
  double _aspectW = 9;
  double _aspectH = 16;
  int _filterIndex = 0;
  String? _musicTitle;
  String? _textOverlay;
  String? _stickerLabel;
  Color _bgColor = Colors.black;
  late final TextEditingController _textFieldController;

  static final _filters = <(String, ColorFilter?)>[
    ('Original', null),
    (
      'Warm',
      ColorFilter.matrix(<double>[
        1.1, 0.05, 0, 0, 8,
        0, 1.0, 0, 0, 4,
        0, 0, 0.9, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
    (
      'Cool',
      ColorFilter.matrix(<double>[
        0.9, 0, 0.05, 0, 0,
        0, 1.0, 0.05, 0, 0,
        0.05, 0, 1.15, 0, 10,
        0, 0, 0, 1, 0,
      ]),
    ),
    (
      'Mono',
      ColorFilter.matrix(<double>[
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
    (
      'Vivid',
      ColorFilter.matrix(<double>[
        1.2, 0, 0, 0, 0,
        0, 1.15, 0, 0, 0,
        0, 0, 1.1, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _clips = List<String>.from(widget.videoPaths);
    _textFieldController = TextEditingController();
    if (_clips.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No videos selected')),
        );
        context.pop();
      });
      return;
    }
    _loadClip(0);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _textFieldController.dispose();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadClip(int index) async {
    if (index < 0 || index >= _clips.length) return;
    _tick?.cancel();
    final old = _controller;
    old?.removeListener(_onVideoTick);
    setState(() {
      _ready = false;
      _playing = false;
      _activeIndex = index;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    final next = VideoPlayerController.file(File(_clips[index]));
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      next.addListener(_onVideoTick);
      await old?.dispose();
      _controller = next;
      setState(() {
        _ready = true;
        _duration = next.value.duration;
        _position = next.value.position;
      });
    } catch (_) {
      await next.dispose();
      if (!mounted) return;
      setState(() => _ready = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open video')),
      );
    }
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    setState(() {
      _position = v.position;
      _duration = v.duration;
      _playing = v.isPlaying;
    });
    if (v.isInitialized &&
        v.position >= v.duration &&
        v.duration > Duration.zero &&
        !v.isPlaying) {
      _playNextOrStop();
    }
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      if (c.value.position >= c.value.duration &&
          c.value.duration > Duration.zero) {
        await c.seekTo(Duration.zero);
      }
      await c.play();
    }
  }

  Future<void> _playNextOrStop() async {
    if (_activeIndex + 1 < _clips.length) {
      await _loadClip(_activeIndex + 1);
      await _controller?.play();
    } else {
      await _controller?.pause();
      await _controller?.seekTo(Duration.zero);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _selectTool(VideoEditorTool t) {
    setState(() => _tool = _tool == t ? null : t);
  }

  Future<void> _addMoreClips() async {
    final result = await context.push<List<String>>(
      '/gallery?type=video&insert=1',
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() => _clips.addAll(result));
  }

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final filter = _filters[_filterIndex].$2;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Editor'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: rs.w(12)),
            child: TealPillButton(
              label: 'Export',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Video export coming soon'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: _bgColor,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _aspectW / _aspectH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_ready && _controller != null)
                        _buildPlayer(filter)
                      else
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      if (_textOverlay != null && _textOverlay!.isNotEmpty)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _textOverlay!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: rs.sp(22),
                                fontWeight: FontWeight.w700,
                                shadows: const [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_stickerLabel != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _stickerLabel!,
                              style: TextStyle(fontSize: rs.sp(36)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildPlaybackBar(rs),
          _buildTimeline(rs),
          if (_tool != null) _buildToolPanel(rs),
          _buildBottomTools(rs),
        ],
      ),
    );
  }

  Widget _buildPlayer(ColorFilter? filter) {
    final player = FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
    if (filter == null) return player;
    return ColorFiltered(colorFilter: filter, child: player);
  }

  Widget _buildPlaybackBar(AppResponsive rs) {
    return Padding(
      padding: EdgeInsets.fromLTRB(rs.w(12), rs.h(8), rs.w(12), rs.h(4)),
      child: Row(
        children: [
          SizedBox(
            width: rs.w(96),
            child: Text(
              '${_fmt(_position)} / ${_fmt(_duration)}',
              style: TextStyle(
                fontSize: rs.sp(12),
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: IconButton(
                onPressed: _ready ? _togglePlay : null,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: rs.r(32),
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          SizedBox(
            width: rs.w(96),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.undo_rounded, color: AppColors.textMuted, size: rs.r(22)),
                SizedBox(width: rs.w(12)),
                Icon(Icons.redo_rounded, color: AppColors.textMuted, size: rs.r(22)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(AppResponsive rs) {
    final trackH = rs.h(56);
    return Container(
      height: rs.h(118),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.w(12),
                    vertical: rs.h(8),
                  ),
                  children: [
                    GestureDetector(
                      onTap: _addMoreClips,
                      child: Container(
                        width: trackH,
                        height: trackH,
                        margin: EdgeInsets.only(right: rs.w(8)),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(rs.r(8)),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 28),
                      ),
                    ),
                    for (var i = 0; i < _clips.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: rs.w(4)),
                          child: CircleAvatar(
                            radius: rs.r(10),
                            backgroundColor: AppColors.surfaceAlt,
                            child: Icon(
                              Icons.swap_horiz,
                              size: rs.r(12),
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _loadClip(i),
                        child: Container(
                          width: rs.w(88),
                          height: trackH,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(rs.r(8)),
                            border: Border.all(
                              color: i == _activeIndex
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: i == _activeIndex ? 2 : 1,
                            ),
                            color: AppColors.surfaceAlt,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Color(0xFF1C1C1E)),
                              Center(
                                child: Icon(
                                  Icons.videocam_rounded,
                                  color: Colors.white54,
                                  size: rs.r(22),
                                ),
                              ),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Text(
                                  'Clip ${i + 1}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: rs.sp(10),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    height: trackH + rs.h(8),
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(rs.w(12), 0, rs.w(12), rs.h(8)),
            child: Row(
              children: [
                _laneChip(
                  rs,
                  icon: Icons.music_note_outlined,
                  label: _musicTitle ?? '+ Add audio',
                  onTap: () => _selectTool(VideoEditorTool.music),
                ),
                SizedBox(width: rs.w(8)),
                _laneChip(
                  rs,
                  icon: Icons.text_fields,
                  label: _textOverlay ?? '+ Add text',
                  onTap: () => _selectTool(VideoEditorTool.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _laneChip(
    AppResponsive rs, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rs.r(8)),
        child: Container(
          height: rs.h(28),
          padding: EdgeInsets.symmetric(horizontal: rs.w(8)),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(rs.r(8)),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: rs.r(14), color: AppColors.textMuted),
              SizedBox(width: rs.w(6)),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: rs.sp(11),
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTools(AppResponsive rs) {
    return Container(
      height: rs.h(72),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: rs.w(8)),
        children: [
          for (final t in VideoEditorTool.values)
            EditorToolIcon(
              assetPath: _toolAsset(t),
              icon: _toolIcon(t),
              label: _toolLabel(t),
              selected: _tool == t,
              onTap: () => _selectTool(t),
            ),
        ],
      ),
    );
  }

  String _toolLabel(VideoEditorTool t) => switch (t) {
        VideoEditorTool.edit => 'Edit',
        VideoEditorTool.text => 'Text',
        VideoEditorTool.music => 'Music',
        VideoEditorTool.effects => 'Effects',
        VideoEditorTool.filters => 'Filters',
        VideoEditorTool.sticker => 'Sticker',
        VideoEditorTool.aspectRatio => 'Aspect Ratio',
        VideoEditorTool.background => 'Background',
      };

  String? _toolAsset(VideoEditorTool t) => switch (t) {
        VideoEditorTool.edit => null,
        VideoEditorTool.text => 'assets/images/editor/text.png',
        VideoEditorTool.music => 'assets/images/editor/music.png',
        VideoEditorTool.effects => 'assets/images/editor/effects.png',
        VideoEditorTool.filters => 'assets/images/editor/filter.png',
        VideoEditorTool.sticker => 'assets/images/editor/sticker.png',
        VideoEditorTool.aspectRatio => null,
        VideoEditorTool.background => 'assets/images/editor/bg.png',
      };

  IconData _toolIcon(VideoEditorTool t) => switch (t) {
        VideoEditorTool.edit => Icons.content_cut_rounded,
        VideoEditorTool.text => Icons.text_fields,
        VideoEditorTool.music => Icons.music_note_outlined,
        VideoEditorTool.effects => Icons.auto_awesome,
        VideoEditorTool.filters => Icons.filter_vintage_outlined,
        VideoEditorTool.sticker => Icons.emoji_emotions_outlined,
        VideoEditorTool.aspectRatio => Icons.aspect_ratio,
        VideoEditorTool.background => Icons.format_color_fill_outlined,
      };

  Widget _buildToolPanel(AppResponsive rs) {
    return Container(
      height: rs.h(150),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: switch (_tool!) {
        VideoEditorTool.edit => _editPanel(rs),
        VideoEditorTool.text => _textPanel(rs),
        VideoEditorTool.music => _musicPanel(rs),
        VideoEditorTool.effects => _effectsPanel(rs),
        VideoEditorTool.filters => _filtersPanel(rs),
        VideoEditorTool.sticker => _stickerPanel(rs),
        VideoEditorTool.aspectRatio => _ratioPanel(rs),
        VideoEditorTool.background => _bgPanel(rs),
      },
    );
  }

  Widget _panelHeader(AppResponsive rs, String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(rs.w(14), rs.h(10), rs.w(8), rs.h(4)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: rs.sp(14),
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _tool = null),
            icon: const Icon(Icons.check, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _editPanel(AppResponsive rs) {
    final actions = [
      (Icons.content_cut, 'Split', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Split coming soon')),
        );
      }),
      (Icons.content_copy_outlined, 'Duplicate', () {
        if (_clips.isEmpty) return;
        setState(() => _clips.insert(_activeIndex + 1, _clips[_activeIndex]));
      }),
      (Icons.delete_outline, 'Delete', () async {
        if (_clips.length <= 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keep at least one clip')),
          );
          return;
        }
        setState(() => _clips.removeAt(_activeIndex));
        await _loadClip(_activeIndex.clamp(0, _clips.length - 1));
      }),
      (Icons.speed, 'Speed', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speed coming soon')),
        );
      }),
      (Icons.volume_up_outlined, 'Volume', () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Volume coming soon')),
        );
      }),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Edit'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: actions.length,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(14)),
            itemBuilder: (context, i) {
              final a = actions[i];
              return InkWell(
                onTap: a.$3,
                child: SizedBox(
                  width: rs.w(64),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(a.$1, color: AppColors.textDark, size: rs.r(26)),
                      SizedBox(height: rs.h(6)),
                      Text(
                        a.$2,
                        style: TextStyle(
                          fontSize: rs.sp(11),
                          color: AppColors.textMuted,
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

  Widget _textPanel(AppResponsive rs) {
    return Column(
      children: [
        _panelHeader(rs, 'Text'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
          child: TextField(
            controller: _textFieldController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Add text overlay',
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(rs.r(10)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(
              () => _textOverlay = v.trim().isEmpty ? null : v,
            ),
          ),
        ),
      ],
    );
  }

  Widget _musicPanel(AppResponsive rs) {
    return Column(
      children: [
        _panelHeader(rs, 'Music'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
          child: Row(
            children: [
              Expanded(
                child: TealPillButton(
                  label: _musicTitle == null ? 'Add music' : 'Replace music',
                  onPressed: () async {
                    await context.push('/music');
                    if (!mounted) return;
                    setState(() => _musicTitle ??= 'Background music');
                  },
                ),
              ),
              if (_musicTitle != null) ...[
                SizedBox(width: rs.w(10)),
                IconButton(
                  onPressed: () => setState(() => _musicTitle = null),
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _effectsPanel(AppResponsive rs) {
    final effects = ['None', 'Glow', 'Zoom', 'Shake', 'Fade'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Effects'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: effects.length,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(10)),
            itemBuilder: (context, i) {
              final selected = i == 0;
              return Column(
                children: [
                  Container(
                    width: rs.w(64),
                    height: rs.w(64),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(rs.r(10)),
                      gradient: selected ? null : AppColors.primaryGradient,
                      color: selected ? AppColors.surfaceAlt : null,
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: selected ? AppColors.textMuted : Colors.white,
                    ),
                  ),
                  SizedBox(height: rs.h(4)),
                  Text(
                    effects[i],
                    style: TextStyle(fontSize: rs.sp(11), color: AppColors.textMuted),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filtersPanel(AppResponsive rs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Filters'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: _filters.length,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(10)),
            itemBuilder: (context, i) {
              final selected = _filterIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _filterIndex = i),
                child: Column(
                  children: [
                    Container(
                      width: rs.w(64),
                      height: rs.w(64),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(rs.r(10)),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.border,
                          width: selected ? 2 : 1,
                        ),
                        gradient: i == 0 ? null : AppColors.primaryGradient,
                        color: i == 0 ? AppColors.surfaceAlt : null,
                      ),
                      child: Icon(
                        Icons.filter_vintage_outlined,
                        color: i == 0 ? AppColors.textMuted : Colors.white,
                      ),
                    ),
                    SizedBox(height: rs.h(4)),
                    Text(
                      _filters[i].$1,
                      style: TextStyle(
                        fontSize: rs.sp(11),
                        color: AppColors.textMuted,
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

  Widget _stickerPanel(AppResponsive rs) {
    const stickers = ['😀', '🔥', '⭐', '❤️', '🎉', '✨', '👍', '🎵'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Sticker'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: stickers.length + 1,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(10)),
            itemBuilder: (context, i) {
              if (i == 0) {
                return GestureDetector(
                  onTap: () => setState(() => _stickerLabel = null),
                  child: Column(
                    children: [
                      Container(
                        width: rs.w(56),
                        height: rs.w(56),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(rs.r(10)),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text('None', style: TextStyle(fontSize: rs.sp(11))),
                      ),
                    ],
                  ),
                );
              }
              final s = stickers[i - 1];
              final selected = _stickerLabel == s;
              return GestureDetector(
                onTap: () => setState(() => _stickerLabel = s),
                child: Container(
                  width: rs.w(56),
                  height: rs.w(56),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(rs.r(10)),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Text(s, style: TextStyle(fontSize: rs.sp(26))),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ratioPanel(AppResponsive rs) {
    final ratios = <(String, double, double)>[
      ('9:16', 9, 16),
      ('16:9', 16, 9),
      ('1:1', 1, 1),
      ('4:5', 4, 5),
      ('4:3', 4, 3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Aspect Ratio'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: ratios.length,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(10)),
            itemBuilder: (context, i) {
              final r = ratios[i];
              final selected = _aspectW == r.$2 && _aspectH == r.$3;
              return GestureDetector(
                onTap: () => setState(() {
                  _aspectW = r.$2;
                  _aspectH = r.$3;
                }),
                child: Container(
                  width: rs.w(72),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(rs.r(10)),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                    color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
                  ),
                  child: Text(
                    r.$1,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      fontSize: rs.sp(13),
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

  Widget _bgPanel(AppResponsive rs) {
    final colors = [
      Colors.black,
      Colors.white,
      const Color(0xFF1A237E),
      const Color(0xFF212121),
      const Color(0xFF26EBD7),
      const Color(0xFF33B5F1),
      const Color(0xFFFF7043),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader(rs, 'Background'),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: rs.w(14)),
            itemCount: colors.length,
            separatorBuilder: (_, _) => SizedBox(width: rs.w(10)),
            itemBuilder: (context, i) {
              final c = colors[i];
              final selected = _bgColor == c;
              return GestureDetector(
                onTap: () => setState(() => _bgColor = c),
                child: Container(
                  width: rs.w(48),
                  height: rs.w(48),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 3 : 1,
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
}
