import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
      // Black cover outside + transparent hole inside + fire ring (portal reveal).
      portalReveal: true,
      durationSec: 2.3,
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

  /// Opening reveal animation id per clip (null = none). CapCut “In”.
  final List<String?> _clipRevealIds = [];

  /// User duration for In-anim (CapCut slider). Null = asset default.
  final List<double?> _clipRevealDurSec = [];

  /// Ending reveal animation id per clip (null = none). CapCut “Out”.
  final List<String?> _clipOutRevealIds = [];

  /// User duration for Out-anim. Null = asset default.
  final List<double?> _clipOutRevealDurSec = [];
  double? _revealDurDrag;
  double _clipSpeed = 1.0;
  bool _animSheetOpen = false;
  _VideoAnimPhase _animPhase = _VideoAnimPhase.inAnimation;

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
  }

  double _volumeFor(int index) {
    _ensureTrimSlots();
    if (index < 0 || index >= _clipVolumes.length) return 1.0;
    return _clipVolumes[index].clamp(0.0, 1.0);
  }

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
  String? _musicTitle;
  String? _textOverlay;
  String? _stickerLabel;
  String? _effectName; // null / 'None' = no effect lane
  Color _bgColor = Colors.black;
  late final TextEditingController _textFieldController;
  bool _loadingClip = false;
  bool _preparingProxy = false;

  final _stripController = ScrollController();
  bool _syncingStrip = false;
  bool _userScrubbing = false;
  Timer? _scrubTimer;
  double _lastScrubSec = -1;
  DateTime? _lastUiTick;

  /// Max editable clip length (product limit). CapCut free is typically ~60 min;
  /// we keep a conservative 5 min for v1 preview/export.
  static const _maxClipSec = 5 * 60.0;

  /// Per-clip duration (seconds).
  final Map<String, double> _clipDurationSec = {};

  /// Original path → downscaled proxy used for on-device preview (CapCut-style).
  final Map<String, String> _previewProxyPath = {};

  /// Filmstrip frame image paths per clip (1 frame ≈ 1s visual slot).
  final Map<String, List<String>> _filmstripFrames = {};
  final Set<String> _filmstripLoading = {};

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
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
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

  /// CapCut-style filmstrip: 1 thumbnail per second of source video.
  Future<void> _ensureFilmstrip(String path) async {
    final already = _filmstripFrames[path];
    if (already != null && already.length > 1) return;
    if (_filmstripLoading.contains(path)) return;
    _filmstripLoading.add(path);
    try {
      final dur = _clipDurationSec[path] ?? 1.0;
      final count = math.min(120, math.max(1, dur.ceil()));
      final tmp = await getTemporaryDirectory();
      final safe = path.hashCode.toRadixString(16);
      final dir = Directory(p.join(tmp.path, 'vstrip2_$safe'));

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
          '-vf "fps=1,scale=120:-2" -q:v 6 -frames:v $count "$pattern"',
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
    }
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
      await next.setPlaybackSpeed(_clipSpeed);
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
    final span = _trimOut(index) - _trimIn(index);
    return span.clamp(0.5, full).toDouble();
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
    final local = (_position.inMilliseconds / 1000.0) - _trimIn(_activeIndex);
    return before + local.clamp(0.0, _visibleDuration(_activeIndex));
  }

  void _clearClipSelection() {
    unawaited(_pausePreview());
    setState(() {
      _selectedClipIndex = null;
      _animSheetOpen = false;
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

    // CapCut In-anim: end overlay when past user duration.
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
    if (v.isInitialized && v.isPlaying && posSec >= out - 0.04) {
      unawaited(_playNextOrStop());
      return;
    }
    // Native EOF only while we haven't already parked on the last frame.
    if (v.isInitialized &&
        !_stoppedAtClipEnd &&
        v.position >= v.duration &&
        v.duration > Duration.zero &&
        !v.isPlaying) {
      unawaited(_playNextOrStop());
    }
  }

  void _syncStripToPlayhead() {
    if (!_stripController.hasClients) return;
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
    if (_syncingStrip || !_stripController.hasClients) return;
    if (_playing) {
      // User dragged while playing → pause then scrub (slideshow behavior).
      unawaited(_controller?.pause());
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
    final sourceLocal = _trimIn(index) + remaining;
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
    }
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      await c.pause();
      // CapCut: keep In-anim visible at playhead while paused.
      _syncRevealOverlayFromMain();
    } else {
      _userScrubbing = false;
      _scrubTimer?.cancel();
      final inn = _trimIn(_activeIndex);
      final out = _trimOut(_activeIndex);
      final pos = c.value.position.inMilliseconds / 1000.0;
      // CapCut: restart from start if near begin or past / parked at clip end.
      final restartFromStart = _stoppedAtClipEnd ||
          pos < inn + 0.15 ||
          pos >= out - 0.05 ||
          pos < inn;
      _stoppedAtClipEnd = false;
      if (restartFromStart) {
        await c.seekTo(Duration(milliseconds: (inn * 1000).round()));
      }
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
      await c.play();
      _syncStripToPlayhead();
    }
  }

  Future<void> _playNextOrStop() async {
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
      _syncStripToPlayhead();
      return;
    }

    // Last clip finished: pause on last frame (Out final frame if set).
    // Do NOT seek back to trimIn — that wrongly shows the In effect.
    if (_stoppedAtClipEnd) return;
    _stoppedAtClipEnd = true;
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
        // v21: Valentine hearts-only, New Year no-year, Leaf Cover Out.
        final base = p.basenameWithoutExtension(anim.assetPath);
        final dir = Directory(
          p.join(tmp.path, 'vreveal_frames_${anim.id}_${base}_v21_alpha'),
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
    setState(() {
      _tool = _tool == t ? null : t;
      _animSheetOpen = false;
    });
  }

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
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: _bgColor,
              // CapCut-style: full preview is canvas; video keeps native
              // aspect (contain). In-anim / overlays clip to video rect only.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_ready || _controller == null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                          if (_preparingProxy) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Preparing preview…',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: rs.sp(13),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  final videoSize = _controller!.value.size;
                  final videoAr = (videoSize.width > 0 && videoSize.height > 0)
                      ? videoSize.width / videoSize.height
                      : (_aspectW / _aspectH);
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
                            if (_textOverlay != null &&
                                _textOverlay!.isNotEmpty)
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
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Fixed play / time / undo row (never jumps when Animation opens).
          _buildPlaybackBar(rs),
          // Green area: filmstrip+tools OR Animation bottom sheet.
          if (_animSheetOpen)
            _buildClipAnimationSheet(rs)
          else
            _buildTimelineFilmstripPanel(rs),
          if (_selectedClipIndex == null && _tool != null) _buildToolPanel(rs),
          // CapCut: hide clip tools while Animation sheet fills that space.
          if (_selectedClipIndex != null && !_animSheetOpen)
            _buildClipToolsNavbar(rs)
          else if (_selectedClipIndex == null)
            _buildBottomTools(rs),
        ],
      ),
    );
  }

  /// CapCut: pause preview when opening tools / Animation.
  Future<void> _pausePreview() async {
    final c = _controller;
    if (c == null || !_ready || !c.value.isPlaying) return;
    await c.pause();
    _syncRevealOverlayFromMain();
    if (mounted) setState(() {});
  }

  /// Fills the already-sized video frame (native aspect, CapCut contain).
  Widget _buildPlayer(ColorFilter? filter) {
    final player = VideoPlayer(_controller!);
    if (filter == null) return player;
    return ColorFiltered(colorFilter: filter, child: player);
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
  Widget _buildTimelineFilmstripPanel(AppResponsive rs) {
    final bodyH = _timelinePanelH - _timelineHeaderH;
    return Container(
      height: bodyH,
      width: double.infinity,
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
              onPressed: _ready ? _togglePlay : null,
              icon: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: rs.r(32),
                color: _ready ? Colors.black87 : Colors.black26,
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

  bool get _hasMusicLane => _musicTitle != null;
  bool get _hasEffectLane => _effectName != null && _effectName != 'None';

  Widget _videoFilmstrip(AppResponsive rs, double playheadX) {
    final leftPad = playheadX.clamp(0.0, 800.0).toDouble();
    final pps = _pixelsPerSecond;
    final thumbH = _thumbH;
    final totalW = _totalDurationSec * pps;
    final hasMusic = _hasMusicLane;
    final hasEffect = _hasEffectLane;
    final lineH = rs.h(6);
    final rulerH = rs.h(18);
    final gapH = rs.h(4);
    final underH = (!hasMusic && !hasEffect)
        ? 0.0
        : (hasMusic && hasEffect ? lineH * 2 + rs.h(6) : lineH + rs.h(4));
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
                          _collapsedLane(
                            width: totalW,
                            height: lineH,
                            color: const Color(0xFF7C4DFF),
                            onTap: () => _selectTool(VideoEditorTool.effects),
                          ),
                        if (hasEffect && hasMusic) SizedBox(height: rs.h(2)),
                        if (hasMusic)
                          _collapsedLane(
                            width: totalW,
                            height: lineH,
                            color: AppColors.primary,
                            onTap: () => _selectTool(VideoEditorTool.music),
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
                final scroll = _stripController.hasClients
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
                      if (!_stripController.hasClients) return;
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
                      if (!_stripController.hasClients) return;
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

  Widget _clipThumbContent(int index, double width, double height, double pps) {
    final path = _clips[index];
    final frames = _filmstripFrames[path] ?? const <String>[];
    final slots = math.min(120, math.max(1, (width / pps).ceil()));
    final inn = _trimIn(index);
    final reveal = _revealFor(index);
    final outReveal = _outRevealFor(index);
    // CapCut: white In block at start, Out block at end.
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
                          final srcSec = (inn + s).floor();
                          final fi = srcSec.clamp(0, frames.length - 1);
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
    return GestureDetector(
      onTap: () => _selectClip(index),
      child: SizedBox(
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
        setState(() {
          _animSheetOpen = false;
          _revealDurDrag = null;
        });
        _stopRevealOverlay();
      },
      onConfirm: () {
        setState(() {
          _animSheetOpen = false;
          _revealDurDrag = null;
        });
        _stopRevealOverlay();
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
                    onTap: () => setState(() {
                      _animPhase = phase;
                      _revealDurDrag = null;
                    }),
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
                      setState(() {
                        if (isOut) {
                          _clipOutRevealIds[sel] = null;
                          _clipOutRevealDurSec[sel] = null;
                        } else {
                          _clipRevealIds[sel] = null;
                          _clipRevealDurSec[sel] = null;
                        }
                      });
                      _stopRevealOverlay();
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
                    Future<void> preview() async {
                      if (isOut) {
                        await _playRevealAtClipEnd(anim, playMain: true);
                      } else {
                        await _playRevealAtClipStart(anim, playMain: true);
                      }
                    }

                    if (_activeIndex != sel) {
                      unawaited(_loadClip(sel).then((_) => preview()));
                    } else {
                      unawaited(preview());
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

  Future<void> _handleClipTool(_ClipEditTool tool) async {
    final sel = _selectedClipIndex;
    if (sel == null || sel >= _clips.length) return;
    await _pausePreview();

    switch (tool) {
      case _ClipEditTool.volume:
        if (!mounted) return;
        await _openClipVolumeSheet(sel);
      case _ClipEditTool.animation:
        setState(() {
          _animSheetOpen = true;
          _animPhase = _VideoAnimPhase.inAnimation;
          _tool = null;
        });
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
          _ensureTrimSlots();
          _animSheetOpen = false;
          _selectedClipIndex = null;
        });
        await _loadClip(sel.clamp(0, _clips.length - 1));
      case _ClipEditTool.speed:
        if (!mounted) return;
        const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        final speedCtx = context;
        await showModalBottomSheet<void>(
          context: speedCtx,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Speed',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in speeds)
                        ChoiceChip(
                          label: Text('${s}x'),
                          selected: _clipSpeed == s,
                          onSelected: (_) {
                            setState(() => _clipSpeed = s);
                            unawaited(_controller?.setPlaybackSpeed(s));
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      case _ClipEditTool.crop:
        _clearClipSelection();
        _selectTool(VideoEditorTool.aspectRatio);
      case _ClipEditTool.replace:
        final result = await context.push<List<String>>(
          '/gallery?type=video&insert=1',
        );
        if (!mounted || result == null || result.isEmpty) return;
        setState(() {
          _clips[sel] = result.first;
          _ensureTrimSlots();
          _clipVolumes[sel] = 1.0;
          _clipRevealIds[sel] = null;
          _clipRevealDurSec[sel] = null;
          _clipOutRevealIds[sel] = null;
          _clipOutRevealDurSec[sel] = null;
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
            onChanged: (v) =>
                setState(() => _textOverlay = v.trim().isEmpty ? null : v),
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
                    setState(() => _musicTitle = 'Background music');
                  },
                ),
              ),
              if (_musicTitle != null) ...[
                SizedBox(width: rs.w(10)),
                IconButton(
                  onPressed: () => setState(() => _musicTitle = null),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
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
              final name = effects[i];
              final selected = (_effectName ?? 'None') == name;
              return GestureDetector(
                onTap: () =>
                    setState(() => _effectName = name == 'None' ? null : name),
                child: Column(
                  children: [
                    Container(
                      width: rs.w(64),
                      height: rs.w(64),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(rs.r(10)),
                        gradient: selected && name != 'None'
                            ? AppColors.primaryGradient
                            : null,
                        color: name == 'None' || !selected
                            ? AppColors.surfaceAlt
                            : null,
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: selected && name != 'None'
                            ? Colors.white
                            : AppColors.textMuted,
                      ),
                    ),
                    SizedBox(height: rs.h(4)),
                    Text(
                      name,
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
  double get _visible =>
      (_out - _inn).clamp(_minVisible, widget.sourceDuration);

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
    final clipW = _visible * widget.pixelsPerSecond;
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
                              '${_visible.toStringAsFixed(1)}s',
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
