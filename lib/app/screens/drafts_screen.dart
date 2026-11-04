import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/responsive/app_responsive.dart';
import '../core/theme/app_theme.dart';
import '../services/draft_service.dart';
import '../services/slideshow_project.dart';

/// Full list of saved editor drafts (project state — not exported MP4s).
class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<DraftMeta> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DraftService.changes.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    DraftService.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) unawaited(_load(showLoading: false));
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    final drafts = await DraftService.listDrafts();
    if (!mounted) return;
    setState(() {
      _drafts = drafts;
      _loading = false;
    });
  }

  Future<void> _open(DraftMeta draft) async {
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

  Future<void> _delete(DraftMeta draft) async {
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
    await _load(showLoading: false);
  }

  String _fmtDuration(double sec) {
    final total = sec.round().clamp(0, 99999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final rs = AppResponsive.of(context);
    final thumbSize = rs.r(64);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Drafts')),
      body: ResponsiveBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _drafts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: rs.r(56),
                          color: AppColors.textMuted,
                        ),
                        SizedBox(height: rs.h(12)),
                        Text(
                          'No drafts yet',
                          style: TextStyle(
                            fontSize: rs.sp(18),
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: rs.h(4)),
                        Text(
                          'Saved editor projects will appear here',
                          style: TextStyle(
                            fontSize: rs.sp(13),
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(showLoading: false),
                    child: ListView.separated(
                      itemCount: _drafts.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      itemBuilder: (context, index) {
                        final draft = _drafts[index];
                        final stamp = DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(draft.updatedAt);
                        final thumb = draft.thumbPath;
                        return ListTile(
                          contentPadding: EdgeInsets.fromLTRB(
                            rs.w(16),
                            rs.h(8),
                            rs.w(8),
                            rs.h(8),
                          ),
                          onTap: () => _open(draft),
                          leading: ClipRRect(
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
                                  : const Icon(
                                      Icons.photo_library_outlined,
                                      color: Colors.white70,
                                    ),
                            ),
                          ),
                          title: Text(
                            draft.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: rs.sp(14),
                              color: const Color(0xFF1A237E),
                            ),
                          ),
                          subtitle: Text(
                            'Last update $stamp\n'
                            '${draft.photoCount} photos · ${_fmtDuration(draft.durationSec)}',
                            style: TextStyle(
                              fontSize: rs.sp(11),
                              color: const Color(0xFF9E9E9E),
                              height: 1.35,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_horiz,
                              color: Color(0xFF757575),
                            ),
                            onSelected: (v) {
                              if (v == 'delete') _delete(draft);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
