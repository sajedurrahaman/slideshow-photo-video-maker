import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/app_constants.dart';
import '../services/export_service.dart';

/// Figma `home-Screen` — hero + Slideshow/Studio + Drafts + Rate/Share.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _heroSlides = [
    'assets/images/home/slider/slide_1.png',
    'assets/images/home/slider/slide_2.png',
    'assets/images/home/slider/slide_3.jpg',
    'assets/images/home/slider/slide_4.png',
  ];

  List<File> _drafts = [];
  bool _loading = true;
  late final PageController _heroPageController;
  int _heroIndex = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _heroPageController = PageController();
    _startHeroAutoPlay();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDrafts());
  }

  void _startHeroAutoPlay() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_heroPageController.hasClients) return;
      final next = (_heroIndex + 1) % _heroSlides.length;
      _heroPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _heroPageController.dispose();
    super.dispose();
  }

  int _imageCacheWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (width * dpr).round().clamp(360, 960);
  }

  Future<void> _loadDrafts() async {
    setState(() => _loading = true);
    final files = await ExportService.listCreations();
    if (!mounted) return;
    setState(() {
      _drafts = files;
      _loading = false;
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _rateUs() {
    return _openUrl(
      'https://play.google.com/store/apps/details?id=${AppConstants.packageId}',
    );
  }

  Future<void> _shareApp() {
    return SharePlus.instance.share(
      ShareParams(
        text:
            'Check out ${AppConstants.appName} — make photo slideshows easily!',
      ),
    );
  }

  Future<void> _playDraft(File file) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => _HomePlayerPage(file: file)));
  }

  Future<void> _deleteDraft(File file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text(p.basename(file.path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (await file.exists()) await file.delete();
    await _loadDrafts();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final visibleDrafts = _drafts.take(3).toList();
    final heroCacheW = _imageCacheWidth(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: RefreshIndicator(
          onRefresh: _loadDrafts,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 280 + topInset,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: PageView.builder(
                          controller: _heroPageController,
                          itemCount: _heroSlides.length,
                          onPageChanged: (i) => setState(() => _heroIndex = i),
                          itemBuilder: (context, index) {
                            return Image.asset(
                              _heroSlides[index],
                              fit: BoxFit.cover,
                              cacheWidth: heroCacheW,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (_, _, _) => Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1A1035),
                                      Color(0xFF4A148C),
                                      Color(0xFF00BCD4),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 88,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_heroSlides.length, (i) {
                            final active = i == _heroIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 16 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ),
                      // Soft fade into white content
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 72,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Slideshow + Studio (Figma image buttons)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 4,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _HomeHeroImageButton(
                                backgroundAsset:
                                    'assets/images/slideshowbutton.png',
                                iconAsset: 'assets/images/slideshow.png',
                                cacheWidth: heroCacheW ~/ 2,
                                onTap: () => context.push('/gallery'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _HomeHeroImageButton(
                                backgroundAsset:
                                    'assets/images/studiobutton.png',
                                iconAsset: 'assets/images/studio.png',
                                iconWidth: 72,
                                iconTop: -28,
                                cacheWidth: heroCacheW ~/ 2,
                                onTap: () => context.push('/creations'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Drafts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => context.push('/creations'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1A237E),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View All >',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (visibleDrafts.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'No drafts yet. Create a slideshow to see it here.',
                      style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final file = visibleDrafts[index];
                    return _DraftTile(
                      file: file,
                      onTap: () => _playDraft(file),
                      onDelete: () => _deleteDraft(file),
                      onShare: () {
                        SharePlus.instance.share(
                          ShareParams(files: [XFile(file.path)]),
                        );
                      },
                    );
                  }, childCount: visibleDrafts.length),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _OutlineActionButton(
                          label: 'Rate Us',
                          icon: Icons.star_rounded,
                          color: const Color(0xFFFF9800),
                          onTap: _rateUs,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OutlineActionButton(
                          label: 'Share Now',
                          icon: Icons.share_rounded,
                          color: const Color(0xFF4CAF50),
                          onTap: _shareApp,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    4,
                    24,
                    20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'By Continuing you agree to the ',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF616161),
                          height: 1.4,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openUrl(
                          'https://sites.google.com/view/graphicscycle/home',
                        ),
                        child: const Text(
                          'Terms and service',
                          style: TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Text(
                        ' & ',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF616161),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openUrl(
                          'https://sites.google.com/view/graphicscycle/home',
                        ),
                        child: const Text(
                          'privacy policy',
                          style: TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }
}

/// Figma home hero button: PNG background + decorative icon overlapping top.
class _HomeHeroImageButton extends StatelessWidget {
  const _HomeHeroImageButton({
    required this.backgroundAsset,
    required this.iconAsset,
    required this.onTap,
    this.iconWidth = 64,
    this.iconTop = -24,
    this.cacheWidth,
  });

  final String backgroundAsset;
  final String iconAsset;
  final VoidCallback onTap;
  final double iconWidth;
  final double iconTop;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    backgroundAsset,
                    fit: BoxFit.fill,
                    cacheWidth: cacheWidth,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              Positioned(
                top: iconTop,
                right: -4,
                child: Image.asset(
                  iconAsset,
                  width: iconWidth,
                  fit: BoxFit.contain,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftTile extends StatefulWidget {
  const _DraftTile({
    required this.file,
    required this.onTap,
    required this.onDelete,
    required this.onShare,
  });

  final File file;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  @override
  State<_DraftTile> createState() => _DraftTileState();
}

class _DraftTileState extends State<_DraftTile> {
  late final Future<DateTime> _modifiedFuture = widget.file.lastModified();

  @override
  Widget build(BuildContext context) {
    final name = p.basenameWithoutExtension(widget.file.path);
    final id = name.replaceAll(RegExp(r'[^0-9]'), '');
    final displayId = id.isNotEmpty ? id : name;

    return InkWell(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 64,
                height: 64,
                color: const Color(0xFF263238),
                child: const Center(
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFF00BCD4),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FutureBuilder<DateTime>(
                    future: _modifiedFuture,
                    builder: (context, snap) {
                      final stamp = snap.hasData
                          ? DateFormat('yyyy-MM-dd HH:mm').format(snap.data!)
                          : '…';
                      return Text(
                        'Last update $stamp',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      );
                    },
                  ),
                  const Text(
                    '00:14',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Color(0xFF757575)),
              onSelected: (v) {
                if (v == 'share') widget.onShare();
                if (v == 'delete') widget.onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 20),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _HomePlayerPage extends StatefulWidget {
  const _HomePlayerPage({required this.file});
  final File file;

  @override
  State<_HomePlayerPage> createState() => _HomePlayerPageState();
}

class _HomePlayerPageState extends State<_HomePlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller
          ..setLooping(true)
          ..play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(p.basename(widget.file.path)),
      ),
      body: Center(
        child: !_ready
            ? const CircularProgressIndicator(color: Colors.white)
            : AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
      ),
    );
  }
}
