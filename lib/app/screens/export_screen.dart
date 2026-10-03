import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../services/export_service.dart';
import '../services/slideshow_project.dart';
import '../widgets/app_chrome.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _started = false;
  bool _exporting = false;
  double _progress = 0;
  String? _status;
  File? _output;
  VideoPlayerController? _controller;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startExport() async {
    final project = context.read<SlideshowProject>();
    setState(() {
      _started = true;
      _exporting = true;
      _progress = 0;
      _status = 'Rendering frames…';
      _error = null;
      _output = null;
    });

    try {
      // Always regenerate so quality/ratio/overlays are baked in.
      await project.generatePreviewFrames(
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _progress = p * 0.7;
            _status = 'Rendering frames… ${(_progress * 100).toInt()}%';
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _progress = 0.75;
        _status = 'Encoding video…';
      });

      final file = await ExportService.export(project);
      if (!mounted) return;

      await _controller?.dispose();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      setState(() {
        _controller = controller;
        _output = file;
        _exporting = false;
        _progress = 1;
        _status = 'Saved to Studio';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = e.toString();
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<SlideshowProject>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Export'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (!_started) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Resolution',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final q in ExportQuality.values) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => project.setExportQuality(q),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: project.exportQuality == q
                                ? AppColors.primarySoft
                                : AppColors.surfaceAlt,
                            border: Border.all(
                              color: project.exportQuality == q
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: project.exportQuality == q ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            q.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: project.exportQuality == q
                                  ? AppColors.primaryDark
                                  : AppColors.textDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (q != ExportQuality.p1080) const SizedBox(width: 10),
                  ],
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _startExport,
                  child: const Text('Start Export'),
                ),
              ),
            ] else ...[
              Expanded(
                child: Center(
                  child: _controller != null && _controller!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_exporting) ...[
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: CircularProgressIndicator(
                                  value: _progress > 0 ? _progress : null,
                                  color: AppColors.primary,
                                  strokeWidth: 6,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _status ?? 'Working…',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else if (_error != null) ...[
                              const Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppColors.danger,
                              ),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _startExport,
                                child: const Text('Retry'),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              if (_output != null) ...[
                Text(
                  _output!.path.split('/').last,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          SharePlus.instance.share(
                            ShareParams(files: [XFile(_output!.path)]),
                          );
                        },
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TealPillButton(
                        label: 'Studio',
                        onPressed: () => context.go('/creations'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
