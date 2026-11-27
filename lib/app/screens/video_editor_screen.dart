import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/responsive/app_responsive.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/effect_overlay_service.dart';
import '../services/text_overlay_host.dart';
import '../widgets/editTool_sheet.dart';
import '../widgets/editor_media_sheets.dart';
import '../widgets/preparing_preview_overlay.dart';
import '../widgets/text_tools_sheet.dart';
import 'video_resize_screen.dart';

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

/// Tools shown when a timeline clip is selected (CapCut-style).
enum _ClipEditTool { volume, animation, delete, speed, crop, replace }

enum _VideoAnimPhase { inAnimation, outAnimation }

/// CapCut-style opening reveal overlays (applied at clip start).
class VideoRevealAnim {
  const VideoRevealAnim({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.thumbPath,
    required this.durationSec,
    this.portalReveal = false,
    this.alphaMatteAssetPath,
  });

  final String id;
  final String name;
  final String assetPath;
  final String thumbPath;
  final double durationSec;

  /// Legacy flag (unused — all In FX use color + alpha matte like Leaf Reveal).
  final bool portalReveal;

  /// Grayscale alpha matte paired with [assetPath] (Leaf Reveal pattern).
  final String? alphaMatteAssetPath;

  /// CapCut In tab: color + alpha matte → srcOver over the clip.
  static const catalog = <VideoRevealAnim>[
    VideoRevealAnim(
      id: 'fx_01',
      name: 'Leaf Reveal',
      assetPath: 'assets/animations/fx_01_leaf_reveal.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_01_leaf_reveal_alpha.mp4',
      thumbPath: 'assets/animations/fx_01_leaf_reveal_thumb.png',
      durationSec: 2.0,
    ),
    VideoRevealAnim(
      id: 'fx_02',
      name: 'Portal Burst',
      assetPath: 'assets/animations/fx_02_portal_burst.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_02_portal_burst_alpha.mp4',
      thumbPath: 'assets/animations/fx_02_portal_burst_thumb.jpg',
      // Black cover outside + transparent hole inside + CapCut-style fire vortex.
      portalReveal: true,
      durationSec: 2.4,
    ),
    VideoRevealAnim(
      id: 'fx_03',
      name: 'Balloon Rise',
      assetPath: 'assets/animations/fx_03_balloon_rise.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_03_balloon_rise_alpha.mp4',
      thumbPath: 'assets/animations/fx_03_balloon_rise_thumb.png',
      // Full-screen balloons → float up → clear.
      durationSec: 2.2,
    ),
    VideoRevealAnim(
      id: 'fx_04',
      name: 'Dollar Rain',
      assetPath: 'assets/animations/fx_04_dollar_rain.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_04_dollar_rain_alpha.mp4',
      thumbPath: 'assets/animations/fx_04_dollar_rain_thumb.png',
      // Full-screen dollars → fall down → clear.
      durationSec: 2.2,
    ),
  ];

  /// CapCut Out tab: play at clip end (clear → cover).
  static const outCatalog = <VideoRevealAnim>[
    VideoRevealAnim(
      id: 'fx_out_01',
      name: 'Glitch Static',
      assetPath: 'assets/animations/fx_out_01_glitch_static.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_out_01_glitch_static_alpha.mp4',
      thumbPath: 'assets/animations/fx_out_01_glitch_static_thumb.png',
      durationSec: 2.0,
    ),
    VideoRevealAnim(
      id: 'fx_out_02',
      name: 'Valentine',
      assetPath: 'assets/animations/fx_out_02_valentine.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_out_02_valentine_alpha.mp4',
      thumbPath: 'assets/animations/fx_out_02_valentine_thumb.png',
      durationSec: 2.0,
    ),
    VideoRevealAnim(
      id: 'fx_out_03',
      name: 'New Year',
      assetPath: 'assets/animations/fx_out_03_new_year.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_out_03_new_year_alpha.mp4',
      thumbPath: 'assets/animations/fx_out_03_new_year_thumb.png',
      durationSec: 2.0,
    ),
    VideoRevealAnim(
      id: 'fx_out_04',
      name: 'Leaf Cover',
      assetPath: 'assets/animations/fx_out_04_leaf_cover.mp4',
      alphaMatteAssetPath: 'assets/animations/fx_out_04_leaf_cover_alpha.mp4',
      thumbPath: 'assets/animations/fx_out_04_leaf_cover_thumb.png',
      durationSec: 2.0,
    ),
  ];

  static VideoRevealAnim? byId(String? id) {
    if (id == null) return null;
    for (final a in catalog) {
      if (a.id == id) return a;
    }
    for (final a in outCatalog) {
      if (a.id == id) return a;
    }
    return null;
  }
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

  /// Null = deselected (initial). Selected → CapCut white handles + clip tools bar.
  int? _selectedClipIndex;
  bool _ready = false;
  bool _playing = false;
  VideoEditorTool? _tool;

  /// Trim window per clip index (CapCut cut/resize). Null = natural edge.
  final List<double?> _clipTrimIn = [];
  final List<double?> _clipTrimOut = [];
  double? _liveTrimIn;
  double? _liveTrimOut;
  bool _trimDragging = false;

  /// Original clip audio level per index (0.0–1.0).
  final List<double> _clipVolumes = [];

  /// Per-clip speed (duration-capped). Timeline length = source / speed.
  final List<double> _clipSpeeds = [];

  /// CapCut “Change audio pitch” per clip (UI + export hint).
  final List<bool> _clipChangePitch = [];

  /// CapCut Resize (crop/rotate) per clip — null = identity.
  final List<VideoClipCrop?> _clipCrops = [];

  /// Opening reveal animation id per clip (null = none). CapCut “In”.
  final List<String?> _clipRevealIds = [];

  /// User duration for In-anim (CapCut slider). Null = asset default.
  final List<double?> _clipRevealDurSec = [];

  /// Ending reveal animation id per clip (null = none). CapCut “Out”.
  final List<String?> _clipOutRevealIds = [];

  /// User duration for Out-anim. Null = asset default.
  final List<double?> _clipOutRevealDurSec = [];
  double? _revealDurDrag;
  bool _animSheetOpen = false;
  /// CapCut Speed sheet — same inline green-area pattern as Animation.
  bool _speedSheetOpen = false;
  double _speedDraft = 1.0;
  bool _pitchDraft = false;
  double _speedCommittedOnOpen = 1.0;
  bool _pitchCommittedOnOpen = false;
  bool _speedPreviewLoading = false;
  bool _speedPreviewReady = true;
  int _speedPrepareGen = 0;
  _VideoAnimPhase _animPhase = _VideoAnimPhase.inAnimation;

  bool get _clipEditorSheetOpen => _animSheetOpen || _speedSheetOpen;

  /// CapCut In-anim: disk frames + decoded ui.Images (smooth, no Image.file blink).
  final Map<String, String> _revealAssetFiles = {};
  final Map<String, List<String>> _revealFrameFiles = {};
  final Map<String, Future<List<String>>> _revealFrameJobs = {};
  final Map<String, List<ui.Image>> _revealImages = {};
  final Map<String, Future<List<ui.Image>>> _revealImageJobs = {};
  bool _revealOverlayActive = false;
  String? _activeRevealId;
  int _revealFrameIndex = 0;

  /// Frame index only — avoids rebuilding the whole editor every FX tick.
  final ValueNotifier<int> _revealFrameTick = ValueNotifier(0);

  /// True after last clip finishes — stay on last frame (don't loop seek→In).
  bool _stoppedAtClipEnd = false;

  /// CapCut Animation sheet: prepare FX → loading → ready → play only FX window.
  bool _animPreviewLoading = false;
  bool _animPreviewReady = false;
  bool _animPreviewPlaying = false;
  int _animPreviewGen = 0;

  bool get _hasAnimSheetSelection {
    final sel = _selectedClipIndex;
    if (sel == null) return false;
    if (_animPhase == _VideoAnimPhase.outAnimation) {
      return sel < _clipOutRevealIds.length && _clipOutRevealIds[sel] != null;
    }
    return sel < _clipRevealIds.length && _clipRevealIds[sel] != null;
  }

  bool get _playButtonEnabled {
    if (!_ready || _animPreviewLoading || _speedPreviewLoading) return false;
    // After speed change, stay disabled until prepare finishes (even if sheet closed).
    if (!_speedPreviewReady) return false;
    // Music picker: audition only — top play stays off until ✓ commits.
    if (_tool == VideoEditorTool.music) return false;
    if (_animSheetOpen && _hasAnimSheetSelection) return _animPreviewReady;
    return true;
  }

  void _clearAnimPreviewState({bool stopOverlay = false}) {
    _animPreviewGen++;
    _animPreviewLoading = false;
    _animPreviewReady = false;
    _animPreviewPlaying = false;
    if (stopOverlay) _stopRevealOverlay();
  }

  void _ensureTrimSlots() {
    while (_clipTrimIn.length < _clips.length) {
      _clipTrimIn.add(null);
      _clipTrimOut.add(null);
    }
    while (_clipTrimIn.length > _clips.length) {
      _clipTrimIn.removeLast();
      _clipTrimOut.removeLast();
    }
    while (_clipVolumes.length < _clips.length) {
      _clipVolumes.add(1.0);
    }
    while (_clipVolumes.length > _clips.length) {
      _clipVolumes.removeLast();
    }
    while (_clipSpeeds.length < _clips.length) {
      _clipSpeeds.add(1.0);
    }
    while (_clipSpeeds.length > _clips.length) {
      _clipSpeeds.removeLast();
    }
    while (_clipChangePitch.length < _clips.length) {
      _clipChangePitch.add(false);
    }
    while (_clipChangePitch.length > _clips.length) {
      _clipChangePitch.removeLast();
    }
    while (_clipRevealIds.length < _clips.length) {
      _clipRevealIds.add(null);
      _clipRevealDurSec.add(null);
    }
    while (_clipRevealIds.length > _clips.length) {
      _clipRevealIds.removeLast();
      if (_clipRevealDurSec.isNotEmpty) _clipRevealDurSec.removeLast();
    }
    while (_clipRevealDurSec.length < _clips.length) {
      _clipRevealDurSec.add(null);
    }
    while (_clipRevealDurSec.length > _clips.length) {
      _clipRevealDurSec.removeLast();
    }
    while (_clipOutRevealIds.length < _clips.length) {
      _clipOutRevealIds.add(null);
      _clipOutRevealDurSec.add(null);
    }
    while (_clipOutRevealIds.length > _clips.length) {
      _clipOutRevealIds.removeLast();
      if (_clipOutRevealDurSec.isNotEmpty) _clipOutRevealDurSec.removeLast();
    }
    while (_clipOutRevealDurSec.length < _clips.length) {
      _clipOutRevealDurSec.add(null);
    }
    while (_clipOutRevealDurSec.length > _clips.length) {
      _clipOutRevealDurSec.removeLast();
    }
    while (_clipCrops.length < _clips.length) {
      _clipCrops.add(null);
    }
    while (_clipCrops.length > _clips.length) {
      _clipCrops.removeLast();
    }
  }

  VideoClipCrop? _cropFor(int index) {
    _ensureTrimSlots();
    if (index < 0 || index >= _clipCrops.length) return null;
    return _clipCrops[index];
  }

  double _volumeFor(int index) {
    _ensureTrimSlots();
    if (index < 0 || index >= _clipVolumes.length) return 1.0;
    return _clipVolumes[index].clamp(0.0, 1.0);
  }

  /// Duration-based max (20s → 1.5x). While Speed sheet open, live draft drives strip.
  double _speedFor(int index) {
    _ensureTrimSlots();
    final maxS = _ClipSpeedLimits.selectMax(_sourceSpan(index));
    if (_speedSheetOpen && _selectedClipIndex == index) {
      return _speedDraft.clamp(_ClipSpeedLimits.minSpeed, maxS);
    }
    if (index < 0 || index >= _clipSpeeds.length) return 1.0;
    return _clipSpeeds[index].clamp(_ClipSpeedLimits.minSpeed, maxS);
  }

  /// Preview rate matches timeline speed (clamped to device-safe range).
  double _previewPlaybackRate(double speed) =>
      speed.clamp(_ClipSpeedLimits.minSpeed, 100.0);

  VideoRevealAnim? _revealFor(int index) {
    _ensureTrimSlots();
    if (index < 0 || index >= _clipRevealIds.length) return null;
    return VideoRevealAnim.byId(_clipRevealIds[index]);
  }

  VideoRevealAnim? _outRevealFor(int index) {
    _ensureTrimSlots();
    if (index < 0 || index >= _clipOutRevealIds.length) return null;
    return VideoRevealAnim.byId(_clipOutRevealIds[index]);
  }

  /// CapCut In duration: user slider, else asset length (clamped to clip).
  double _revealDurationFor(int index) {
    final anim = _revealFor(index);
    if (anim == null) return 0;
    final maxSec = math.max(0.5, _visibleDuration(index));
    final raw =
        (_revealDurDrag != null &&
            _selectedClipIndex == index &&
            _animPhase == _VideoAnimPhase.inAnimation)
        ? _revealDurDrag!
        : (_clipRevealDurSec[index] ?? anim.durationSec);
    return raw.clamp(0.5, math.min(maxSec, 5.0)).toDouble();
  }

  /// CapCut Out duration at clip end.
  double _outRevealDurationFor(int index) {
    final anim = _outRevealFor(index);
    if (anim == null) return 0;
    final maxSec = math.max(0.5, _visibleDuration(index));
    final raw =
        (_revealDurDrag != null &&
            _selectedClipIndex == index &&
            _animPhase == _VideoAnimPhase.outAnimation)
        ? _revealDurDrag!
        : (_clipOutRevealDurSec[index] ?? anim.durationSec);
    return raw.clamp(0.5, math.min(maxSec, 5.0)).toDouble();
  }

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectW = 9;
  double _aspectH = 16;
  int _filterIndex = 0;
  /// Committed music on the timeline (after Music ✓).
  MusicTrack? _music;
  /// Draft selection while the Music picker is open (audition only).
  MusicTrack? _musicDraft;
  final List<MusicTrack> _localMusicTracks = [];
  /// Don't steal Android audio focus from [VideoPlayer] (or video pauses).
  final AudioPlayer _bgmPlayer = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  String? _bgmPath;
  bool _musicToolsOpen = false;
  bool _musicTrackSelected = false;
  bool _musicVolumeOpen = false;
  String? _stickerLabel;
  OverlayEffect? _overlayEffect;
  /// Effect span on the project timeline (CapCut clip start/end).
  double _effectStartSec = 0;
  double? _effectEndSec;
  bool _effectsToolsOpen = false;
  bool _effectsTrackSelected = false;
  bool _effectPreviewLoading = false;
  Color _bgColor = Colors.black;
  late final TextEditingController _textFieldController;
  late final FocusNode _textFocusNode;
  final TextOverlayStore _textOverlays = TextOverlayStore();
  bool _textToolsOpen = false;
  String? _selectedTextOverlayId;

  bool get _mediaToolSheetOpen =>
      _tool == VideoEditorTool.music || _tool == VideoEditorTool.effects;
  bool _loadingClip = false;
  bool _preparingProxy = false;

  final _stripController = ScrollController();
  bool _syncingStrip = false;
  bool _userScrubbing = false;
  Timer? _scrubTimer;
  double _lastScrubSec = -1;
  DateTime? _lastUiTick;
  /// Bumps on each play/pause so a stale async play branch can't resume video
  /// after the user already paused (BGM load race).
  int _playToggleGen = 0;

  /// Max editable clip length (product limit). CapCut free is typically ~60 min;
  /// we keep a conservative 5 min for v1 preview/export.
  static const _maxClipSec = 5 * 60.0;

  /// Per-clip duration (seconds).
  final Map<String, double> _clipDurationSec = {};

  /// Original path → downscaled proxy used for on-device preview (CapCut-style).
  final Map<String, String> _previewProxyPath = {};

  /// Filmstrip frame image paths per clip (dense strip → short transitions visible).
  final Map<String, List<String>> _filmstripFrames = {};
  final Set<String> _filmstripLoading = {};
  /// In-flight filmstrip jobs so Speed ✓ can await full strip before play.
  final Map<String, Future<void>> _filmstripJobs = {};

  /// Serialize FFmpeg so filmstrip doesn't fight preview proxy (CapCut-like).
  Future<void> _ffmpegChain = Future.value();

  Future<T> _runFfmpegJob<T>(Future<T> Function() job) {
    final run = _ffmpegChain.then((_) => job());
    _ffmpegChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  double get _pixelsPerSecond => AppResponsive.of(context).w(44);
  double get _thumbH => AppResponsive.of(context).h(60);
  double get _plusW => AppResponsive.of(context).w(52);
  double get _stripPadLeft => AppResponsive.of(context).w(16);
  double get _timelinePanelH => AppResponsive.of(context).h(200);
  double get _timelineHeaderH => AppResponsive.of(context).h(48);

  static final _filters = <(String, ColorFilter?)>[
    ('Original', null),
    (
      'Warm',
      ColorFilter.matrix(<double>[
        1.1,
        0.05,
        0,
        0,
        8,
        0,
        1.0,
        0,
        0,
        4,
        0,
        0,
        0.9,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    ),
    (
      'Cool',
      ColorFilter.matrix(<double>[
        0.9,
        0,
        0.05,
        0,
        0,
        0,
        1.0,
        0.05,
        0,
        0,
        0.05,
        0,
        1.15,
        0,
        10,
        0,
        0,
        0,
        1,
        0,
      ]),
    ),
    (
      'Mono',
      ColorFilter.matrix(<double>[
        0.33,
        0.33,
        0.33,
        0,
        0,
        0.33,
        0.33,
        0.33,
        0,
        0,
        0.33,
        0.33,
        0.33,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    ),
    (
      'Vivid',
      ColorFilter.matrix(<double>[
        1.2,
        0,
        0,
        0,
        0,
        0,
        1.15,
        0,
        0,
        0,
        0,
        0,
        1.1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _clips = List<String>.from(widget.videoPaths);
    _ensureTrimSlots();
    _textFieldController = TextEditingController();
    _textFocusNode = FocusNode();
    if (_clips.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No videos selected')));
        context.pop();
      });
      return;
    }
    _stripController.addListener(_onStripScroll);
    // Load active clip first — never open a second VideoPlayer on the same file
    // (Oppo/MediaCodec OOM when probe + preview fight for the decoder).
    unawaited(_bootstrapClips());
  }

  Future<void> _bootstrapClips() async {
    await _loadClip(0);
    if (!mounted) return;
    // Other clips: duration via FFprobe only (no VideoPlayer).
    for (var i = 1; i < _clips.length; i++) {
      await _probeDurationOnly(_clips[i]);
      if (!mounted) return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrubTimer?.cancel();
    _stripController.removeListener(_onStripScroll);
    _stripController.dispose();
    _textFieldController.dispose();
    _textFocusNode.dispose();
    _textOverlays.dispose();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    unawaited(_bgmPlayer.dispose());
    _stopRevealOverlay();
    _revealFrameTick.dispose();
    for (final images in _revealImages.values) {
      for (final img in images) {
        img.dispose();
      }
    }
    _revealImages.clear();
    super.dispose();
  }

  Future<void> _probeDurationOnly(String path) async {
    if (_clipDurationSec.containsKey(path)) return;
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final sec = double.tryParse(info?.getDuration() ?? '') ?? 1.0;
      _clipDurationSec[path] = math.max(0.1, sec);
      // Filmstrip starts after preview opens — don't compete with player/proxy.
    } catch (_) {
      _clipDurationSec[path] = _clipDurationSec[path] ?? 1.0;
    }
  }

  /// Filmstrip sample rate (higher = short transitions more visible on strip).
  static const _filmstripFps = 4;

  /// CapCut-style filmstrip: [_filmstripFps] thumbnails per second of source.
  /// Awaitable — Speed confirm waits until strip is ready before enabling play.
  Future<void> _ensureFilmstrip(String path) {
    final already = _filmstripFrames[path];
    if (already != null && already.length > 1) return Future.value();
    return _filmstripJobs.putIfAbsent(path, () async {
      _filmstripLoading.add(path);
      try {
        final dur = _clipDurationSec[path] ?? 1.0;
        final count =
            math.min(360, math.max(1, (dur * _filmstripFps).ceil()));
        final tmp = await getTemporaryDirectory();
        final safe = path.hashCode.toRadixString(16);
        // vstrip4 = 4fps cache (invalidates older vstrip2/3).
        final dir = Directory(p.join(tmp.path, 'vstrip4_$safe'));

        if (await dir.exists()) {
          final cached = await _listFilmstripJpgs(dir);
          if (cached.length >= math.min(count, 2) ||
              (count == 1 && cached.isNotEmpty)) {
            _filmstripFrames[path] = cached;
            if (mounted) setState(() {});
            return;
          }
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        await dir.create(recursive: true);

        // Quick poster (queued) so strip isn't empty.
        final poster = File(p.join(dir.path, 'f_0001.jpg'));
        await _runFfmpegJob(() async {
          final posterSession = await FFmpegKit.execute(
            '-y -ss 0.1 -i "$path" -frames:v 1 -vf scale=120:-2 -q:v 6 '
            '"${poster.path}"',
          );
          if (ReturnCode.isSuccess(await posterSession.getReturnCode()) &&
              await poster.exists()) {
            _filmstripFrames[path] = [poster.path];
            if (mounted) setState(() {});
          }
        });

        if (count <= 1) return;

        // Full strip after preview is up — lower priority than proxy.
        final pattern = p.join(dir.path, 'f_%04d.jpg');
        await _runFfmpegJob(() async {
          final session = await FFmpegKit.execute(
            '-y -i "$path" -t ${dur.clamp(0.5, _maxClipSec)} '
            '-vf "fps=$_filmstripFps,scale=120:-2" -q:v 6 -frames:v $count '
            '"$pattern"',
          );
          final code = await session.getReturnCode();
          if (!ReturnCode.isSuccess(code)) return;
          final files = await _listFilmstripJpgs(dir);
          if (files.isEmpty) return;
          _filmstripFrames[path] = files;
          if (mounted) setState(() {});
        });
      } catch (_) {
        // Keep placeholders / poster.
      } finally {
        _filmstripLoading.remove(path);
        _filmstripJobs.remove(path);
      }
    });
  }

  Future<List<String>> _listFilmstripJpgs(Directory dir) async {
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.jpg')) {
        files.add(e);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return [for (final f in files) f.path];
  }

  /// Light proxy only when hardware decode fails (CapCut opens original first).
  Future<String?> _ensurePreviewProxy(String original) async {
    final cached = _previewProxyPath[original];
    if (cached != null && File(cached).existsSync()) return cached;

    final tmp = await getTemporaryDirectory();
    final out = File(
      p.join(tmp.path, 'vproxy3_${original.hashCode.toRadixString(16)}.mp4'),
    );
    if (await out.exists() && await out.length() > 1024) {
      _previewProxyPath[original] = out.path;
      return out.path;
    }

    // Fast fallback: 540p @ 24fps, mono AAC — much quicker than full 720p re-encode.
    return _runFfmpegJob(() async {
      final session = await FFmpegKit.execute(
        '-y -i "$original" -t $_maxClipSec '
        '-vf "scale=\'min(540,iw)\':\'min(540,ih)\':force_original_aspect_ratio=decrease,fps=24" '
        '-c:v libx264 -preset ultrafast -tune zerolatency -crf 32 -pix_fmt yuv420p '
        '-c:a aac -ac 1 -ar 22050 -b:a 64k -movflags +faststart '
        '"${out.path}"',
      );
      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code) && await out.exists()) {
        _previewProxyPath[original] = out.path;
        return out.path;
      }
      return null;
    });
  }

  Future<bool> _openPlayer(
    String path, {
    required Duration seekTo,
    required String originalPath,
  }) async {
    final next = VideoPlayerController.file(File(path));
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return false;
      }
      next.addListener(_onVideoTick);
      _controller = next;
      final dur = next.value.duration;
      _clipDurationSec[originalPath] = math.max(
        0.1,
        dur.inMilliseconds / 1000.0,
      );
      unawaited(_ensureFilmstrip(originalPath));
      if (seekTo > Duration.zero && seekTo < dur) {
        await next.seekTo(seekTo);
      }
      await next.setVolume(_volumeFor(_activeIndex));
      await next.setPlaybackSpeed(
        _previewPlaybackRate(_speedFor(_activeIndex)),
      );
      setState(() {
        _ready = true;
        _preparingProxy = false;
        _duration = dur;
        _position = next.value.position;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncStripToPlayhead();
      });
      return true;
    } catch (_) {
      try {
        await next.dispose();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _loadClip(int index, {Duration seekTo = Duration.zero}) async {
    if (index < 0 || index >= _clips.length) return;
    if (_loadingClip) return;
    _loadingClip = true;
    final original = _clips[index];
    final old = _controller;
    old?.removeListener(_onVideoTick);
    setState(() {
      _ready = false;
      _playing = false;
      _preparingProxy = false;
      _activeIndex = index;
      _position = seekTo;
      _duration = Duration.zero;
    });
    try {
      await old?.dispose();
    } catch (_) {}
    _controller = null;

    try {
      // Probe in parallel with open — don't block first frame on ffprobe alone.
      final probe = _probeDurationOnly(original);

      // CapCut: open original immediately. Proxy only if decoder rejects it.
      if (await _openPlayer(original, seekTo: seekTo, originalPath: original)) {
        await probe;
        final durSec =
            _clipDurationSec[original] ?? _duration.inMilliseconds / 1000.0;
        if (durSec > _maxClipSec + 0.5) {
          await _controller?.dispose();
          _controller = null;
          if (!mounted) return;
          setState(() => _ready = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a video of 5 minutes or less.'),
            ),
          );
        }
        return;
      }

      await probe;
      if (!mounted) return;
      final durSec = _clipDurationSec[original] ?? 0;
      if (durSec > _maxClipSec + 0.5) {
        setState(() => _ready = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a video of 5 minutes or less.'),
          ),
        );
        return;
      }

      // Hardware decode failed → light proxy (shown as Preparing preview…).
      setState(() => _preparingProxy = true);
      final proxy = await _ensurePreviewProxy(original);
      if (!mounted) return;
      if (proxy != null &&
          await _openPlayer(proxy, seekTo: seekTo, originalPath: original)) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _ready = false;
        _preparingProxy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not prepare this video for preview.'),
        ),
      );
    } finally {
      _loadingClip = false;
      if (mounted && _preparingProxy && !_ready) {
        setState(() => _preparingProxy = false);
      }
    }
  }

  double _sourceDuration(int index) {
    final path = _clips[index];
    final known = _clipDurationSec[path];
    if (known != null && known > 0) return known;
    // Active player may still be Duration.zero while proxy/init runs.
    if (index == _activeIndex) {
      final sec = _duration.inMilliseconds / 1000.0;
      if (sec > 0) return sec;
    }
    return 1.0; // placeholder until duration is probed
  }

  double _trimIn(int index) {
    _ensureTrimSlots();
    if (_selectedClipIndex == index && _liveTrimIn != null) return _liveTrimIn!;
    return _clipTrimIn[index] ?? 0;
  }

  double _trimOut(int index) {
    _ensureTrimSlots();
    if (_selectedClipIndex == index && _liveTrimOut != null) {
      return _liveTrimOut!;
    }
    return _clipTrimOut[index] ?? _sourceDuration(index);
  }

  double _visibleDuration(int index) {
    // Dart clamp requires lower <= upper; full can be 0 while loading.
    final full = math.max(0.5, _sourceDuration(index));
    final span = (_trimOut(index) - _trimIn(index)).clamp(0.05, full);
    // CapCut: timeline length stretches/shrinks with speed.
    return (span / _speedFor(index)).clamp(0.1, 36000.0).toDouble();
  }

  double _sourceSpan(int index) {
    final full = math.max(0.5, _sourceDuration(index));
    return (_trimOut(index) - _trimIn(index)).clamp(0.05, full).toDouble();
  }

  double get _totalDurationSec {
    var sum = 0.0;
    for (var i = 0; i < _clips.length; i++) {
      sum += _visibleDuration(i);
    }
    return math.max(0.1, sum);
  }

  double get _globalPositionSec {
    var before = 0.0;
    for (var i = 0; i < _activeIndex && i < _clips.length; i++) {
      before += _visibleDuration(i);
    }
    final sourceLocal =
        (_position.inMilliseconds / 1000.0) - _trimIn(_activeIndex);
    final timelineLocal = sourceLocal / _speedFor(_activeIndex);
    return before + timelineLocal.clamp(0.0, _visibleDuration(_activeIndex));
  }

  void _clearClipSelection() {
    unawaited(_pausePreview());
    _clearAnimPreviewState(stopOverlay: true);
    setState(() {
      _selectedClipIndex = null;
      _animSheetOpen = false;
      _speedSheetOpen = false;
      _liveTrimIn = null;
      _liveTrimOut = null;
      _trimDragging = false;
    });
    _stopRevealOverlay();
  }

  void _selectClip(int index) {
    unawaited(_pausePreview());
    setState(() {
      _selectedClipIndex = index;
      _tool = null;
      _animSheetOpen = false;
      _speedSheetOpen = false;
      _effectsToolsOpen = false;
      _musicToolsOpen = false;
      _musicVolumeOpen = false;
      _musicTrackSelected = false;
      _textToolsOpen = false;
      _selectedTextOverlayId = null;
    });
    if (_activeIndex != index) unawaited(_loadClip(index));
  }

  String _fmtSec(double sec) {
    final s = sec.floor().clamp(0, 99999);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    final wasPlaying = _playing;
    _position = v.position;
    _duration = v.duration;
    _playing = v.isPlaying;

    // Slideshow-style: strip follows playhead while playing.
    if (_playing && !_userScrubbing) {
      _syncStripToPlayhead();
    }

    // Stop BGM once playhead leaves the music window / hits video end.
    if (_music != null && (_playing || _bgmPlayer.playing)) {
      final (tStart, tEnd) = _musicTimelineRange();
      final g = _globalPositionSec;
      if (g < tStart || g >= tEnd || g >= _totalDurationSec - 0.04) {
        unawaited(_pauseBgm());
      }
    }

    // CapCut In/Out-anim: sync overlay to playhead.
    _syncRevealOverlayFromMain();

    final now = DateTime.now();
    final dueUi =
        _lastUiTick == null ||
        now.difference(_lastUiTick!) >= const Duration(milliseconds: 50) ||
        wasPlaying != _playing;
    if (dueUi) {
      _lastUiTick = now;
      setState(() {});
    }

    final out = _trimOut(_activeIndex);
    final posSec = v.position.inMilliseconds / 1000.0;

    // Animation sheet: play only the selected FX window (e.g. ~2s), then pause.
    if (_animPreviewPlaying && v.isPlaying) {
      final endSec = _animPreviewEndSec();
      if (posSec >= endSec - 0.04) {
        unawaited(_finishAnimPreviewPlayback(endSec));
      }
      return;
    }

    if (v.isInitialized && v.isPlaying && posSec >= out - 0.04) {
      unawaited(_playNextOrStop());
      return;
    }
    // Native EOF only while we haven't already parked on the last frame.
    if (v.isInitialized &&
        !_stoppedAtClipEnd &&
        !_animPreviewPlaying &&
        v.position >= v.duration &&
        v.duration > Duration.zero &&
        !v.isPlaying) {
      unawaited(_playNextOrStop());
    }
  }

  double _animPreviewEndSec() {
    final inn = _trimIn(_activeIndex);
    final out = _trimOut(_activeIndex);
    if (_animPhase == _VideoAnimPhase.outAnimation) {
      return out;
    }
    return inn + _revealDurationFor(_activeIndex);
  }

  double _animPreviewStartSec() {
    final inn = _trimIn(_activeIndex);
    final out = _trimOut(_activeIndex);
    if (_animPhase == _VideoAnimPhase.outAnimation) {
      final dur = _outRevealDurationFor(_activeIndex);
      return math.max(inn, out - dur);
    }
    return inn;
  }

  Future<void> _finishAnimPreviewPlayback(double endSec) async {
    final c = _controller;
    if (c == null) return;
    _animPreviewPlaying = false;
    final durMs = c.value.duration.inMilliseconds;
    final endMs = (endSec * 1000).round();
    final seekMs = durMs > 0
        ? math.min(endMs, math.max(0, durMs - 30))
        : math.max(0, endMs - 30);
    await c.pause();
    await c.seekTo(Duration(milliseconds: seekMs));
    if (!mounted) return;
    setState(() {
      _playing = false;
      _position = c.value.position;
      _animPreviewReady = true;
    });
    _syncRevealOverlayFromMain();
    _syncStripToPlayhead();
  }

  /// CapCut: tap FX thumb → loading on preview → park first frame → play enabled.
  Future<void> _prepareAnimPreview(
    VideoRevealAnim anim, {
    required bool isOut,
  }) async {
    final gen = ++_animPreviewGen;
    _animPreviewPlaying = false;
    _stoppedAtClipEnd = false;
    final c = _controller;
    if (c != null && c.value.isPlaying) {
      await c.pause();
    }
    if (!mounted || gen != _animPreviewGen) return;
    setState(() {
      _animPreviewLoading = true;
      _animPreviewReady = false;
      _playing = false;
    });
    try {
      await _ensureRevealImages(anim);
      if (!mounted || gen != _animPreviewGen) return;
      if (isOut) {
        final out = _trimOut(_activeIndex);
        final dur = anim.durationSec.clamp(
          0.5,
          math.max(0.5, _visibleDuration(_activeIndex)),
        );
        final start = math.max(_trimIn(_activeIndex), out - dur);
        await _startRevealOverlay(
          anim,
          seekMainToStart: false,
          seekToSec: start,
        );
      } else {
        await _startRevealOverlay(anim, seekMainToStart: true);
      }
      if (!mounted || gen != _animPreviewGen) return;
      setState(() {
        _animPreviewLoading = false;
        _animPreviewReady = true;
        _playing = false;
        _position = _controller?.value.position ?? _position;
      });
      _syncStripToPlayhead();
    } catch (e, st) {
      debugPrint('Anim preview prepare failed (${anim.id}): $e\n$st');
      if (!mounted || gen != _animPreviewGen) return;
      setState(() {
        _animPreviewLoading = false;
        _animPreviewReady = false;
      });
      _stopRevealOverlay();
    }
  }

  Future<void> _playAnimPreviewOnly() async {
    final c = _controller;
    if (c == null || !_ready || !_animPreviewReady) return;
    final isOut = _animPhase == _VideoAnimPhase.outAnimation;
    final anim = isOut
        ? _outRevealFor(_activeIndex)
        : _revealFor(_activeIndex);
    if (anim == null) return;

    _stoppedAtClipEnd = false;
    final start = _animPreviewStartSec();
    await _startRevealOverlay(
      anim,
      seekMainToStart: false,
      seekToSec: start,
    );
    if (!mounted) return;
    _animPreviewPlaying = true;
    await c.play();
    if (mounted) {
      setState(() => _playing = true);
      _syncStripToPlayhead();
    }
  }

  /// Animation check (✓): close sheet and park playhead at project start.
  Future<void> _confirmAnimSheetAndSeekStart() async {
    final c = _controller;
    if (c != null && c.value.isPlaying) {
      await c.pause();
    }
    _clearAnimPreviewState(stopOverlay: true);
    _stoppedAtClipEnd = false;
    if (mounted) {
      setState(() {
        _animSheetOpen = false;
        _speedSheetOpen = false;
        _revealDurDrag = null;
        _playing = false;
      });
    }
    // Full timeline preview always resumes from the beginning after confirm.
    await _seekGlobal(0);
    if (!mounted) return;
    final reveal = _revealFor(_activeIndex);
    if (reveal != null) {
      await _ensureRevealImages(reveal);
      if (!mounted) return;
      await _startRevealOverlay(reveal, seekMainToStart: true);
    } else {
      _syncRevealOverlayFromMain();
    }
    _syncStripToPlayhead();
    if (mounted) setState(() {});
  }

  void _syncStripToPlayhead() {
    // Avoid assert when controller briefly has 0/N positions during rebuilds.
    if (_stripController.positions.length != 1) return;
    final target = _globalPositionSec * _pixelsPerSecond;
    final max = _stripController.position.maxScrollExtent;
    if (max <= 0) return;
    final next = target.clamp(0.0, max).toDouble();
    if ((_stripController.offset - next).abs() < 0.5) return;
    _syncingStrip = true;
    _stripController.jumpTo(next);
    // jumpTo may notify listeners after this returns — keep flag until next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncingStrip = false;
    });
  }

  void _onStripScroll() {
    // Ignore programmatic jumps while video is driving the strip.
    if (_syncingStrip || _stripController.positions.length != 1) return;
    if (_playing || (_controller?.value.isPlaying ?? false) || _bgmPlayer.playing) {
      // User dragged while playing → pause then scrub (slideshow behavior).
      _playToggleGen++;
      unawaited(_controller?.pause());
      unawaited(_pauseBgm());
      _playing = false;
    }
    _userScrubbing = true;
    final t = (_stripController.offset / _pixelsPerSecond)
        .clamp(0.0, _totalDurationSec)
        .toDouble();
    if ((t - _lastScrubSec).abs() < 0.04) return;
    _lastScrubSec = t;
    setState(() => _position = Duration(milliseconds: (t * 1000).round()));
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(milliseconds: 50), () {
      unawaited(_seekGlobal(t, fromScrub: true));
    });
  }

  Future<void> _seekGlobal(double globalSec, {bool fromScrub = false}) async {
    if (_clips.isEmpty) return;
    _stoppedAtClipEnd = false;
    _userScrubbing = fromScrub;
    var remaining = globalSec;
    var index = 0;
    for (; index < _clips.length; index++) {
      final d = _visibleDuration(index);
      if (remaining <= d || index == _clips.length - 1) break;
      remaining -= d;
    }
    // Timeline seconds → source seconds (speed-scaled).
    final sourceLocal = _trimIn(index) + remaining * _speedFor(index);
    final local = Duration(
      milliseconds: (sourceLocal * 1000).round().clamp(0, 1 << 30),
    );
    if (index != _activeIndex) {
      final wasPlaying = _playing;
      await _loadClip(index, seekTo: local);
      if (wasPlaying && !fromScrub) await _controller?.play();
    } else {
      await _controller?.seekTo(local);
      if (mounted) {
        setState(() => _position = local);
      }
    }
    // CapCut: In/Out anim follows playhead while scrubbing.
    final reveal = _revealFor(_activeIndex);
    final outReveal = _outRevealFor(_activeIndex);
    if (reveal != null || outReveal != null) {
      unawaited(() async {
        if (reveal != null) await _ensureRevealImages(reveal);
        if (outReveal != null) await _ensureRevealImages(outReveal);
        if (mounted) _syncRevealOverlayFromMain();
      }());
    } else {
      _syncRevealOverlayFromMain();
    }
    if (fromScrub) {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _userScrubbing = false;
      });
      await _pauseBgm();
    } else if (_playing || (_controller?.value.isPlaying ?? false)) {
      await _syncBgmToPlayhead(forceSeek: true);
    }
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !_ready || _animPreviewLoading) return;
    final gen = ++_playToggleGen;

    // Animation sheet + FX selected: play/pause only that FX window (~2s).
    if (_animSheetOpen && _hasAnimSheetSelection) {
      if (!_animPreviewReady) return;
      if (c.value.isPlaying || _animPreviewPlaying) {
        _animPreviewPlaying = false;
        await c.pause();
        await _pauseBgm();
        _syncRevealOverlayFromMain();
        if (mounted && gen == _playToggleGen) {
          setState(() => _playing = false);
        }
        return;
      }
      await _playAnimPreviewOnly();
      return;
    }

    final inn = _trimIn(_activeIndex);
    final out = _trimOut(_activeIndex);
    final pos = c.value.position.inMilliseconds / 1000.0;
    final atProjectEnd =
        _stoppedAtClipEnd || _globalPositionSec >= _totalDurationSec - 0.15;

    // Parked at the last frame after a full play-through: Play always
    // restarts from 0 (do not treat leftover BGM as a "pause" tap).
    if (atProjectEnd && !c.value.isPlaying && !_playing) {
      await _pauseBgm();
      if (!mounted || gen != _playToggleGen) return;
      _userScrubbing = false;
      _scrubTimer?.cancel();
      _stoppedAtClipEnd = false;
      await _seekGlobal(0);
      if (!mounted || gen != _playToggleGen) return;
      final revealAtStart = _revealFor(_activeIndex);
      if (revealAtStart != null) {
        await _startRevealOverlay(revealAtStart, seekMainToStart: true);
      } else {
        _stopRevealOverlay();
      }
      if (!mounted || gen != _playToggleGen) return;
      final rate0 = _speedSheetOpen
          ? _previewPlaybackRate(_speedDraft)
          : _previewPlaybackRate(_speedFor(_activeIndex));
      await c.setPlaybackSpeed(rate0);
      if (!mounted || gen != _playToggleGen) return;
      await c.play();
      if (!mounted || gen != _playToggleGen) {
        await c.pause();
        return;
      }
      await _syncBgmToPlayhead(forceSeek: true);
      if (!mounted || gen != _playToggleGen) {
        await c.pause();
        await _pauseBgm();
        return;
      }
      if (!c.value.isPlaying) await c.play();
      if (!mounted || gen != _playToggleGen) {
        await c.pause();
        await _pauseBgm();
        return;
      }
      setState(() => _playing = c.value.isPlaying);
      _syncStripToPlayhead();
      return;
    }

    // Pause if UI, video, or BGM is active (keeps them in lockstep).
    final wantPause =
        _playing || c.value.isPlaying || _bgmPlayer.playing;
    if (wantPause) {
      await c.pause();
      await _pauseBgm();
      // CapCut: keep In-anim visible at playhead while paused.
      _syncRevealOverlayFromMain();
      if (mounted && gen == _playToggleGen) {
        setState(() => _playing = false);
      }
      return;
    }

    _userScrubbing = false;
    _scrubTimer?.cancel();
    // CapCut: restart from clip start if near begin or past / parked at clip end.
    final restartFromStart =
        pos < inn + 0.15 || pos >= out - 0.05 || pos < inn;
    _stoppedAtClipEnd = false;
    if (restartFromStart) {
      await c.seekTo(Duration(milliseconds: (inn * 1000).round()));
    }
    if (!mounted || gen != _playToggleGen) return;

    final reveal = _revealFor(_activeIndex);
    final revealDur = _revealDurationFor(_activeIndex);
    final outReveal = _outRevealFor(_activeIndex);
    final outDur = _outRevealDurationFor(_activeIndex);
    final outStart = out - outDur;
    if (reveal != null && restartFromStart) {
      await _startRevealOverlay(reveal);
    } else if (reveal != null) {
      final local = pos - inn;
      if (local >= 0 && local < revealDur) {
        await _startRevealOverlay(reveal, seekMainToStart: false);
      } else if (outReveal != null &&
          pos >= outStart - 0.05 &&
          pos <= out + 0.05) {
        await _startRevealOverlay(
          outReveal,
          seekMainToStart: false,
          seekToSec: pos.clamp(outStart, out),
        );
      } else {
        _stopRevealOverlay();
      }
    } else if (outReveal != null &&
        pos >= outStart - 0.05 &&
        pos <= out + 0.05) {
      await _startRevealOverlay(
        outReveal,
        seekMainToStart: false,
        seekToSec: pos.clamp(outStart, out),
      );
    } else {
      _stopRevealOverlay();
    }
    if (!mounted || gen != _playToggleGen) return;

    final rate = _speedSheetOpen
        ? _previewPlaybackRate(_speedDraft)
        : _previewPlaybackRate(_speedFor(_activeIndex));
    await c.setPlaybackSpeed(rate);
    if (!mounted || gen != _playToggleGen) return;
    await c.play();
    if (!mounted || gen != _playToggleGen) {
      await c.pause();
      return;
    }
    await _syncBgmToPlayhead(forceSeek: true);
    if (!mounted || gen != _playToggleGen) {
      await c.pause();
      await _pauseBgm();
      return;
    }
    // BGM start can still drop VideoPlayer on some devices — resume if needed.
    if (!c.value.isPlaying) {
      await c.play();
    }
    if (!mounted || gen != _playToggleGen) {
      await c.pause();
      await _pauseBgm();
      return;
    }
    setState(() => _playing = c.value.isPlaying);
    _syncStripToPlayhead();
  }

  Future<void> _playNextOrStop() async {
    // Animation-sheet FX preview owns its own end handling.
    if (_animPreviewPlaying || _animSheetOpen && _hasAnimSheetSelection) {
      return;
    }
    if (_activeIndex + 1 < _clips.length) {
      _stoppedAtClipEnd = false;
      _stopRevealOverlay();
      final next = _activeIndex + 1;
      await _loadClip(
        next,
        seekTo: Duration(milliseconds: (_trimIn(next) * 1000).round()),
      );
      final reveal = _revealFor(next);
      if (reveal != null) await _startRevealOverlay(reveal);
      await _controller?.play();
      await _syncBgmToPlayhead(forceSeek: true);
      final nextC = _controller;
      if (mounted && nextC != null && !nextC.value.isPlaying) {
        await nextC.play();
      }
      _syncStripToPlayhead();
      return;
    }

    // Last clip finished: pause on last frame (Out final frame if set).
    // Do NOT seek back to trimIn — that wrongly shows the In effect.
    if (_stoppedAtClipEnd) return;
    _stoppedAtClipEnd = true;
    _playToggleGen++; // cancel any in-flight play/BGM resume
    final c = _controller;
    if (c == null) return;
    final out = _trimOut(_activeIndex);
    final durMs = c.value.duration.inMilliseconds;
    final outMs = (out * 1000).round();
    // Stay just inside the clip so the decoder still has a valid last frame.
    final seekMs = durMs > 0
        ? math.min(outMs, math.max(0, durMs - 30))
        : math.max(0, outMs - 30);
    await c.pause();
    await _pauseBgm();
    await c.seekTo(Duration(milliseconds: seekMs));
    if (!mounted) return;
    setState(() {
      _playing = false;
      _position = c.value.position;
    });
    _syncRevealOverlayFromMain();
    _syncStripToPlayhead();
  }

  Future<String> _revealFilePath(VideoRevealAnim anim) async {
    // Include asset basename so reused ids (e.g. fx_02) never keep a stale file.
    final base = p.basenameWithoutExtension(anim.assetPath);
    return _copyRevealAsset(anim.assetPath, 'vreveal_${anim.id}_${base}_color');
  }

  Future<String> _revealMatteFilePath(VideoRevealAnim anim) async {
    final path = anim.alphaMatteAssetPath;
    if (path == null) throw StateError('Reveal has no alpha matte');
    final base = p.basenameWithoutExtension(path);
    return _copyRevealAsset(path, 'vreveal_${anim.id}_${base}');
  }

  Future<String> _copyRevealAsset(String assetPath, String cacheName) async {
    final cached = _revealAssetFiles[assetPath];
    if (cached != null && File(cached).existsSync()) return cached;
    final tmp = await getTemporaryDirectory();
    final out = File(p.join(tmp.path, '$cacheName.mp4'));
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    // Rewrite when missing or size-mismatched (stale cache after asset swap).
    if (!await out.exists() || await out.length() != bytes.length) {
      await out.writeAsBytes(bytes, flush: true);
    }
    _revealAssetFiles[assetPath] = out.path;
    return out.path;
  }

  Future<List<String>> _listRevealFrames(
    Directory dir, {
    required Set<String> exts,
  }) async {
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final lower = e.path.toLowerCase();
      if (exts.any(lower.endsWith)) files.add(e);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return [for (final f in files) f.path];
  }

  /// Decode In-anim frames once. Alpha-matte assets stay RGBA PNGs; legacy
  /// glow assets remain JPEGs for Screen blend.
  Future<List<String>> _ensureRevealFrames(VideoRevealAnim anim) {
    final hit = _revealFrameFiles[anim.id];
    if (hit != null && hit.isNotEmpty) return Future.value(hit);
    return _revealFrameJobs.putIfAbsent(anim.id, () async {
      try {
        final path = await _revealFilePath(anim);
        final mattePath = anim.alphaMatteAssetPath == null
            ? null
            : await _revealMatteFilePath(anim);
        final tmp = await getTemporaryDirectory();
        // Leaf Reveal pattern: color + alpha → RGBA PNG.
        // v22: denser CapCut-like Portal Burst fire vortex.
        final base = p.basenameWithoutExtension(anim.assetPath);
        final dir = Directory(
          p.join(tmp.path, 'vreveal_frames_${anim.id}_${base}_v22_alpha'),
        );
        if (await dir.exists()) {
          final existing = await _listRevealFrames(dir, exts: {'.png'});
          if (existing.length >= 4) {
            _revealFrameFiles[anim.id] = existing;
            return existing;
          }
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        await dir.create(recursive: true);
        final pattern = p.join(dir.path, 'r_%04d.png');
        await _runFfmpegJob(() async {
          if (mattePath == null) {
            throw Exception('${anim.id} missing alpha matte asset');
          }
          final session = await FFmpegKit.execute(
            '-y -i "$path" -i "$mattePath" '
            '-filter_complex "'
            '[0:v]fps=24,scale=540:-2,setsar=1,format=rgb24[fg];'
            '[1:v]fps=24,scale=540:-2,setsar=1,format=gray[matte];'
            '[fg][matte]alphamerge,format=rgba[out]" '
            '-map "[out]" -vsync 0 "$pattern"',
          );
          final code = await session.getReturnCode();
          if (!ReturnCode.isSuccess(code)) {
            final logs = await session.getAllLogsAsString();
            throw Exception('Alpha reveal frame extraction failed: $logs');
          }
        });
        final files = await _listRevealFrames(dir, exts: {'.png'});
        if (files.isEmpty) throw Exception('In-anim frames empty');
        _revealFrameFiles[anim.id] = files;
        return files;
      } catch (e) {
        _revealFrameJobs.remove(anim.id);
        rethrow;
      }
    });
  }

  /// Decode FX frames into GPU-ready images once (fixes blink from Image.file).
  Future<List<ui.Image>> _ensureRevealImages(VideoRevealAnim anim) {
    final hit = _revealImages[anim.id];
    if (hit != null && hit.isNotEmpty) return Future.value(hit);
    return _revealImageJobs.putIfAbsent(anim.id, () async {
      try {
        final files = await _ensureRevealFrames(anim);
        final decoded = <ui.Image>[];
        for (final path in files) {
          final bytes = await File(path).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          decoded.add(frame.image);
        }
        if (decoded.isEmpty) throw Exception('In-anim decode empty');
        _revealImages[anim.id] = decoded;
        return decoded;
      } catch (e) {
        _revealImageJobs.remove(anim.id);
        rethrow;
      }
    });
  }

  /// CapCut In-anim: paint predecoded RGBA frame (Leaf Reveal srcOver pattern).
  Widget _buildRevealOverlayLayer() {
    final id = _activeRevealId;
    final images = id == null ? null : _revealImages[id];
    if (images == null || images.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _revealFrameTick,
      builder: (context, _) {
        final fi = _revealFrameIndex.clamp(0, images.length - 1);
        return CustomPaint(
          painter: _RevealFxPainter(
            image: images[fi],
            blendMode: BlendMode.srcOver,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }

  void _stopRevealOverlay() {
    if (!_revealOverlayActive && _activeRevealId == null) return;
    _revealOverlayActive = false;
    _activeRevealId = null;
    _revealFrameIndex = 0;
    _revealFrameTick.value = 0;
    if (mounted) setState(() {});
  }

  /// CapCut: show In at clip start, Out at clip end.
  void _syncRevealOverlayFromMain() {
    final pos =
        (_controller?.value.position.inMilliseconds ?? 0) / 1000.0;
    final inn = _trimIn(_activeIndex);
    final out = _trimOut(_activeIndex);

    final inAnim = _revealFor(_activeIndex);
    final inDur = _revealDurationFor(_activeIndex);
    final inLocal = pos - inn;
    final inActive =
        inAnim != null && inLocal >= -0.02 && inLocal < inDur;

    final outAnim = _outRevealFor(_activeIndex);
    final outDur = _outRevealDurationFor(_activeIndex);
    final outStart = out - outDur;
    final outLocal = pos - outStart;
    final outActive =
        outAnim != null &&
        outDur > 0 &&
        pos >= outStart - 0.02 &&
        pos <= out + 0.05;

    VideoRevealAnim? reveal;
    double local = 0;
    double dur = 0;
    if (inActive) {
      reveal = inAnim;
      local = inLocal;
      dur = inDur;
    } else if (outActive) {
      reveal = outAnim;
      local = outLocal.clamp(0.0, outDur);
      dur = outDur;
    }

    if (reveal == null) {
      if (_revealOverlayActive) _stopRevealOverlay();
      return;
    }
    final images = _revealImages[reveal.id];
    if (images == null || images.isEmpty) {
      // Prefetch when playhead enters In/Out window.
      unawaited(
        _ensureRevealImages(reveal).then((_) {
          if (mounted) _syncRevealOverlayFromMain();
        }),
      );
      return;
    }

    final idx = (local / dur * images.length).floor().clamp(
      0,
      images.length - 1,
    );
    final wasActive = _revealOverlayActive && _activeRevealId == reveal.id;
    _activeRevealId = reveal.id;
    _revealOverlayActive = true;
    if (idx != _revealFrameIndex) {
      _revealFrameIndex = idx;
      _revealFrameTick.value = idx;
    }
    if (!wasActive && mounted) setState(() {});
  }

  /// CapCut: arm reveal overlay (In at start, or Out at custom seek).
  Future<void> _startRevealOverlay(
    VideoRevealAnim anim, {
    bool seekMainToStart = true,
    double? seekToSec,
  }) async {
    final main = _controller;
    if (main == null || !_ready) return;
    try {
      final images = await _ensureRevealImages(anim);
      if (!mounted || images.isEmpty) return;
      if (seekToSec != null) {
        await main.seekTo(
          Duration(milliseconds: (seekToSec * 1000).round()),
        );
      } else if (seekMainToStart) {
        final inn = _trimIn(_activeIndex);
        await main.seekTo(Duration(milliseconds: (inn * 1000).round()));
      }
      _activeRevealId = anim.id;
      _revealOverlayActive = true;
      _revealFrameIndex = 0;
      _revealFrameTick.value = 0;
      _syncRevealOverlayFromMain();
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Reveal overlay failed (${anim.id}): $e\n$st');
      _stopRevealOverlay();
    }
  }

  /// Live preview when picking an In-anim (CapCut: seek start + play overlay).
  Future<void> _playRevealAtClipStart(
    VideoRevealAnim anim, {
    required bool playMain,
  }) async {
    await _startRevealOverlay(anim, seekMainToStart: true);
    if (playMain) {
      await _controller?.play();
      _syncStripToPlayhead();
    }
  }

  /// Live preview when picking an Out-anim (CapCut: seek end window + play).
  Future<void> _playRevealAtClipEnd(
    VideoRevealAnim anim, {
    required bool playMain,
  }) async {
    final out = _trimOut(_activeIndex);
    final dur = anim.durationSec.clamp(0.5, math.max(0.5, _visibleDuration(_activeIndex)));
    final start = math.max(_trimIn(_activeIndex), out - dur);
    await _startRevealOverlay(anim, seekMainToStart: false, seekToSec: start);
    if (playMain) {
      await _controller?.play();
      _syncStripToPlayhead();
    }
  }

  void _selectTool(VideoEditorTool t) {
    unawaited(_pausePreview());
    // Edit → same as tapping a clip: select timeline + clip tools navbar.
    if (t == VideoEditorTool.edit) {
      if (_clips.isEmpty) return;
      final index = _activeIndex.clamp(0, _clips.length - 1);
      _selectClip(index);
      return;
    }
    if (t == VideoEditorTool.text) {
      if (_textToolsOpen) {
        _closeTextTools();
      } else {
        _openTextTools();
      }
      return;
    }
    // Existing music → CapCut music tools navbar (not picker).
    if (t == VideoEditorTool.music && _music != null) {
      if (_musicToolsOpen) {
        _closeMusicTools();
        return;
      }
      setState(() {
        _tool = null;
        _musicToolsOpen = true;
        _musicTrackSelected = true;
        _musicVolumeOpen = false;
        _effectsToolsOpen = false;
        _animSheetOpen = false;
        _speedSheetOpen = false;
        _textToolsOpen = false;
        _selectedClipIndex = null;
      });
      return;
    }
    // Existing effect → CapCut effects tools navbar (not picker).
    if (t == VideoEditorTool.effects && _overlayEffect != null) {
      if (_effectsToolsOpen) {
        _closeEffectsTools();
        return;
      }
      setState(() {
        _tool = null;
        _effectsToolsOpen = true;
        _effectsTrackSelected = true;
        _musicToolsOpen = false;
        _animSheetOpen = false;
        _speedSheetOpen = false;
        _textToolsOpen = false;
        _selectedClipIndex = null;
      });
      return;
    }
    final closing = _tool == t;
    setState(() {
      _tool = closing ? null : t;
      _animSheetOpen = false;
      _speedSheetOpen = false;
      _textToolsOpen = false;
      _selectedTextOverlayId = null;
      _selectedClipIndex = null;
      if (t == VideoEditorTool.effects && !closing) {
        _effectsToolsOpen = false;
      }
      if (t == VideoEditorTool.music && !closing) {
        _musicToolsOpen = false;
        _musicDraft = _music;
      }
      if (closing && t == VideoEditorTool.music) {
        _musicDraft = null;
      }
    });
  }

  void _finishEffectsPicker() {
    final has = _overlayEffect != null;
    setState(() {
      _tool = null;
      _effectPreviewLoading = false;
      _effectsToolsOpen = true;
      _effectsTrackSelected = has;
      _musicToolsOpen = false;
      if (has) {
        _effectStartSec = 0;
        _effectEndSec = null; // full project
      }
    });
  }

  void _closeEffectsTools() {
    setState(() {
      _effectsToolsOpen = false;
      _effectsTrackSelected = false;
      _tool = null;
    });
  }

  void _handleEffectsToolTap(String id) {
    if (!_effectsTrackSelected && id != 'add') return;
    switch (id) {
      case 'add':
        setState(() {
          _tool = VideoEditorTool.effects;
          _effectsToolsOpen = false;
        });
        return;
      case 'delete':
        setState(() {
          _overlayEffect = null;
          _effectsTrackSelected = false;
          _effectStartSec = 0;
          _effectEndSec = null;
        });
        return;
      case 'clip_start':
        {
          const step = 0.5;
          final end = _effectEndSec ?? _totalDurationSec;
          if (_effectStartSec <= 0.001) return;
          setState(() {
            _effectStartSec =
                (_effectStartSec - step).clamp(0.0, end - 0.5);
          });
          return;
        }
      case 'clip_end':
        {
          const step = 0.5;
          final videoEnd = _totalDurationSec;
          final curEnd = _effectEndSec ?? videoEnd;
          if (curEnd >= videoEnd - 0.001) return;
          setState(() {
            _effectEndSec =
                (curEnd + step).clamp(_effectStartSec + 0.5, videoEnd);
          });
          return;
        }
    }
  }

  void _openTextTools({String? editOverlayId}) {
    unawaited(_pausePreview());
    if (editOverlayId != null) {
      final o = _textOverlays.overlays.where((e) => e.id == editOverlayId).firstOrNull;
      _textFieldController.text = o?.text ?? '';
      _selectedTextOverlayId = editOverlayId;
    } else {
      // Navbar Text always starts a *new* text (slideshow parity).
      _textFieldController.text = '';
      _selectedTextOverlayId = null;
    }
    setState(() {
      _tool = null;
      _animSheetOpen = false;
      _speedSheetOpen = false;
      _musicToolsOpen = false;
      _musicVolumeOpen = false;
      _effectsToolsOpen = false;
      _textToolsOpen = true;
      _selectedClipIndex = null;
    });
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
  }

  /// Filmstrip body + bottom navbar — fixed so preview never jumps on sheet open/close.
  double get _bottomWorkspaceH =>
      (_timelinePanelH - _timelineHeaderH) +
      AppResponsive.of(context).h(72);

  double get _mediaToolSheetHeight => _bottomWorkspaceH;

  Future<void> _addMoreClips() async {
    final result = await context.push<List<String>>(
      '/gallery?type=video&insert=1',
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      _clips.addAll(result);
      _ensureTrimSlots();
    });
    for (final path in result) {
      unawaited(_probeDurationOnly(path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final filter = _filters[_filterIndex].$2;

    return Scaffold(
      // Keep preview fixed while keyboard lifts TextToolsSheet (slideshow parity).
      resizeToAvoidBottomInset: false,
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
                  const SnackBar(content: Text('Video export coming soon')),
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
          Expanded(
            child: ColoredBox(
              color: _bgColor,
              // CapCut-style: full preview is canvas; video keeps native
              // aspect (contain). In-anim / overlays clip to video rect only.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_ready || _controller == null) {
                    return const PreparingPreviewOverlay();
                  }

                  final videoSize = _controller!.value.size;
                  final nativeAr = (videoSize.width > 0 && videoSize.height > 0)
                      ? videoSize.width / videoSize.height
                      : (_aspectW / _aspectH);
                  // After Resize, preview frame follows crop window aspect.
                  final crop = _cropFor(_activeIndex);
                  final videoAr = (crop != null &&
                          !crop.isIdentity &&
                          crop.height > 0 &&
                          videoSize.width > 0 &&
                          videoSize.height > 0)
                      ? (crop.width * videoSize.width) /
                          (crop.height * videoSize.height)
                      : nativeAr;
                  final maxW = constraints.maxWidth;
                  final maxH = constraints.maxHeight;
                  late final double frameW;
                  late final double frameH;
                  if (maxW / maxH > videoAr) {
                    frameH = maxH;
                    frameW = frameH * videoAr;
                  } else {
                    frameW = maxW;
                    frameH = frameW / videoAr;
                  }

                  return Center(
                    child: SizedBox(
                      width: frameW,
                      height: frameH,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            _buildPlayer(filter),
                            // CapCut In-anim — predecoded frames (no blink).
                            if (_revealOverlayActive &&
                                _activeRevealId != null &&
                                (_revealImages[_activeRevealId]?.isNotEmpty ??
                                    false))
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _buildRevealOverlayLayer(),
                                ),
                              ),
                            // CapCut live FX overlay (screen-blend frames).
                            if (_overlayEffect != null)
                              Positioned.fill(
                                child: _VideoLiveEffectOverlay(
                                  effect: _overlayEffect!,
                                  positionSec: _globalPositionSec,
                                  startSec: _effectStartSec,
                                  endSec: _effectEndSec ?? _totalDurationSec,
                                  onFramesReady: (_) {
                                    if (_effectPreviewLoading && mounted) {
                                      setState(
                                        () => _effectPreviewLoading = false,
                                      );
                                    }
                                  },
                                ),
                              ),
                            if (_effectPreviewLoading)
                              const Positioned.fill(
                                child: PreparingPreviewOverlay(),
                              ),
                            // CapCut live text: move / rotate / scale handles.
                            LiveTextOverlaysLayer(
                              project: _textOverlays,
                              selectedOverlayId: _selectedTextOverlayId,
                              onSelectedOverlayId: (id) {
                                setState(() {
                                  _selectedTextOverlayId = id;
                                  if (id != null) {
                                    final o = _textOverlays.overlays
                                        .where((e) => e.id == id)
                                        .firstOrNull;
                                    if (o?.text != null) {
                                      _textFieldController.text = o!.text!;
                                    }
                                  }
                                });
                              },
                              onEditOverlay: (id) => _openTextTools(
                                editOverlayId: id,
                              ),
                              editing: _textToolsOpen,
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
                            // Selection outline (teal — avoid FX green-screen color).
                            if (_selectedClipIndex != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // CapCut: loading while decoding selected In/Out FX
                            // or preparing a new playback speed.
                            if (_animPreviewLoading || _speedPreviewLoading)
                              const Positioned.fill(
                                child: PreparingPreviewOverlay(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Fixed play / time / undo row (never jumps when Animation/Speed opens).
          _buildPlaybackBar(rs),
          // Fixed height: Animation close must not resize the preview ("bari").
          SizedBox(
            height: _bottomWorkspaceH,
            width: double.infinity,
            // No AnimatedSwitcher cross-fade: keeping the outgoing timeline
            // mounted attaches `_stripController` to two ListViews → assert.
            child: _clipEditorSheetOpen || _mediaToolSheetOpen
                ? KeyedSubtree(
                    key: ValueKey(
                      _animSheetOpen
                          ? 'anim_sheet'
                          : _speedSheetOpen
                              ? 'speed_sheet'
                              : _tool == VideoEditorTool.music
                                  ? 'music_sheet'
                                  : 'effects_sheet',
                    ),
                    child: _animSheetOpen
                        ? _buildClipAnimationSheet(rs)
                        : _speedSheetOpen
                            ? _buildClipSpeedSheet(rs)
                            : _tool == VideoEditorTool.music
                                ? _buildMusicToolSheet(rs)
                                : _buildEffectsToolSheet(rs),
                  )
                : KeyedSubtree(
                    key: const ValueKey('timeline_workspace'),
                    child: Column(
                      children: [
                        // Volume UI replaces the timeline (red area); navbar stays.
                        Expanded(
                          child: _musicToolsOpen && _musicVolumeOpen
                              ? _buildMusicVolumeSheet(rs)
                              : _buildTimelineFilmstripPanel(rs),
                        ),
                        if (_selectedClipIndex != null)
                          _buildClipToolsNavbar(rs)
                        else if (_musicToolsOpen)
                          _buildMusicEditorToolbar(rs)
                        else if (_effectsToolsOpen)
                          _buildEffectsEditorToolbar(rs)
                        else
                          _buildBottomTools(rs),
                      ],
                    ),
                  ),
          ),
          // Filter/sticker/… panels stay below (optional extra chrome).
          if (_selectedClipIndex == null &&
              _tool != null &&
              !_mediaToolSheetOpen &&
              !_textToolsOpen &&
              !_clipEditorSheetOpen)
            _buildToolPanel(rs),
            ],
          ),
          // Slideshow-identical TextToolsSheet overlay (keyboard lifts sheet only).
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
                  final bodyH = (hasOverlay && !keyboardOpen)
                      ? TextToolsSheet.sheetBodyHeight
                      : 64.0;
                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
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
                          project: _textOverlays,
                          controller: _textFieldController,
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

  /// CapCut: pause preview when opening tools / Animation.
  Future<void> _pausePreview() async {
    _playToggleGen++; // invalidate in-flight play→BGM→resume
    final c = _controller;
    if (c == null || !_ready) {
      await _pauseBgm();
      return;
    }
    if (c.value.isPlaying || _playing || _bgmPlayer.playing) {
      await c.pause();
      await _pauseBgm();
      _syncRevealOverlayFromMain();
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _pauseBgm() async {
    try {
      await _bgmPlayer.pause();
    } catch (_) {}
  }

  Future<void> _stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  /// Music window on the project timeline: [start, end).
  (double, double) _musicTimelineRange([MusicTrack? track]) {
    final m = track ?? _music;
    final total = _totalDurationSec;
    if (m == null) return (0.0, 0.0);
    final start = m.timelineStartSec.clamp(0.0, total);
    final end = (m.timelineEndSec ?? total).clamp(start + 0.1, total);
    return (start, end);
  }

  /// Probe file/asset length so the lane matches real music duration.
  Future<double?> _probeMusicDurationSec(MusicTrack track) async {
    if (track.duration != null && track.duration!.inMilliseconds > 0) {
      return track.duration!.inMilliseconds / 1000.0;
    }
    final player = AudioPlayer();
    try {
      final d = track.isAsset
          ? await player.setAsset(track.path)
          : await player.setFilePath(track.path);
      final resolved = d ?? player.duration;
      if (resolved == null || resolved.inMilliseconds <= 0) return null;
      return resolved.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  /// Mix committed music with video — plays once, no loop past music end.
  Future<void> _syncBgmToPlayhead({bool forceSeek = true}) async {
    final m = _music;
    if (m == null || _stoppedAtClipEnd) {
      await _pauseBgm();
      return;
    }
    final videoSec = _globalPositionSec;
    final total = _totalDurationSec;
    if (videoSec >= total - 0.04) {
      await _pauseBgm();
      return;
    }
    final (tStart, tEnd) = _musicTimelineRange(m);
    if (videoSec < tStart || videoSec >= tEnd) {
      await _pauseBgm();
      return;
    }
    try {
      if (_bgmPath != m.path) {
        if (m.isAsset) {
          await _bgmPlayer.setAsset(m.path);
        } else {
          await _bgmPlayer.setFilePath(m.path);
        }
        _bgmPath = m.path;
      }
      await _bgmPlayer.setVolume((m.volume / 100.0).clamp(0.0, 1.0));
      final clipStart = m.clipStartSec;
      final sourceDur = m.duration?.inMilliseconds != null
          ? m.duration!.inMilliseconds / 1000.0
          : (_bgmPlayer.duration?.inMilliseconds ?? 60000) / 1000.0;
      final clipEnd =
          (m.clipEndSec ?? sourceDur).clamp(clipStart + 0.1, sourceDur);
      final clipLen = math.max(0.1, clipEnd - clipStart);
      final into = videoSec - tStart;
      // Do not loop: once past the music clip, stay silent.
      if (into >= clipLen - 0.02) {
        await _pauseBgm();
        return;
      }
      final audioSec = clipStart + into;
      if (forceSeek || !_bgmPlayer.playing) {
        await _bgmPlayer.seek(
          Duration(milliseconds: (audioSec * 1000).round()),
        );
      }
      if (!_bgmPlayer.playing) {
        await _bgmPlayer.play();
      }
    } catch (_) {
      // Preview still works if BGM fails.
    }
  }

  /// X on Music picker — discard draft, keep previously committed music.
  void _cancelMusicPicker() {
    setState(() {
      _musicDraft = null;
      _tool = null;
    });
  }

  /// ✓ on Music picker — commit draft onto timeline, then music tools navbar.
  Future<void> _confirmMusicPicker() async {
    final draft = _musicDraft;
    final total = _totalDurationSec;
    MusicTrack? committed;
    if (draft != null) {
      final probed = await _probeMusicDurationSec(draft);
      if (!mounted) return;
      final musicDur = (probed ??
              (draft.duration?.inMilliseconds ?? 0) / 1000.0)
          .clamp(0.5, 36000.0);
      // From video start: lane length = min(music, video).
      final end = math.min(total, musicDur).toDouble();
      committed = draft.copyWith(
        duration: probed != null
            ? Duration(milliseconds: (probed * 1000).round())
            : draft.duration,
        timelineStartSec: 0,
        timelineEndSec: end,
        clipStartSec: 0,
        clearClipEnd: true,
      );
    }
    setState(() {
      _music = committed;
      _musicDraft = null;
      _bgmPath = null;
      _tool = null;
      _musicToolsOpen = true;
      _musicVolumeOpen = false;
      _musicTrackSelected = committed != null;
      _effectsToolsOpen = false;
      _selectedClipIndex = null;
    });
    unawaited(_stopBgm());
  }

  void _closeMusicTools() {
    setState(() {
      _musicToolsOpen = false;
      _musicVolumeOpen = false;
      _musicTrackSelected = false;
      _tool = null;
    });
  }

  Future<void> _clearCommittedMusic() async {
    setState(() {
      _music = null;
      _musicDraft = null;
      _musicTrackSelected = false;
      _musicVolumeOpen = false;
      _bgmPath = null;
    });
    await _stopBgm();
  }

  void _handleMusicToolTap(String id) {
    if (!_musicTrackSelected && id != 'add') return;
    switch (id) {
      case 'add':
      case 'replace':
        setState(() {
          _musicVolumeOpen = false;
          _musicToolsOpen = false;
          _musicDraft = _music;
          _tool = VideoEditorTool.music;
        });
        unawaited(_pausePreview());
        return;
      case 'volume':
        setState(() => _musicVolumeOpen = true);
        return;
      case 'edit':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Music edit coming soon')),
        );
        return;
      case 'delete':
        unawaited(_clearCommittedMusic());
        return;
    }
  }

  /// Fills the already-sized video frame (native aspect, CapCut contain).
  /// Applies per-clip Resize (crop + rotate) when set.
  Widget _buildPlayer(ColorFilter? filter) {
    Widget player = VideoPlayer(_controller!);
    if (filter != null) {
      player = ColorFiltered(colorFilter: filter, child: player);
    }
    final crop = _cropFor(_activeIndex);
    if (crop == null || crop.isIdentity) return player;

    final rad = crop.degrees * math.pi / 180;
    final cover = () {
      final a = crop.degrees.abs() * math.pi / 180;
      final c = math.cos(a);
      final s = math.sin(a);
      final vs = _controller?.value.size;
      final w = (vs != null && vs.width > 0) ? vs.width : 1.0;
      final h = (vs != null && vs.height > 0) ? vs.height : 1.0;
      return math.max((w * c + h * s) / w, (w * s + h * c) / h);
    }();

    // Align crop window center; scale so crop rect fills the preview frame.
    final cx = (crop.left + crop.width / 2).clamp(0.0, 1.0);
    final cy = (crop.top + crop.height / 2).clamp(0.0, 1.0);
    final align = Alignment(cx * 2 - 1, cy * 2 - 1);
    final zoom = math.max(1.0 / crop.width, 1.0 / crop.height) * cover;

    return ClipRect(
      child: Transform.rotate(
        angle: rad,
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: align,
          child: Transform.scale(
            scale: zoom / cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: player,
            ),
          ),
        ),
      ),
    );
  }

  /// Fixed chrome under preview: time + play/pause + undo/redo.
  Widget _buildPlaybackBar(AppResponsive rs) {
    return Container(
      height: _timelineHeaderH,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(left: rs.w(14), right: rs.w(6)),
      child: _timelineHeaderRow(rs),
    );
  }

  /// Filmstrip + playhead only (playback bar is fixed above).
  /// Height comes from parent [Expanded] so sheet open/close keeps preview stable.
  Widget _buildTimelineFilmstripPanel(AppResponsive rs) {
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final playheadX = constraints.maxWidth / 2;
          return Stack(
            children: [
              Positioned.fill(child: _videoFilmstrip(rs, playheadX)),
              Positioned(
                left: playheadX - 1,
                top: 0,
                bottom: rs.h(36),
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

  Widget _timelineHeaderRow(AppResponsive rs) {
    return Row(
      children: [
        SizedBox(
          width: rs.w(96),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_fmtSec(_globalPositionSec)} / ${_fmtSec(_totalDurationSec)}',
              style: TextStyle(
                fontSize: rs.sp(12),
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: _playButtonEnabled ? _togglePlay : null,
              icon: Icon(
                _playing || _animPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: rs.r(32),
                color: _playButtonEnabled ? Colors.black87 : Colors.black26,
              ),
            ),
          ),
        ),
        SizedBox(
          width: rs.w(96),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                Icons.undo_rounded,
                color: AppColors.textMuted,
                size: rs.r(22),
              ),
              SizedBox(width: rs.w(12)),
              Icon(
                Icons.redo_rounded,
                color: AppColors.textMuted,
                size: rs.r(22),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _hasMusicLane => _music != null;
  bool get _hasEffectLane => _overlayEffect != null;

  Widget _videoFilmstrip(AppResponsive rs, double playheadX) {
    final leftPad = playheadX.clamp(0.0, 800.0).toDouble();
    final pps = _pixelsPerSecond;
    final thumbH = _thumbH;
    final totalW = _totalDurationSec * pps;
    final hasMusic = _hasMusicLane;
    final hasEffect = _hasEffectLane;
    final lineH = rs.h(6);
    // CapCut: full purple bar when tools open / track selected.
    final effectLaneH = (_effectsToolsOpen || _effectsTrackSelected)
        ? rs.h(34)
        : lineH;
    final musicLaneH = (_musicToolsOpen || _musicTrackSelected)
        ? rs.h(34)
        : lineH;
    final rulerH = rs.h(18);
    final gapH = rs.h(4);
    final underH = (!hasMusic && !hasEffect)
        ? 0.0
        : (hasMusic && hasEffect
              ? effectLaneH + musicLaneH + rs.h(6)
              : (hasEffect ? effectLaneH : musicLaneH) + rs.h(4));
    const handleW = _SelectedVideoClip.handleW;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_selectedClipIndex != null) _clearClipSelection();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              controller: _stripController,
              scrollDirection: Axis.horizontal,
              physics: (_trimDragging)
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(leftPad, 0, playheadX, 0),
              children: [
                SizedBox(
                  width: totalW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: rulerH,
                        width: totalW,
                        child: CustomPaint(
                          painter: _TimelineRulerPainter(
                            totalSec: _totalDurationSec,
                            pixelsPerSecond: pps,
                            labelStyle: TextStyle(
                              fontSize: rs.sp(10),
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: gapH),
                      SizedBox(
                        height: thumbH,
                        width: totalW,
                        child: Row(
                          children: [
                            for (var i = 0; i < _clips.length; i++)
                              _clipFilmstripTile(
                                index: i,
                                width: _visibleDuration(i) * pps,
                                height: thumbH,
                                pps: pps,
                              ),
                          ],
                        ),
                      ),
                      if (underH > 0) ...[
                        SizedBox(height: rs.h(4)),
                        if (hasEffect)
                          _effectTimelineLane(
                            rs: rs,
                            width: totalW,
                            height: effectLaneH,
                            pps: pps,
                          ),
                        if (hasEffect && hasMusic) SizedBox(height: rs.h(2)),
                        if (hasMusic)
                          _musicTimelineLane(
                            rs: rs,
                            width: totalW,
                            height: musicLaneH,
                            pps: pps,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Selection chrome sits outside ListView (slideshow pattern) so
          // scroll is applied once via leftPad + startPx - scroll.
          if (_selectedClipIndex != null)
            ListenableBuilder(
              listenable: _stripController,
              builder: (context, _) {
                final sel = _selectedClipIndex!;
                if (sel < 0 || sel >= _clips.length) {
                  return const SizedBox.shrink();
                }
                var startPx = 0.0;
                for (var i = 0; i < sel; i++) {
                  startPx += _visibleDuration(i) * pps;
                }
                final clipW = _visibleDuration(sel) * pps;
                final scroll = _stripController.positions.length == 1
                    ? _stripController.offset
                    : 0.0;
                final left = leftPad + startPx - scroll - handleW;
                return Positioned(
                  left: left,
                  top: rulerH + gapH,
                  width: clipW + handleW * 2,
                  height: thumbH,
                  child: _SelectedVideoClip(
                    height: thumbH,
                    durationSec: _visibleDuration(sel),
                    pixelsPerSecond: pps,
                    thumbBuilder: (w, h) => _clipThumbContent(sel, w, h, pps),
                    // Trim handles: pan strip with finger, don't scrub-seek.
                    onScrollTimeline: (dx) {
                      if (_stripController.positions.length != 1) return;
                      final next = (_stripController.offset - dx).clamp(
                        0.0,
                        _stripController.position.maxScrollExtent,
                      );
                      _syncingStrip = true;
                      _stripController.jumpTo(next);
                      _syncingStrip = false;
                    },
                    // Body drag: CapCut scrub — move timeline + seek playhead.
                    onPanScrub: (dx) {
                      if (_stripController.positions.length != 1) return;
                      if (_playing) unawaited(_controller?.pause());
                      final next = (_stripController.offset - dx).clamp(
                        0.0,
                        _stripController.position.maxScrollExtent,
                      );
                      _userScrubbing = true;
                      _stripController.jumpTo(next);
                      final t = (next / pps)
                          .clamp(0.0, _totalDurationSec)
                          .toDouble();
                      _scrubTimer?.cancel();
                      _scrubTimer = Timer(const Duration(milliseconds: 40), () {
                        unawaited(_seekGlobal(t, fromScrub: true));
                      });
                    },
                    onDragStart: () {
                      setState(() => _trimDragging = true);
                    },
                    onLiveTrim: (inn, out) {
                      setState(() {
                        _liveTrimIn = inn;
                        _liveTrimOut = out;
                      });
                    },
                    onDragEnd: () {
                      setState(() {
                        _trimDragging = false;
                        _liveTrimIn = null;
                        _liveTrimOut = null;
                      });
                    },
                    onCommitTrim: (inn, out) {
                      _ensureTrimSlots();
                      setState(() {
                        _clipTrimIn[sel] = inn;
                        _clipTrimOut[sel] = out;
                      });
                      unawaited(
                        _controller?.seekTo(
                          Duration(milliseconds: (inn * 1000).round()),
                        ),
                      );
                    },
                    sourceIn: _trimIn(sel),
                    sourceOut: _trimOut(sel),
                    sourceDuration: _sourceDuration(sel),
                  ),
                );
              },
            ),
          if (_selectedClipIndex == null)
            Positioned(
              left: _stripPadLeft,
              top: rulerH + gapH,
              height: thumbH,
              child: GestureDetector(
                onTap: _addMoreClips,
                child: Container(
                  width: _plusW,
                  height: thumbH,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
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
        ],
      ),
    );
  }

  Widget _collapsedLane({
    required double width,
    required double height,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  /// CapCut purple effect bar under filmstrip (thumb + name).
  Widget _effectTimelineLane({
    required AppResponsive rs,
    required double width,
    required double height,
    required double pps,
  }) {
    final effect = _overlayEffect;
    if (effect == null) return const SizedBox.shrink();
    final total = _totalDurationSec;
    final start = _effectStartSec.clamp(0.0, total);
    final end = (_effectEndSec ?? total).clamp(start + 0.1, total);
    final left = start * pps;
    final barW = math.max(48.0, (end - start) * pps);
    final selected = _effectsTrackSelected || _effectsToolsOpen;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(
            left: left,
            width: barW,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _effectsToolsOpen = true;
                  _effectsTrackSelected = true;
                  _tool = null;
                  _selectedClipIndex = null;
                });
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF),
                  borderRadius: BorderRadius.circular(4),
                  border: selected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: height >= 24
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.asset(
                                effect.thumbPath,
                                width: height - 8,
                                height: height - 8,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(
                                  color: Colors.black26,
                                  child: SizedBox(
                                    width: height - 8,
                                    height: height - 8,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                effect.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: rs.sp(11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectMusicTrack() {
    setState(() {
      _musicToolsOpen = true;
      _musicTrackSelected = true;
      _musicVolumeOpen = false;
      _effectsToolsOpen = false;
      _effectsTrackSelected = false;
      _tool = null;
      _selectedClipIndex = null;
    });
  }

  /// CapCut purple music bar — length = music window; tap selects like clip.
  Widget _musicTimelineLane({
    required AppResponsive rs,
    required double width,
    required double height,
    required double pps,
  }) {
    final music = _music;
    if (music == null) return const SizedBox.shrink();
    final (start, end) = _musicTimelineRange(music);
    final left = start * pps;
    final barW = math.max(48.0, (end - start) * pps);
    final selected = _musicTrackSelected || _musicToolsOpen;
    const handleW = 22.0;

    Widget body() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF650CFF), Color(0xFF120799)],
            ),
          ),
          child: height >= 24
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _VideoMusicWavePainter()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.music_note,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              music.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: rs.sp(11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : const SizedBox.expand(),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: selected ? left - handleW : left,
            width: selected ? barW + handleW * 2 : barW,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _selectMusicTrack,
              child: selected
                  ? Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x29000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: handleW,
                            child: const Icon(
                              Icons.chevron_left,
                              size: 16,
                              color: Colors.black87,
                            ),
                          ),
                          Expanded(child: body()),
                          SizedBox(
                            width: handleW,
                            child: const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    )
                  : body(),
            ),
          ),
        ],
      ),
    );
  }

  /// Slideshow music tools: Back · Add · Replace · Edit · Volume.
  Widget _buildMusicEditorToolbar(AppResponsive rs) {
    final active = _musicTrackSelected;
    final actions =
        <({String id, String label, String? asset, IconData? icon})>[
      (id: 'add', label: 'Add', asset: 'add_music.png', icon: null),
      (id: 'replace', label: 'Replace', asset: 'replace.png', icon: null),
      (id: 'edit', label: 'Edit', asset: 'edit.png', icon: null),
      (id: 'volume', label: 'Volume', asset: 'volume.png', icon: null),
      (id: 'delete', label: 'Delete', asset: 'delete.png', icon: null),
    ];
    final color = active ? AppColors.textDark : AppColors.textMuted;
    return Container(
      height: rs.h(72),
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
                      onTap: () => _handleMusicToolTap(actions[i].id),
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

  /// Dual volume fills the timeline area; music tools navbar stays below.
  Widget _buildMusicVolumeSheet(AppResponsive rs) {
    final clipVol = (_volumeFor(_activeIndex) * 100).round().clamp(0, 100);
    final musicVol = (_music?.volume ?? 100).clamp(0, 100);
    Widget row({
      required String label,
      required IconData icon,
      required int value,
      required ValueChanged<double> onChanged,
    }) {
      return Row(
        children: [
          SizedBox(
            width: rs.w(72),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textMuted),
                SizedBox(width: rs.w(4)),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: rs.sp(12),
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: AppColors.primary,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _musicVolumeOpen = false),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const Expanded(
                  child: Text(
                    'Volume',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _musicVolumeOpen = false),
                  icon: const Icon(Icons.check, color: AppColors.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(rs.w(12), 0, rs.w(12), rs.h(8)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  row(
                    label: 'Original',
                    icon: Icons.videocam_outlined,
                    value: clipVol,
                    onChanged: (v) {
                      final next = (v / 100.0).clamp(0.0, 1.0);
                      _ensureTrimSlots();
                      setState(() => _clipVolumes[_activeIndex] = next);
                      unawaited(_controller?.setVolume(next));
                    },
                  ),
                  SizedBox(height: rs.h(8)),
                  row(
                    label: 'Music',
                    icon: Icons.music_note_outlined,
                    value: musicVol,
                    onChanged: (v) {
                      if (_music == null) return;
                      final next = v.round().clamp(0, 100);
                      setState(() {
                        _music = _music!.copyWith(volume: next);
                      });
                      unawaited(
                        _bgmPlayer.setVolume((next / 100.0).clamp(0.0, 1.0)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Slideshow CapCut effects tools: Back · Add · Delete · Clip start/end.
  Widget _buildEffectsEditorToolbar(AppResponsive rs) {
    final active = _effectsTrackSelected;
    final videoEnd = _totalDurationSec;
    final effectEnd = _effectEndSec ?? videoEnd;
    final canClipStart = active && _effectStartSec > 0.001;
    final canClipEnd = active && effectEnd < videoEnd - 0.001;
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
    return Container(
      height: rs.h(72),
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
                  Builder(
                    builder: (context) {
                      final id = actions[i].id;
                      final enabled = switch (id) {
                        'add' => true,
                        'clip_start' => canClipStart,
                        'clip_end' => canClipEnd,
                        _ => active,
                      };
                      final color =
                          enabled ? AppColors.textDark : AppColors.textMuted;
                      return SizedBox(
                        width: 76,
                        child: InkWell(
                          onTap: enabled
                              ? () => _handleEffectsToolTap(id)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Opacity(
                            opacity: enabled ? 1 : 0.45,
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
                      );
                    },
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

  Widget _clipThumbContent(int index, double width, double height, double pps) {
    final path = _clips[index];
    final frames = _filmstripFrames[path] ?? const <String>[];
    // Slot every ~0.5 timeline-sec so speed-scaled / short FX windows show
    // distinct frames (not two identical cells under the playhead).
    final visibleSec = math.max(0.1, width / pps);
    final slots = math.min(
      180,
      math.max(1, (visibleSec * 2).ceil()),
    );
    final inn = _trimIn(index);
    final speed = _speedFor(index);
    final span = _sourceSpan(index);
    final reveal = _revealFor(index);
    final outReveal = _outRevealFor(index);
    // CapCut: white In block at start, Out block at end (timeline seconds).
    final animDur = reveal == null ? 0.0 : _revealDurationFor(index);
    final markerW = reveal == null
        ? 0.0
        : (animDur * pps).clamp(10.0, math.max(10.0, width)).toDouble();
    final outDur = outReveal == null ? 0.0 : _outRevealDurationFor(index);
    final outMarkerW = outReveal == null
        ? 0.0
        : (outDur * pps).clamp(10.0, math.max(10.0, width)).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                for (var s = 0; s < slots; s++)
                  Expanded(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.white70, width: 1),
                        ),
                        color: Color(0xFF1C1C1E),
                      ),
                      child: Builder(
                        builder: (_) {
                          if (frames.isEmpty) {
                            return const Center(
                              child: Icon(
                                Icons.videocam_rounded,
                                color: Colors.white38,
                                size: 18,
                              ),
                            );
                          }
                          // Evenly sample timeline → source (speed) → strip frame.
                          final t = slots <= 1
                              ? 0.0
                              : (s + 0.5) / slots * visibleSec;
                          final srcTime =
                              (inn + t * speed).clamp(inn, inn + span);
                          final fi = (srcTime * _filmstripFps)
                              .floor()
                              .clamp(0, frames.length - 1);
                          return Image.file(
                            File(frames[fi]),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: Color(0xFF1C1C1E)),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
            // CapCut In-marker: white rounded block + duration (e.g. 1.0s).
            if (markerW > 0)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: markerW,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 4, top: 3, right: 4),
                  alignment: Alignment.topLeft,
                  child: Text(
                    '${animDur.toStringAsFixed(1)}s',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            // CapCut Out-marker at clip end.
            if (outMarkerW > 0)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: outMarkerW,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 4, top: 3, right: 4),
                  alignment: Alignment.topRight,
                  child: Text(
                    '${outDur.toStringAsFixed(1)}s',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: Color(0xFF111111),
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
    );
  }

  Widget _clipFilmstripTile({
    required int index,
    required double width,
    required double height,
    required double pps,
  }) {
    // Deselected by default — no cyan/blur border. Selection chrome is overlay.
    // Key on speed/width so strip remounts after Speed ✓ (no stale cells).
    final speedKey = _speedFor(index).toStringAsFixed(3);
    return GestureDetector(
      onTap: () => _selectClip(index),
      child: SizedBox(
        key: ValueKey('strip_${index}_${speedKey}_${width.toStringAsFixed(1)}'),
        width: width,
        height: height,
        child: _clipThumbContent(index, width, height, pps),
      ),
    );
  }

  /// CapCut Animation page: In/Out + FX thumbs + duration slider.
  Widget _buildClipAnimationSheet(AppResponsive rs) {
    final sel = _selectedClipIndex;
    final isOut = _animPhase == _VideoAnimPhase.outAnimation;
    final selectedId = sel == null
        ? null
        : (isOut
              ? (sel < _clipOutRevealIds.length
                    ? _clipOutRevealIds[sel]
                    : null)
              : (sel < _clipRevealIds.length ? _clipRevealIds[sel] : null));
    final options = isOut
        ? VideoRevealAnim.outCatalog
        : VideoRevealAnim.catalog;

    // Fills green area (filmstrip + clip tools). Playback bar stays fixed above.
    final sheetH = (_timelinePanelH - _timelineHeaderH) + rs.h(72);
    return SectionSheet(
      title: 'Animation',
      height: sheetH,
      compactHeader: true,
      showTopDivider: false,
      onClose: () {
        _clearAnimPreviewState(stopOverlay: true);
        setState(() {
          _animSheetOpen = false;
          _revealDurDrag = null;
        });
      },
      onConfirm: () {
        // CapCut: check → close sheet & park at start so full preview plays from beginning.
        unawaited(_confirmAnimSheetAndSeekStart());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                for (final phase in _VideoAnimPhase.values)
                  InkWell(
                    onTap: () {
                      if (_animPhase == phase) return;
                      _clearAnimPreviewState(stopOverlay: true);
                      setState(() {
                        _animPhase = phase;
                        _revealDurDrag = null;
                      });
                      // Re-prepare existing selection on the new tab (if any).
                      final sel = _selectedClipIndex;
                      if (sel == null) return;
                      final id = phase == _VideoAnimPhase.outAnimation
                          ? (sel < _clipOutRevealIds.length
                                ? _clipOutRevealIds[sel]
                                : null)
                          : (sel < _clipRevealIds.length
                                ? _clipRevealIds[sel]
                                : null);
                      final anim = VideoRevealAnim.byId(id);
                      if (anim != null) {
                        unawaited(
                          _prepareAnimPreview(
                            anim,
                            isOut: phase == _VideoAnimPhase.outAnimation,
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          Text(
                            switch (phase) {
                              _VideoAnimPhase.inAnimation => 'In',
                              _VideoAnimPhase.outAnimation => 'Out',
                            },
                            style: TextStyle(
                              fontSize: 13,
                              color: _animPhase == phase
                                  ? AppColors.textDark
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Container(
                            width: 18,
                            height: 2,
                            color: _animPhase == phase
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
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 12, 2),
              itemCount: options.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  final isSelected = selectedId == null;
                  return InkWell(
                    onTap: () {
                      if (sel == null) return;
                      _ensureTrimSlots();
                      _clearAnimPreviewState(stopOverlay: true);
                      setState(() {
                        if (isOut) {
                          _clipOutRevealIds[sel] = null;
                          _clipOutRevealDurSec[sel] = null;
                        } else {
                          _clipRevealIds[sel] = null;
                          _clipRevealDurSec[sel] = null;
                        }
                      });
                    },
                    child: SizedBox(
                      width: 78,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: PrimarySelectedBorder(
                              selected: isSelected,
                              borderRadius: 4,
                              width: 2,
                              unselectedColor: Colors.transparent,
                              unselectedWidth: 0,
                              child: const ColoredBox(
                                color: Color(0xFFF2F2F2),
                                child: Center(
                                  child: Icon(
                                    Icons.block,
                                    color: Color(0xFF9E9E9E),
                                    size: 28,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Text(
                            'None',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final anim = options[i - 1];
                final isSelected = selectedId == anim.id;
                return InkWell(
                  onTap: () {
                    if (sel == null) return;
                    _ensureTrimSlots();
                    setState(() {
                      if (isOut) {
                        _clipOutRevealIds[sel] = anim.id;
                        _clipOutRevealDurSec[sel] = anim.durationSec;
                      } else {
                        _clipRevealIds[sel] = anim.id;
                        _clipRevealDurSec[sel] = anim.durationSec;
                      }
                    });
                    // Loading on preview → ready → user presses play for FX-only.
                    Future<void> prepare() async {
                      await _prepareAnimPreview(anim, isOut: isOut);
                    }

                    if (_activeIndex != sel) {
                      unawaited(_loadClip(sel).then((_) => prepare()));
                    } else {
                      unawaited(prepare());
                    }
                  },
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: PrimarySelectedBorder(
                            selected: isSelected,
                            borderRadius: 4,
                            width: 2,
                            unselectedColor: Colors.transparent,
                            unselectedWidth: 0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: ColoredBox(
                                color: Colors.black,
                                child: Image.asset(
                                  anim.thumbPath,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(
                                      Icons.movie_filter_rounded,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          anim.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
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
        ],
      ),
    );
  }

  Widget _buildClipToolsNavbar(AppResponsive rs) {
    // Prefer editor assets. Speed: temporary Icon until photo_tools/speed.png.
    const actions = <(_ClipEditTool, String, IconData?, String?)>[
      (
        _ClipEditTool.volume,
        'Volume',
        null,
        'assets/images/editor/music_tools/volume.png',
      ),
      (
        _ClipEditTool.animation,
        'Animation',
        null,
        'assets/images/editor/photo_tools/animation.png',
      ),
      (
        _ClipEditTool.delete,
        'Delete',
        null,
        'assets/images/editor/photo_tools/delete.png',
      ),
      // TODO: replace Icon when asset provided → photo_tools/speed.png
      (_ClipEditTool.speed, 'Speed', Icons.speed_rounded, null),
      (
        _ClipEditTool.crop,
        'Crop',
        null,
        'assets/images/editor/photo_tools/crop.png',
      ),
      (
        _ClipEditTool.replace,
        'Replace',
        null,
        'assets/images/editor/photo_tools/replace.png',
      ),
    ];

    // Match slideshow `_photoEditorToolbar` icon size / spacing / chrome.
    return Container(
      height: rs.h(72),
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
                for (final a in actions)
                  SizedBox(
                    width: 72,
                    child: InkWell(
                      onTap: () => _handleClipTool(a.$1),
                      borderRadius: BorderRadius.circular(8),
                      child: Builder(
                        builder: (context) {
                          final asset = a.$4;
                          final isAnim =
                              asset != null && asset.endsWith('animation.png');
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(height: isAnim ? 4 : 0),
                              if (asset != null)
                                Image.asset(
                                  asset,
                                  width: 28,
                                  height: isAnim ? 23 : 28,
                                  color: AppColors.iconNormal,
                                  colorBlendMode: BlendMode.srcIn,
                                )
                              else
                                Icon(
                                  a.$3,
                                  size: 26,
                                  color: AppColors.iconNormal,
                                ),
                              SizedBox(height: isAnim ? 6 : 4),
                              Text(
                                a.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          );
                        },
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
                  onPressed: _clearClipSelection,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Adjust original clip audio. Close = discard, check = apply (screenshot).
  Future<void> _openClipVolumeSheet(int index) async {
    _ensureTrimSlots();
    final committed = _volumeFor(index);
    var draft = committed;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            void preview(double v) {
              draft = v.clamp(0.0, 1.0);
              setModal(() {});
              if (_activeIndex == index) {
                unawaited(_controller?.setVolume(draft));
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.textDark,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Volume',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(
                            Icons.check,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.volume_up_outlined,
                            color: AppColors.textMuted,
                          ),
                          Expanded(
                            child: Slider(
                              value: draft * 100,
                              min: 0,
                              max: 100,
                              divisions: 100,
                              activeColor: AppColors.primary,
                              onChanged: (v) => preview(v / 100),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${(draft * 100).round()}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _clipVolumes[index] = draft);
      if (_activeIndex == index) {
        unawaited(_controller?.setVolume(draft));
      }
    } else {
      // Close / dismiss → restore committed original-clip volume.
      if (_activeIndex == index) {
        unawaited(_controller?.setVolume(committed));
      }
    }
  }

  String _fmtSpeedDuration(double sec) {
    if (sec < 60) return '${sec.toStringAsFixed(1)}s';
    final total = sec.round().clamp(0, 999999);
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// CapCut Resize page — full-screen crop / rotate / aspect for one clip.
  Future<void> _openClipResize(int index) async {
    if (index < 0 || index >= _clips.length) return;
    _ensureTrimSlots();
    await _pausePreview();
    if (!mounted) return;
    final result = await Navigator.of(context).push<VideoClipCrop>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoResizeScreen(
          videoPath: _clips[index],
          initial: _cropFor(index),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _clipCrops[index] = result.isIdentity ? null : result;
    });
  }

  void _openClipSpeedSheet(int index) {
    _ensureTrimSlots();
    _clearAnimPreviewState(stopOverlay: true);
    // Use committed list value (not draft) when opening.
    final maxS = _ClipSpeedLimits.selectMax(_sourceSpan(index));
    final committed = (index >= 0 && index < _clipSpeeds.length)
        ? _clipSpeeds[index].clamp(_ClipSpeedLimits.minSpeed, maxS)
        : 1.0;
    final pitch =
        index < _clipChangePitch.length ? _clipChangePitch[index] : false;
    setState(() {
      _speedSheetOpen = true;
      _animSheetOpen = false;
      _tool = null;
      _speedCommittedOnOpen = committed;
      _pitchCommittedOnOpen = pitch;
      _speedDraft = committed;
      _pitchDraft = pitch;
      _speedPreviewLoading = false;
      _speedPreviewReady = true;
    });
  }

  /// Timeline global sec for a source position at a given clip speed.
  double _globalForSourceAtSpeed(double sourcePosSec, double speed) {
    var before = 0.0;
    for (var i = 0; i < _activeIndex && i < _clips.length; i++) {
      before += _visibleDuration(i);
    }
    final inn = _trimIn(_activeIndex);
    final local = (sourcePosSec - inn).clamp(0.0, _sourceSpan(_activeIndex));
    return before +
        local / speed.clamp(_ClipSpeedLimits.minSpeed, 100.0);
  }

  /// Loading → set rate → remap playhead → rebuild strip → ready (play enabled).
  Future<void> _prepareSpeedPreview(
    double speed, {
    double? previousSpeed,
  }) async {
    final gen = ++_speedPrepareGen;
    final maxS = _ClipSpeedLimits.selectMax(_sourceSpan(_activeIndex));
    final next = speed.clamp(_ClipSpeedLimits.minSpeed, maxS);
    final c = _controller;
    final sourcePosSec =
        (c?.value.position.inMilliseconds ?? _position.inMilliseconds) /
        1000.0;
    final fromSpeed = (previousSpeed ?? _speedDraft)
        .clamp(_ClipSpeedLimits.minSpeed, maxS);
    final keepGlobal = _globalForSourceAtSpeed(sourcePosSec, fromSpeed);

    if (mounted) {
      setState(() {
        _speedDraft = next;
        _speedPreviewLoading = true;
        _speedPreviewReady = false;
        _playing = false;
      });
    }
    if (c == null || !_ready) {
      if (mounted && gen == _speedPrepareGen) {
        setState(() {
          _speedPreviewLoading = false;
          _speedPreviewReady = true;
        });
      }
      return;
    }
    try {
      if (c.value.isPlaying) await c.pause();
      final rate = _previewPlaybackRate(next);
      try {
        await c.setPlaybackSpeed(rate);
      } catch (_) {
        // Some devices reject very high rates — fall back so preview still works.
        await c.setPlaybackSpeed(rate.clamp(0.1, 8.0));
      }
      // Keep playhead on same timeline mark; preview seeks to matching source.
      await _seekGlobal(keepGlobal);
      if (!mounted || gen != _speedPrepareGen) return;

      // Rebuild timeline at new visible width (stretch/shrink).
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      // Await full filmstrip — never enable play on empty/poster-only strip.
      final path = _clips[_activeIndex];
      await _ensureFilmstrip(path);
      if (!mounted || gen != _speedPrepareGen) return;

      // Second seek warms decoder at new rate so first play isn't choppy.
      await _seekGlobal(keepGlobal);
      if (!mounted || gen != _speedPrepareGen) return;
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || gen != _speedPrepareGen) return;

      setState(() {
        _speedPreviewLoading = false;
        _speedPreviewReady = true;
        _playing = false;
      });
      _syncStripToPlayhead();
    } catch (_) {
      if (!mounted || gen != _speedPrepareGen) return;
      setState(() {
        _speedPreviewLoading = false;
        _speedPreviewReady = true;
      });
    }
  }

  Future<void> _closeSpeedSheet({required bool commit}) async {
    final sel = _selectedClipIndex;
    if (sel == null) {
      setState(() {
        _speedSheetOpen = false;
        _speedPreviewLoading = false;
        _speedPreviewReady = true;
      });
      return;
    }
    // Speed currently driving timeline/preview (draft while sheet open).
    final previousSpeed = _speedFor(sel);
    final maxS = _ClipSpeedLimits.selectMax(_sourceSpan(sel));
    final targetSpeed = commit
        ? _speedDraft.clamp(_ClipSpeedLimits.minSpeed, maxS)
        : _speedCommittedOnOpen.clamp(_ClipSpeedLimits.minSpeed, maxS);
    // Close sheet + lock play immediately; await full ready before play enables.
    setState(() {
      if (commit) {
        _clipSpeeds[sel] = targetSpeed;
        _clipChangePitch[sel] = _pitchDraft;
      } else {
        _clipSpeeds[sel] = _speedCommittedOnOpen;
        _clipChangePitch[sel] = _pitchCommittedOnOpen;
        _speedDraft = _speedCommittedOnOpen;
        _pitchDraft = _pitchCommittedOnOpen;
      }
      _speedSheetOpen = false;
      _speedPreviewLoading = true;
      _speedPreviewReady = false;
      _playing = false;
    });
    await _prepareSpeedPreview(targetSpeed, previousSpeed: previousSpeed);
  }

  /// CapCut Speed sheet — same green-area SectionSheet as Animation.
  Widget _buildClipSpeedSheet(AppResponsive rs) {
    final sel = _selectedClipIndex;
    final sourceSec = sel == null ? 1.0 : _sourceSpan(sel);
    final sheetH = (_timelinePanelH - _timelineHeaderH) + rs.h(72);
    return SectionSheet(
      title: 'Speed',
      height: sheetH,
      compactHeader: true,
      showTopDivider: false,
      onClose: () => unawaited(_closeSpeedSheet(commit: false)),
      onConfirm: () => unawaited(_closeSpeedSheet(commit: true)),
      child: _SpeedSheetBody(
        sourceSec: sourceSec,
        initialSpeed: _speedDraft,
        initialPitch: _pitchDraft,
        fmtDuration: _fmtSpeedDuration,
        onDraftChanged: (speed, pitch) {
          _speedDraft = speed;
          _pitchDraft = pitch;
        },
        // Finger up: stretch timeline + loading until preview ready.
        onSpeedChangeEnd: (speed, previousSpeed) {
          unawaited(
            _prepareSpeedPreview(speed, previousSpeed: previousSpeed),
          );
        },
      ),
    );
  }

  Future<void> _handleClipTool(_ClipEditTool tool) async {
    final sel = _selectedClipIndex;
    if (sel == null || sel >= _clips.length) return;
    await _pausePreview();

    switch (tool) {
      case _ClipEditTool.volume:
        if (!mounted) return;
        await _openClipVolumeSheet(sel);
      case _ClipEditTool.animation:
        _clearAnimPreviewState(stopOverlay: true);
        setState(() {
          _animSheetOpen = true;
          _speedSheetOpen = false;
          _animPhase = _VideoAnimPhase.inAnimation;
          _tool = null;
        });
        // If clip already has an In FX, prepare it (loading → ready play).
        if (sel < _clipRevealIds.length) {
          final existing = VideoRevealAnim.byId(_clipRevealIds[sel]);
          if (existing != null) {
            unawaited(_prepareAnimPreview(existing, isOut: false));
          }
        }
      case _ClipEditTool.delete:
        if (!mounted) return;
        if (_clips.length <= 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Keep at least one clip')),
          );
          return;
        }
        setState(() {
          _clips.removeAt(sel);
          if (sel < _clipTrimIn.length) {
            _clipTrimIn.removeAt(sel);
            _clipTrimOut.removeAt(sel);
          }
          if (sel < _clipVolumes.length) {
            _clipVolumes.removeAt(sel);
          }
          if (sel < _clipSpeeds.length) {
            _clipSpeeds.removeAt(sel);
          }
          if (sel < _clipChangePitch.length) {
            _clipChangePitch.removeAt(sel);
          }
          if (sel < _clipRevealIds.length) {
            _clipRevealIds.removeAt(sel);
          }
          if (sel < _clipRevealDurSec.length) {
            _clipRevealDurSec.removeAt(sel);
          }
          if (sel < _clipOutRevealIds.length) {
            _clipOutRevealIds.removeAt(sel);
          }
          if (sel < _clipOutRevealDurSec.length) {
            _clipOutRevealDurSec.removeAt(sel);
          }
          if (sel < _clipCrops.length) {
            _clipCrops.removeAt(sel);
          }
          _ensureTrimSlots();
          _animSheetOpen = false;
          _speedSheetOpen = false;
          _selectedClipIndex = null;
        });
        await _loadClip(sel.clamp(0, _clips.length - 1));
      case _ClipEditTool.speed:
        if (!mounted) return;
        _openClipSpeedSheet(sel);
      case _ClipEditTool.crop:
        if (!mounted) return;
        await _openClipResize(sel);
      case _ClipEditTool.replace:
        final result = await context.push<List<String>>(
          '/gallery?type=video&insert=1',
        );
        if (!mounted || result == null || result.isEmpty) return;
        setState(() {
          _clips[sel] = result.first;
          _ensureTrimSlots();
          _clipVolumes[sel] = 1.0;
          _clipSpeeds[sel] = 1.0;
          _clipChangePitch[sel] = false;
          _clipRevealIds[sel] = null;
          _clipRevealDurSec[sel] = null;
          _clipOutRevealIds[sel] = null;
          _clipOutRevealDurSec[sel] = null;
          _clipCrops[sel] = null;
          _clipTrimIn[sel] = null;
          _clipTrimOut[sel] = null;
        });
        unawaited(_probeDurationOnly(result.first));
        await _loadClip(sel);
    }
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
              selected: _tool == t ||
                  (t == VideoEditorTool.text && _textToolsOpen) ||
                  (t == VideoEditorTool.music && _musicToolsOpen) ||
                  (t == VideoEditorTool.effects && _effectsToolsOpen),
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
    // Text / Music / Effects use fullscreen green-area sheets (slideshow parity).
    return Container(
      height: rs.h(150),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: switch (_tool!) {
        VideoEditorTool.filters => _filtersPanel(rs),
        VideoEditorTool.sticker => _stickerPanel(rs),
        VideoEditorTool.aspectRatio => _ratioPanel(rs),
        VideoEditorTool.background => _bgPanel(rs),
        VideoEditorTool.edit ||
        VideoEditorTool.text ||
        VideoEditorTool.music ||
        VideoEditorTool.effects =>
          const SizedBox.shrink(),
      },
    );
  }

  /// Music picker: audition only (sheet player). Top play stays disabled.
  Widget _buildMusicToolSheet(AppResponsive rs) {
    return EditorMusicPickerSheet(
      height: _mediaToolSheetHeight,
      selected: _musicDraft,
      localTracks: _localMusicTracks,
      onClose: _cancelMusicPicker,
      onConfirm: () => unawaited(_confirmMusicPicker()),
      onSelect: (track) {
        setState(() => _musicDraft = track);
        // Keep video paused while auditioning a track.
        unawaited(_pausePreview());
        unawaited(_stopBgm());
      },
      onOpenLibrary: () async {
        await context.push('/music');
      },
      onImportLocal: () => unawaited(_importLocalMusic()),
    );
  }

  Future<void> _importLocalMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;
    final title = p.basenameWithoutExtension(path);
    final track = MusicTrack(path: path, title: title, isAsset: false);
    setState(() {
      _localMusicTracks.removeWhere((t) => t.path == path);
      _localMusicTracks.insert(0, track);
      _musicDraft = track;
    });
    unawaited(_pausePreview());
    unawaited(_stopBgm());
  }

  /// Slideshow-style Effects picker sheet.
  Widget _buildEffectsToolSheet(AppResponsive rs) {
    return EditorEffectsPickerSheet(
      height: _mediaToolSheetHeight,
      selectedId: _overlayEffect?.id,
      onClose: _finishEffectsPicker,
      onConfirm: () {
        if (_overlayEffect != null) {
          setState(() => _effectPreviewLoading = true);
        }
        _finishEffectsPicker();
      },
      onSelect: (effect) {
        setState(() {
          _overlayEffect = effect;
          if (effect != null) {
            _effectPreviewLoading = true;
            _effectStartSec = 0;
            _effectEndSec = null;
          }
        });
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
      (
        Icons.content_cut,
        'Split',
        () {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Split coming soon')));
        },
      ),
      (
        Icons.content_copy_outlined,
        'Duplicate',
        () {
          if (_clips.isEmpty) return;
          setState(() => _clips.insert(_activeIndex + 1, _clips[_activeIndex]));
        },
      ),
      (
        Icons.delete_outline,
        'Delete',
        () async {
          if (_clips.length <= 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Keep at least one clip')),
            );
            return;
          }
          setState(() => _clips.removeAt(_activeIndex));
          await _loadClip(_activeIndex.clamp(0, _clips.length - 1));
        },
      ),
      (
        Icons.speed,
        'Speed',
        () {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Speed coming soon')));
        },
      ),
      (
        Icons.volume_up_outlined,
        'Volume',
        () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Volume coming soon')));
        },
      ),
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
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
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
                        child: Text(
                          'None',
                          style: TextStyle(fontSize: rs.sp(11)),
                        ),
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
                    color: selected
                        ? AppColors.primarySoft
                        : AppColors.surfaceAlt,
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

/// CapCut/slideshow-style selected clip: white shell + trim handles.
class _SelectedVideoClip extends StatefulWidget {
  const _SelectedVideoClip({
    required this.height,
    required this.durationSec,
    required this.pixelsPerSecond,
    required this.thumbBuilder,
    required this.onScrollTimeline,
    required this.onPanScrub,
    required this.onDragStart,
    required this.onLiveTrim,
    required this.onDragEnd,
    required this.onCommitTrim,
    required this.sourceIn,
    required this.sourceOut,
    required this.sourceDuration,
  });

  static const handleW = 22.0;

  final double height;
  final double durationSec;
  final double pixelsPerSecond;
  final Widget Function(double width, double height) thumbBuilder;
  final ValueChanged<double> onScrollTimeline;

  /// Body drag → scrub timeline under playhead (CapCut).
  final ValueChanged<double> onPanScrub;
  final VoidCallback onDragStart;
  final void Function(double inn, double out) onLiveTrim;
  final VoidCallback onDragEnd;
  final void Function(double inn, double out) onCommitTrim;
  final double sourceIn;
  final double sourceOut;
  final double sourceDuration;

  @override
  State<_SelectedVideoClip> createState() => _SelectedVideoClipState();
}

class _SelectedVideoClipState extends State<_SelectedVideoClip> {
  static const _minVisible = 0.5;
  static const _shellPadV = 3.0;

  double? _liveIn;
  double? _liveOut;
  bool _dragging = false;

  double get _inn => _liveIn ?? widget.sourceIn;
  double get _out => _liveOut ?? widget.sourceOut;

  /// Timeline seconds — includes CapCut speed stretch (parent passes this).
  double get _timelineVisible =>
      widget.durationSec.clamp(_minVisible, 36000.0);

  void _begin() {
    if (_dragging) return;
    _dragging = true;
    _liveIn = widget.sourceIn;
    _liveOut = widget.sourceOut;
    widget.onDragStart();
    widget.onLiveTrim(_inn, _out);
  }

  void _end() {
    if (!_dragging) return;
    final inn = _inn;
    final out = _out;
    _dragging = false;
    _liveIn = null;
    _liveOut = null;
    widget.onCommitTrim(inn, out);
    widget.onDragEnd();
  }

  Widget _handle({required bool isStart}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
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
          _begin();
        },
        onHorizontalDragUpdate: (d) {
          if (d.delta.dx == 0) return;
          final deltaSec = d.delta.dx / widget.pixelsPerSecond;
          setState(() {
            if (isStart) {
              // Drag right → trim more from start.
              final next = (_inn + deltaSec)
                  .clamp(0.0, _out - _minVisible)
                  .toDouble();
              _liveIn = next;
            } else {
              final next = (_out + deltaSec)
                  .clamp(_inn + _minVisible, widget.sourceDuration)
                  .toDouble();
              _liveOut = next;
            }
          });
          widget.onLiveTrim(_inn, _out);
          widget.onScrollTimeline(-d.delta.dx);
        },
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        child: SizedBox(
          width: _SelectedVideoClip.handleW,
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
    // Must use timeline duration (speed-adjusted), not source trim span —
    // otherwise slow-mo leaves a white gap for the rest of the clip.
    final clipW = _timelineVisible * widget.pixelsPerSecond;
    final totalW = clipW + _SelectedVideoClip.handleW * 2;
    final thumbH = widget.height - _shellPadV * 2;

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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // keep selection
                onHorizontalDragUpdate: (d) {
                  if (d.delta.dx == 0) return;
                  widget.onPanScrub(d.delta.dx);
                },
                child: SizedBox(
                  width: clipW,
                  height: thumbH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.thumbBuilder(clipW, thumbH),
                      if (clipW >= 48)
                        Positioned(
                          left: 4,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${_timelineVisible.toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
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

/// Decorative waveform for the music timeline lane (slideshow parity).
class _VideoMusicWavePainter extends CustomPainter {
  const _VideoMusicWavePainter();

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

/// Time ruler: labels every 2s (00:00, 00:02, 00:04 …), minor tick each 1s.
class _TimelineRulerPainter extends CustomPainter {
  _TimelineRulerPainter({
    required this.totalSec,
    required this.pixelsPerSecond,
    required this.labelStyle,
  });

  final double totalSec;
  final double pixelsPerSecond;
  final TextStyle labelStyle;

  static const _labelEvery = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    final tickPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    final end = totalSec.ceil();
    for (var t = 0; t <= end; t++) {
      final x = t * pixelsPerSecond;
      if (x > size.width + 1) break;
      final isMajor = t % _labelEvery == 0;
      final h = isMajor ? size.height * 0.55 : size.height * 0.28;
      canvas.drawLine(
        Offset(x, size.height - h),
        Offset(x, size.height),
        tickPaint,
      );
      if (isMajor) {
        final m = t ~/ 60;
        final s = t % 60;
        final label =
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        textPainter.text = TextSpan(text: label, style: labelStyle);
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x + 2, (size.height - textPainter.height) / 2 - 1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return oldDelegate.totalSec != totalSec ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}

/// CapCut In-anim: paints one predecoded FX frame (smooth, no Image.file blink).
class _RevealFxPainter extends CustomPainter {
  _RevealFxPainter({required this.image, required this.blendMode});

  final ui.Image image;
  final BlendMode blendMode;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.cover,
      blendMode: blendMode,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _RevealFxPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.blendMode != blendMode;
}

/// Duration-based Normal speed limits.
/// Anchor: 20s source → selectable ≤1.5x, ruler shows ≤3x.
/// Longer clips unlock proportionally higher max (floored for short clips).
class _ClipSpeedLimits {
  static const minSpeed = 0.1;
  static const _refSec = 20.0;
  static const _refSelectMax = 1.5;
  static const _refRulerMax = 3.0;

  static double selectMax(double sourceSec) {
    final s = sourceSec.clamp(0.5, 36000.0);
    return (_refSelectMax * (s / _refSec)).clamp(_refSelectMax, 100.0);
  }

  static double rulerMax(double sourceSec) {
    final s = sourceSec.clamp(0.5, 36000.0);
    return (_refRulerMax * (s / _refSec)).clamp(_refRulerMax, 100.0);
  }

  static double _niceRulerMax(double raw) {
    const nice = <double>[3, 5, 10, 20, 50, 100];
    for (final n in nice) {
      if (raw <= n + 1e-6) return n;
    }
    return 100;
  }

  /// Major labels only (CapCut-like). 20s → 0.1 · 1 · 2 · 3.
  static List<double> marksFor(double rulerMax) {
    final end = _niceRulerMax(rulerMax);
    if (end <= 3) return const [0.1, 1, 2, 3];
    if (end <= 5) return const [0.1, 1, 2, 5];
    if (end <= 10) return const [0.1, 1, 2, 5, 10];
    if (end <= 20) return const [0.1, 1, 2, 5, 10, 20];
    if (end <= 50) return const [0.1, 1, 2, 5, 10, 50];
    return const [0.1, 1, 2, 5, 10, 100];
  }
}

/// Speed sheet body — local state so dragging doesn't rebuild VideoPlayer.
class _SpeedSheetBody extends StatefulWidget {
  const _SpeedSheetBody({
    required this.sourceSec,
    required this.initialSpeed,
    required this.initialPitch,
    required this.fmtDuration,
    required this.onDraftChanged,
    required this.onSpeedChangeEnd,
  });

  final double sourceSec;
  final double initialSpeed;
  final bool initialPitch;
  final String Function(double sec) fmtDuration;
  final void Function(double speed, bool pitch) onDraftChanged;
  final void Function(double speed, double previousSpeed) onSpeedChangeEnd;

  @override
  State<_SpeedSheetBody> createState() => _SpeedSheetBodyState();
}

class _SpeedSheetBodyState extends State<_SpeedSheetBody> {
  late double _speed;
  late bool _pitch;

  double get _selectMax => _ClipSpeedLimits.selectMax(widget.sourceSec);
  double get _rulerMax => _ClipSpeedLimits.rulerMax(widget.sourceSec);
  List<double> get _marks => _ClipSpeedLimits.marksFor(_rulerMax);

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed.clamp(_ClipSpeedLimits.minSpeed, _selectMax);
    _pitch = widget.initialPitch;
  }

  void _setSpeed(double speed, {required bool ended}) {
    final previous = _speed;
    final next = speed.clamp(_ClipSpeedLimits.minSpeed, _selectMax);
    setState(() => _speed = next);
    widget.onDraftChanged(next, _pitch);
    if (ended) widget.onSpeedChangeEnd(next, previous);
  }

  @override
  Widget build(BuildContext context) {
    final newDur = widget.sourceSec / _speed;
    final srcLabel = widget.sourceSec < 60
        ? '${widget.sourceSec.toStringAsFixed(1)}s'
        : widget.fmtDuration(widget.sourceSec);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
              children: [
                const TextSpan(text: 'Duration: '),
                TextSpan(text: '$srcLabel → '),
                TextSpan(
                  text: widget.fmtDuration(newDur),
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CapCutSpeedRuler(
            speed: _speed,
            marks: _marks,
            selectMax: _selectMax,
            onChanged: (s) => _setSpeed(s, ended: false),
            onChangeEnd: (s) => _setSpeed(s, ended: true),
          ),
          const Spacer(),
          InkWell(
            onTap: () {
              setState(() => _pitch = !_pitch);
              widget.onDraftChanged(_speed, _pitch);
            },
            borderRadius: BorderRadius.circular(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _pitch
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: _pitch ? AppColors.primary : AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Change audio pitch',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Duration-aware speed ruler: marks scale with clip length (e.g. 20s → …3x).
class _CapCutSpeedRuler extends StatefulWidget {
  const _CapCutSpeedRuler({
    required this.speed,
    required this.marks,
    required this.selectMax,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double speed;
  final List<double> marks;
  final double selectMax;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  static double speedToT(double speed, List<double> marks) {
    if (marks.length < 2) return 0.0;
    final s = speed.clamp(marks.first, marks.last);
    for (var i = 0; i < marks.length - 1; i++) {
      final a = marks[i];
      final b = marks[i + 1];
      if (s <= b || i == marks.length - 2) {
        final local = ((s - a) / (b - a)).clamp(0.0, 1.0);
        return (i + local) / (marks.length - 1);
      }
    }
    return 1.0;
  }

  static double tToSpeed(double t, List<double> marks) {
    if (marks.length < 2) return marks.isEmpty ? 1.0 : marks.first;
    final x = t.clamp(0.0, 1.0) * (marks.length - 1);
    final i = x.floor().clamp(0, marks.length - 2);
    final local = x - i;
    final a = marks[i];
    final b = marks[i + 1];
    final la = math.log(a);
    final lb = math.log(b);
    return math.exp(la + (lb - la) * local);
  }

  @override
  State<_CapCutSpeedRuler> createState() => _CapCutSpeedRulerState();
}

class _CapCutSpeedRulerState extends State<_CapCutSpeedRuler> {
  late double _t;
  bool _dragging = false;

  double get _tMax =>
      _CapCutSpeedRuler.speedToT(widget.selectMax, widget.marks);

  @override
  void initState() {
    super.initState();
    _t = _CapCutSpeedRuler.speedToT(widget.speed, widget.marks)
        .clamp(0.0, _tMax);
  }

  @override
  void didUpdateWidget(covariant _CapCutSpeedRuler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.speed != widget.speed ||
            oldWidget.selectMax != widget.selectMax ||
            oldWidget.marks.length != widget.marks.length)) {
      _t = _CapCutSpeedRuler.speedToT(widget.speed, widget.marks)
          .clamp(0.0, _tMax);
    }
  }

  void _updateFromDx(double dx, double width, {required bool ended}) {
    // Thumb cannot pass selectable max (ruler may still paint beyond).
    final nx = (dx / width).clamp(0.0, _tMax);
    setState(() {
      _t = nx;
      _dragging = !ended;
    });
    final speed = _CapCutSpeedRuler.tToSpeed(nx, widget.marks)
        .clamp(_ClipSpeedLimits.minSpeed, widget.selectMax);
    widget.onChanged(speed);
    if (ended) widget.onChangeEnd(speed);
  }

  String _label(double m) {
    if (m >= 10) return '${m.round()}x';
    if (m == m.roundToDouble()) return '${m.round()}x';
    return '${m}x';
  }

  @override
  Widget build(BuildContext context) {
    final marks = widget.marks;
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) =>
                    _updateFromDx(e.localPosition.dx, w, ended: false),
                onPointerMove: (e) =>
                    _updateFromDx(e.localPosition.dx, w, ended: false),
                onPointerUp: (e) =>
                    _updateFromDx(e.localPosition.dx, w, ended: true),
                onPointerCancel: (_) {
                  final speed =
                      _CapCutSpeedRuler.tToSpeed(_t, marks)
                          .clamp(_ClipSpeedLimits.minSpeed, widget.selectMax);
                  setState(() => _dragging = false);
                  widget.onChangeEnd(speed);
                },
                child: CustomPaint(
                  size: Size(w, 64),
                  painter: _CapCutSpeedRulerPainter(
                    t: _t,
                    markCount: marks.length,
                    selectT: _tMax,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < marks.length; i++)
              Expanded(
                child: Align(
                  alignment: i == 0
                      ? Alignment.centerLeft
                      : (i == marks.length - 1
                            ? Alignment.centerRight
                            : Alignment.center),
                  child: Text(
                    _label(marks[i]),
                    style: TextStyle(
                      fontSize: 11,
                      color: marks[i] <= widget.selectMax + 1e-6
                          ? AppColors.textMuted
                          : AppColors.textMuted.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CapCutSpeedRulerPainter extends CustomPainter {
  _CapCutSpeedRulerPainter({
    required this.t,
    required this.markCount,
    required this.selectT,
  });

  final double t;
  final int markCount;
  final double selectT;

  @override
  void paint(Canvas canvas, Size size) {
    final tickPaint = Paint()
      ..color = const Color(0xFFB0B0B5)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final dimPaint = Paint()
      ..color = const Color(0xFFD0D0D5)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final majorCount = math.max(2, markCount);
    const subdivisions = 10;
    final totalTicks = (majorCount - 1) * subdivisions;

    for (var i = 0; i <= totalTicks; i++) {
      final xFrac = i / totalTicks;
      final x = size.width * xFrac;
      final isMajor = i % subdivisions == 0;
      final isMid = !isMajor && i % (subdivisions ~/ 2) == 0;
      final h = isMajor
          ? size.height * 0.78
          : (isMid ? size.height * 0.52 : size.height * 0.32);
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        xFrac <= selectT + 0.001 ? tickPaint : dimPaint,
      );
    }

    final thumbX = size.width * t.clamp(0.0, selectT);
    final cy = size.height / 2;
    canvas.drawCircle(
      Offset(thumbX, cy + 1),
      11,
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawCircle(Offset(thumbX, cy), 10, Paint()..color = AppColors.primary);
    canvas.drawCircle(
      Offset(thumbX, cy),
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CapCutSpeedRulerPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.markCount != markCount ||
      oldDelegate.selectT != selectT;
}

/// CapCut live FX overlay for video preview (screen-blend raster frames).
class _VideoLiveEffectOverlay extends StatefulWidget {
  const _VideoLiveEffectOverlay({
    required this.effect,
    required this.positionSec,
    required this.startSec,
    required this.endSec,
    this.onFramesReady,
  });

  final OverlayEffect effect;
  final double positionSec;
  final double startSec;
  final double endSec;
  final ValueChanged<String>? onFramesReady;

  @override
  State<_VideoLiveEffectOverlay> createState() =>
      _VideoLiveEffectOverlayState();
}

class _VideoLiveEffectOverlayState extends State<_VideoLiveEffectOverlay> {
  final List<ui.Image> _frames = [];
  int _loadGen = 0;
  int _frameIndex = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFrames(widget.effect));
  }

  @override
  void didUpdateWidget(covariant _VideoLiveEffectOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effect.id != widget.effect.id) {
      unawaited(_loadFrames(widget.effect));
    } else {
      _syncFrame();
    }
  }

  @override
  void dispose() {
    _disposeFrames();
    super.dispose();
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
      final (w, h) = EffectOverlayService.cappedSize(540, 960, maxSide: 360);
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
      setState(() => _ready = true);
      _syncFrame();
      widget.onFramesReady?.call(effect.id);
    } catch (_) {
      if (mounted && gen == _loadGen) setState(() => _ready = false);
    }
  }

  void _syncFrame() {
    if (!_ready || _frames.isEmpty || !mounted) return;
    final t = widget.positionSec;
    final visible = t >= widget.startSec - 0.001 && t <= widget.endSec + 0.001;
    if (!visible) {
      if (_frameIndex != -1) setState(() => _frameIndex = -1);
      return;
    }
    final local = (t - widget.startSec).clamp(0.0, 36000.0);
    final idx =
        (local * EffectOverlayService.previewFps).floor() % _frames.length;
    if (idx != _frameIndex) setState(() => _frameIndex = idx);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _frames.isEmpty || _frameIndex < 0) {
      return const SizedBox.shrink();
    }
    final image = _frames[_frameIndex.clamp(0, _frames.length - 1)];
    return IgnorePointer(
      child: CustomPaint(
        painter: _VideoScreenEffectPainter(image: image),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _VideoScreenEffectPainter extends CustomPainter {
  _VideoScreenEffectPainter({required this.image});

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.cover,
      blendMode: BlendMode.screen,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoScreenEffectPainter oldDelegate) =>
      oldDelegate.image != image;
}
