import 'dart:async';
import 'dart:io';

import 'package:clip_craft_slideshow/app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/bottom_banner_ad.dart';
import '../core/constants/app_constants.dart';
import '../core/responsive/app_responsive.dart';
import '../services/draft_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/rate_app_service.dart';
import '../services/slideshow_project.dart';

/// Home — header + Slideshow/Video + Quick Tools + Drafts + Rate/Share.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DraftMeta> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DraftService.changes.addListener(_onDraftsChanged);
    unawaited(_loadDrafts());
  }

  void _onDraftsChanged() {
    if (!mounted) return;
    // Quiet refresh — no full-screen loading flicker when returning from editor.
    unawaited(_loadDrafts(showLoading: false));
  }

  @override
  void dispose() {
    DraftService.changes.removeListener(_onDraftsChanged);
    super.dispose();
  }

  @override
  void activate() {
    super.activate();
    // Home may stay under the nav stack; refresh when it becomes visible again.
    unawaited(_loadDrafts(showLoading: false));
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

  Future<void> _rateUs() => RateAppService.rateUs();

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open draft: $e')));
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

  void _quickToolTap(String label) {
    if (label == 'Music') {
      context.push('/music');
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label — coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final visibleDrafts = _drafts.take(3).toList();

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        body: ResponsiveBody(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadDrafts,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: ColoredBox(
                          color: const Color(0xFFF7F8FC),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              rs.w(16),
                              topInset + rs.h(12),
                              rs.w(16),
                              rs.h(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Photo & Video Editor',
                                            style: TextStyle(
                                              fontSize: rs.sp(22),
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF1A237E),
                                              height: 1.15,
                                            ),
                                          ),
                                          SizedBox(height: rs.h(4)),
                                          Text(
                                            'make your photo alive',
                                            style: TextStyle(
                                              fontSize: rs.sp(13),
                                              fontWeight: FontWeight.w500,
                                              color: const Color(0xFF9E9E9E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Material has no gradient — use decoration + transparent Material.
                                    Material(
                                      color: Colors.transparent,
                                      shape: const CircleBorder(),
                                      elevation: 2,
                                      shadowColor: const Color(0x6637B5F2),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => context.push('/settings'),
                                        child: Ink(
                                          width: rs.r(40),
                                          height: rs.r(40),
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF21EDD6),
                                                Color(0xFF37B5F2),
                                              ],
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.settings_outlined,
                                            color: Colors.white,
                                            size: rs.r(26),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: rs.h(24)),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _HomeCtaButton(
                                        backgroundAsset:
                                            'assets/images/slideshowbutton.svg',
                                        iconAsset:
                                            'assets/images/slideshow.png',
                                        onTap: () => context.push('/gallery'),
                                      ),
                                    ),
                                    SizedBox(width: rs.w(12)),
                                    Expanded(
                                      child: _HomeCtaButton(
                                        backgroundAsset:
                                            'assets/images/videobutton.svg',
                                        iconAsset: 'assets/images/studio.png',
                                        iconWidth: rs.w(78),
                                        iconTop: -rs.h(30),
                                        onTap: () => context.push('/creations'),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: rs.h(22)),
                                Row(
                                  children: [
                                    Container(
                                      width: rs.w(4),
                                      height: rs.h(18),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1A237E),
                                        borderRadius: BorderRadius.circular(
                                          rs.r(2),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: rs.w(8)),
                                    Text(
                                      'Quick Tools',
                                      style: TextStyle(
                                        fontSize: rs.sp(18),
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1A237E),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: rs.h(14)),
                                _QuickToolsGrid(onTap: _quickToolTap),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            rs.w(16),
                            rs.h(8),
                            rs.w(16),
                            0,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: rs.w(4),
                                height: rs.h(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A237E),
                                  borderRadius: BorderRadius.circular(rs.r(2)),
                                ),
                              ),
                              SizedBox(width: rs.w(8)),
                              Text(
                                'Drafts',
                                style: TextStyle(
                                  fontSize: rs.sp(18),
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A237E),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => context.push('/drafts'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF1A237E),
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size(0, rs.h(32)),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'View All >',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: rs.sp(13),
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
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              44.h(context),
                              16,
                              0,
                            ),
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
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
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
              // Rate / Share / Terms — banner sits below this block.
              ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
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
                              color: const Color(0xFF13D23D),
                              onTap: _shareApp,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
                                'https://sites.google.com/view/slideshow-photovideomaker-term',
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
                                'https://sites.google.com/view/slideshow-photovideomaker',
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
                    ],
                  ),
                ),
              ),
              // Hide entirely when load fails (no empty slot on Home).
              const BottomBannerAd(reserveSpace: false),
              SizedBox(height: bottomInset),
            ],
          ),
        ),
      ),
    );
  }
}

/// PNG background (label baked in) + decorative 3D icon overlapping top-right.
class _HomeCtaButton extends StatelessWidget {
  const _HomeCtaButton({
    required this.backgroundAsset,
    required this.iconAsset,
    required this.onTap,
    this.iconWidth = 64,
    this.iconTop = -24,
  });

  final String backgroundAsset;
  final String iconAsset;
  final VoidCallback onTap;
  final double iconWidth;
  final double iconTop;

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rs.r(14)),
        child: SizedBox(
          height: rs.h(70),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(rs.r(16)),
                  child: SvgPicture.asset(backgroundAsset, fit: BoxFit.fill),
                ),
              ),
              Positioned(
                top: iconTop,
                right: -rs.w(2),
                child: Image.asset(
                  iconAsset,
                  width: iconWidth,
                  fit: BoxFit.contain,
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

class _QuickToolsGrid extends StatelessWidget {
  const _QuickToolsGrid({required this.onTap});

  final ValueChanged<String> onTap;

  static const _tools = <({String label, String image})>[
    (label: 'Trim', image: "assets/images/quickTools/trim.svg"),
    (label: 'Compress', image: "assets/images/quickTools/compress.svg"),
    (label: 'Video to MP3', image: "assets/images/quickTools/mp3.svg"),
    (label: 'Reverse', image: "assets/images/quickTools/reverse.svg"),
    (label: 'Music', image: "assets/images/quickTools/music.svg"),
    (label: 'Merge', image: "assets/images/quickTools/merge.svg"),
  ];

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    return GridView.builder(
      padding: EdgeInsets.all(0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tools.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: rs.h(14),
        crossAxisSpacing: rs.w(12),
        // Soft rounded cards matching home mockup.
        mainAxisExtent: rs.h(94),
      ),
      itemBuilder: (context, i) {
        final tool = _tools[i];
        return _QuickToolTile(
          label: tool.label,
          image: tool.image,
          onTap: () => onTap(tool.label),
        );
      },
    );
  }
}

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    required this.label,
    required this.image,
    required this.onTap,
  });

  final String label;
  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final radius = rs.r(24);
    final borderW = rs.r(1.6);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // Gradient border: stronger blue on top → soft/white at bottom.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF32B9FD), Color(0xFFDCF3FF), Color(0xFFF1F0F0)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF64B5F6).withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Container(
            margin: EdgeInsets.all(borderW),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius - borderW),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: rs.w(8),
              vertical: rs.h(4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  image,
                  fit: BoxFit.contain,
                  width: rs.r(52),
                  height: rs.r(48),
                ),
                SizedBox(height: rs.h(1)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: rs.sp(11),
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: const Color(0xFF1A237E),
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
    final rs = AppResponsive.of(context);
    final stamp = DateFormat('yyyy-MM-dd HH:mm').format(draft.updatedAt);
    final thumb = draft.thumbPath;
    final thumbSize = rs.r(64);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(rs.w(16), rs.h(10), rs.w(8), rs.h(10)),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(rs.r(8)),
              child: Container(
                width: thumbSize,
                height: thumbSize,
                color: const Color(0xFF263238),
                child: thumb != null && File(thumb).existsSync()
                    ? Image.file(
                        File(thumb),
                        fit: BoxFit.cover,
                        width: thumbSize,
                        height: thumbSize,
                      )
                    : const Center(
                        child: Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
            SizedBox(width: rs.w(12)),
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
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9E9E9E),
                    ),
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
