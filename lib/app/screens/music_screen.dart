import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import '../widgets/editTool_sheet.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  String? _playingPath;
  late final TabController _tabs;

  static const _builtin = [
    MusicTrack(path: 'assets/music/songs_1.mp3', title: 'Popular Beat', isAsset: true),
    MusicTrack(path: 'assets/music/songs_2.mp3', title: 'Soft Piano', isAsset: true),
    MusicTrack(path: 'assets/music/songs_3.mp3', title: 'Upbeat Pop', isAsset: true),
    MusicTrack(path: 'assets/music/songs_4.mp3', title: 'Chill Wave', isAsset: true),
    MusicTrack(path: 'assets/music/songs_5.mp3', title: 'Cinematic', isAsset: true),
    MusicTrack(path: 'assets/music/songs_6.mp3', title: 'Happy Day', isAsset: true),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview(MusicTrack track) async {
    try {
      if (_playingPath == track.path && _player.playing) {
        await _player.stop();
        setState(() => _playingPath = null);
        return;
      }
      if (track.isAsset) {
        await _player.setAsset(track.path);
      } else {
        await _player.setFilePath(track.path);
      }
      await _player.setVolume((track.volume / 100).clamp(0.0, 1.0));
      await _player.play();
      setState(() => _playingPath = track.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playback failed: $e')),
      );
    }
  }

  Future<void> _pickDeviceMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final track = MusicTrack(
      path: path,
      title: result.files.single.name,
    );
    if (!mounted) return;
    context.read<SlideshowProject>().setMusic(track);
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<SlideshowProject>();
    final selected = project.music;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Music'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TealPillButton(
              label: 'Done',
              onPressed: () => context.pop(),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Popular'),
            Tab(text: 'My Music'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _MusicTile(
                      title: 'No music',
                      icon: Icons.music_off_outlined,
                      selected: selected == null,
                      onTap: () {
                        _player.stop();
                        project.setMusic(null);
                        setState(() => _playingPath = null);
                      },
                    ),
                    const SizedBox(height: 8),
                    ..._builtin.map((track) {
                      final isSel = selected?.path == track.path;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MusicTile(
                          title: track.title,
                          icon: Icons.library_music_outlined,
                          selected: isSel,
                          playing: _playingPath == track.path,
                          onTap: () => project.setMusic(track),
                          onPlay: () => _preview(track),
                        ),
                      );
                    }),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _MusicTile(
                      title: 'Pick from device',
                      icon: Icons.folder_open_outlined,
                      selected: false,
                      onTap: _pickDeviceMusic,
                    ),
                    if (selected != null && !selected.isAsset) ...[
                      const SizedBox(height: 8),
                      _MusicTile(
                        title: selected.title,
                        icon: Icons.audiotrack,
                        selected: true,
                        playing: _playingPath == selected.path,
                        onTap: () {},
                        onPlay: () => _preview(selected),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (selected != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Volume ${selected.volume}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Slider(
                    value: selected.volume.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (v) {
                      project.setMusicVolume(v.round());
                      _player.setVolume((v / 100).clamp(0.0, 1.0));
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MusicTile extends StatelessWidget {
  const _MusicTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onPlay,
    this.playing = false,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: selected ? AppColors.primary : AppColors.iconNormal,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primaryDark : AppColors.textDark,
          ),
        ),
        trailing: onPlay == null
            ? null
            : IconButton(
                onPressed: onPlay,
                icon: Icon(
                  playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                  color: AppColors.primary,
                ),
              ),
      ),
    );
  }
}
