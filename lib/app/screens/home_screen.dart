import 'dart:async';
import 'dart:io';

import 'package:clip_craft_slideshow/app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../services/draft_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/slideshow_project.dart';

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

  List<DraftMeta> _drafts = [];
  bool _loading = true;
  late final PageController _heroPageController;
  int _heroIndex = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _heroPageController = PageController();
    _startHeroAutoPlay();
    DraftService.changes.addListener(_onDraftsChanged);
    unawaited(_loadDrafts());
  }

  void _onDraftsChanged() {
    if (!mounted) return;
    // Quiet refresh — no full-screen loading flicker when returning from editor.
    unawaited(_loadDrafts(showLoading: false));
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
    DraftService.changes.removeListener(_onDraftsChanged);
    _heroTimer?.cancel();
    _heroPageController.dispose();
    super.dispose();
  }

  @override
  void activate() {
    super.activate();
    // Home may stay under the nav stack; refresh when it becomes visible again.
    unawaited(_loadDrafts(showLoading: false));
  }

  int _imageCacheWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (width * dpr).round().clamp(360, 960);
  }

  Future<void> _loadDrafts({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    final drafts = await DraftService.listDrafts();
    if (!mounted) return;
    setState(() {
      _drafts = drafts;
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

  /// Long-press Rate Us → copy FCM token for Firebase Console push test.
  Future<void> _copyFcmToken() async {
    final token =
        FirebaseBootstrap.fcmToken ?? await FirebaseBootstrap.refreshFcmToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FCM token not ready yet. Try again.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FCM token copied (${token.length} chars)'),
        duration: const Duration(seconds: 3),
      ),
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

  Future<void> _openDraft(DraftMeta draft) async {
    final project = context.read<SlideshowProject>();
    try {
      await DraftService.loadDraft(draft.id, project);
      if (!mounted) return;
      context.push('/editor');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open draft: $e')),
      );
    }
  }

  Future<void> _deleteDraft(DraftMeta draft) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text(draft.displayTitle),
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
    await DraftService.deleteDraft(draft.id);
    await _loadDrafts();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final visibleDrafts = _drafts.take(3).toList();
    final heroCacheW = _imageCacheWidth(context);

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadDrafts,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 390 + topInset,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: PageView.builder(
                                controller: _heroPageController,
                                itemCount: _heroSlides.length,
                                onPageChanged: (i) =>
                                    setState(() => _heroIndex = i),
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
                                children: List.generate(_heroSlides.length, (
                                  i,
                                ) {
                                  final active = i == _heroIndex;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    width: active ? 16 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? Colors.white
                                          : Colors.white.withValues(
                                              alpha: 0.45,
                                            ),
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
                              onPressed: () => context.push('/drafts'),
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
                          padding: EdgeInsets.fromLTRB(16, 44, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'No drafts yet',
                                style: TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Your saved projects will appear here',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final draft = visibleDrafts[index];
                          return _DraftTile(
                            draft: draft,
                            onTap: () => _openDraft(draft),
                            onDelete: () => _deleteDraft(draft),
                          );
                        }, childCount: visibleDrafts.length),
                      ),
                  ],
                ),
              ),
            ),
            // Always pinned to device bottom (above system nav inset).
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 2 + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _OutlineActionButton(
                            label: 'Rate Us',
                            icon: Icons.star_rounded,
                            color: const Color(0xFFFF9800),
                            onTap: _rateUs,
                            onLongPress: _copyFcmToken,
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
                    const SizedBox(height: 6),
                    Wrap(
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
                  ],
                ),
              ),
            ),
          ],
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

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final DraftMeta draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String _fmtDuration(double sec) {
    final total = sec.round().clamp(0, 99999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final stamp = DateFormat('yyyy-MM-dd HH:mm').format(draft.updatedAt);
    final thumb = draft.thumbPath;

    return InkWell(
      onTap: onTap,
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
                child: thumb != null && File(thumb).existsSync()
                    ? Image.file(
                        File(thumb),
                        fit: BoxFit.cover,
                        width: 64,
                        height: 64,
                      )
                    : const Center(
                        child: Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white70,
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
                    draft.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Last update $stamp',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  Text(
                    '${draft.photoCount} photos · ${_fmtDuration(draft.durationSec)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Color(0xFF757575)),
              onSelected: (v) {
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
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
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      onLongPress: onLongPress,
      icon: Icon(icon, color: color, size: 20),
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

