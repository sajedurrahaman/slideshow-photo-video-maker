import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../models/models.dart';
import '../services/slideshow_project.dart';
import '../widgets/editTool_sheet.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    this.insertMode = false,
    this.insertIndex = 0,
  });

  /// When opened from editor timeline "+", insert at [insertIndex] and pop back.
  final bool insertMode;
  final int insertIndex;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final List<_PickedAsset> _assets = [];
  final Set<String> _selectedIds = {};
  final List<String> _orderedIds = [];
  /// Keeps selected entities when switching albums (grid only holds current folder).
  final Map<String, _PickedAsset> _selectedAssets = {};

  final List<_AlbumInfo> _albums = [];
  AssetPathEntity? _currentAlbum;
  String _albumTitle = 'Recent';
  bool _showAlbumPicker = false;

  bool _loading = true;
  bool _loadingAlbum = false;
  bool _continuing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _showAlbumPicker = false;
    });
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.isAuth && !perm.hasAccess) {
      setState(() {
        _loading = false;
        _error = 'Photo access is required. Enable it in Settings.';
      });
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
    );
    if (paths.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No photos found on this device.';
      });
      return;
    }

    // Prefer "All / Recent" first, then other albums by name.
    final sorted = [...paths]
      ..sort((a, b) {
        if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final albums = <_AlbumInfo>[];
    for (final path in sorted) {
      final count = await path.assetCountAsync;
      if (count <= 0) continue;
      albums.add(
        _AlbumInfo(
          path: path,
          name: path.isAll ? 'Recent' : path.name,
          count: count,
        ),
      );
    }

    if (albums.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No photos found on this device.';
      });
      return;
    }

    setState(() {
      _albums
        ..clear()
        ..addAll(albums);
      _loading = false;
    });

    await _openAlbum(albums.first);
  }

  Future<void> _openAlbum(_AlbumInfo album) async {
    setState(() {
      _loadingAlbum = true;
      _currentAlbum = album.path;
      _albumTitle = album.name;
      _showAlbumPicker = false;
    });

    final list = await album.path.getAssetListRange(
      start: 0,
      end: album.count.clamp(0, 500),
    );

    if (!mounted) return;
    setState(() {
      _assets
        ..clear()
        ..addAll(list.map((a) => _PickedAsset(id: a.id, entity: a)));
      _loadingAlbum = false;
    });
  }

  int get _maxSelectable {
    if (!widget.insertMode) return AppConstants.maxPhotos;
    final existing = context.read<SlideshowProject>().photos.length;
    return (AppConstants.maxPhotos - existing).clamp(0, AppConstants.maxPhotos);
  }

  int get _minSelectable =>
      widget.insertMode ? 1 : AppConstants.minPhotos;

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _orderedIds.remove(id);
        _selectedAssets.remove(id);
      } else {
        if (_selectedIds.length >= _maxSelectable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _maxSelectable <= 0
                    ? 'Timeline is full (max ${AppConstants.maxPhotos})'
                    : 'Max $_maxSelectable more photo(s)',
              ),
            ),
          );
          return;
        }
        _PickedAsset? item;
        for (final a in _assets) {
          if (a.id == id) {
            item = a;
            break;
          }
        }
        if (item == null) return;
        _selectedIds.add(id);
        _orderedIds.add(id);
        _selectedAssets[id] = item;
      }
    });
  }

  _PickedAsset? _assetForId(String id) {
    final cached = _selectedAssets[id];
    if (cached != null) return cached;
    for (final a in _assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _continue() async {
    if (_continuing) return;
    if (_orderedIds.length < _minSelectable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.insertMode
                ? 'Select at least 1 photo'
                : 'Select at least ${AppConstants.minPhotos} photos',
          ),
        ),
      );
      return;
    }

    setState(() => _continuing = true);
    try {
      final dir = await getTemporaryDirectory();
      final pickDir = Directory(
        p.join(dir.path, 'picked_${DateTime.now().millisecondsSinceEpoch}'),
      );
      await pickDir.create(recursive: true);

      final photos = <SlideshowPhoto>[];
      for (var i = 0; i < _orderedIds.length; i++) {
        if (!mounted) return;
        final id = _orderedIds[i];
        final item = _assetForId(id);
        if (item == null) continue;
        final dest = await _copyPickedAsset(item, pickDir, i);
        if (dest == null) continue;
        photos.add(SlideshowPhoto(id: id, path: dest.path));
      }
      if (photos.length < _minSelectable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load selected photos')),
        );
        return;
      }

      if (!mounted) return;
      final project = context.read<SlideshowProject>();
      if (widget.insertMode) {
        project.insertPhotosAt(widget.insertIndex, photos);
        if (!mounted) return;
        context.pop();
      } else {
        project.setPhotos(photos);
        if (!mounted) return;
        context.push('/editor');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open editor: $e')),
      );
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  /// Prefer already-loaded gallery thumbs. Never call originBytes / 1920px
  /// decode here — that hangs Glide on Xiaomi and leaves Next spinning.
  Future<File?> _copyPickedAsset(
    _PickedAsset item,
    Directory dir,
    int index,
  ) async {
    final safeId = item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final dest = File(p.join(dir.path, 'pick_${index}_$safeId.jpg'));

    Uint8List? bytes = item.thumbBytes;
    if (bytes == null || bytes.isEmpty) {
      try {
        bytes = await item.entity.thumbnailData.timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) {
      try {
        bytes = await item.entity
            .thumbnailDataWithSize(const ThumbnailSize(512, 512))
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (bytes == null || bytes.isEmpty) return null;

    await dest.writeAsBytes(bytes, flush: false);
    return dest;
  }

  @override
  Widget build(BuildContext context) {
    final count = _selectedIds.length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_showAlbumPicker) {
              setState(() => _showAlbumPicker = false);
              return;
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: GestureDetector(
          onTap: () {
            if (_loading || _albums.isEmpty) return;
            setState(() => _showAlbumPicker = !_showAlbumPicker);
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _albumTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedRotation(
                turns: _showAlbumPicker ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down, size: 20),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TealPillButton(
              label: count > 0 ? 'Next($count)' : 'Next',
              enabled: !_continuing,
              onPressed: _continue,
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => PhotoManager.openSetting(),
                                child: const Text('Open Settings'),
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _showAlbumPicker
                    ? _AlbumFolderList(
                        albums: _albums,
                        selectedPathId: _currentAlbum?.id,
                        onSelect: _openAlbum,
                      )
                    : _loadingAlbum
                    ? const Center(child: CircularProgressIndicator())
                    : GridView.builder(
                        padding: const EdgeInsets.all(2),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: _assets.length,
                        itemBuilder: (context, index) {
                          final item = _assets[index];
                          final selected = _selectedIds.contains(item.id);
                          return _ThumbTile(
                            entity: item.entity,
                            selected: selected,
                            onTap: () => _toggle(item.id),
                            onThumb: (data) => item.thumbBytes = data,
                          );
                        },
                      ),
              ),
              if (_orderedIds.isNotEmpty)
                Container(
                  height: 108,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 8, 14, 6),
                        child: Text(
                          'Multiple clips for better effect',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          itemCount: _orderedIds.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final id = _orderedIds[i];
                            final item = _assetForId(id);
                            if (item == null) return const SizedBox.shrink();
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _TrayThumb(entity: item.entity),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => _toggle(id),
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_continuing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumInfo {
  final AssetPathEntity path;
  final String name;
  final int count;

  const _AlbumInfo({
    required this.path,
    required this.name,
    required this.count,
  });
}

class _AlbumFolderList extends StatelessWidget {
  const _AlbumFolderList({
    required this.albums,
    required this.selectedPathId,
    required this.onSelect,
  });

  final List<_AlbumInfo> albums;
  final String? selectedPathId;
  final ValueChanged<_AlbumInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: albums.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final album = albums[index];
        final selected = album.path.id == selectedPathId;
        return InkWell(
          onTap: () => onSelect(album),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _AlbumCoverThumb(path: album.path),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${album.count}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlbumCoverThumb extends StatefulWidget {
  const _AlbumCoverThumb({required this.path});
  final AssetPathEntity path;

  @override
  State<_AlbumCoverThumb> createState() => _AlbumCoverThumbState();
}

class _AlbumCoverThumbState extends State<_AlbumCoverThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AlbumCoverThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path.id != widget.path.id) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final list = await widget.path.getAssetListRange(start: 0, end: 1);
      if (list.isEmpty || !mounted) return;
      final data = await list.first.thumbnailDataWithSize(
        const ThumbnailSize(160, 160),
      );
      if (!mounted || data == null) return;
      setState(() => _bytes = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : Container(color: AppColors.surfaceAlt),
      ),
    );
  }
}

class _PickedAsset {
  final String id;
  final AssetEntity entity;
  Uint8List? thumbBytes;
  _PickedAsset({required this.id, required this.entity});
}

class _ThumbTile extends StatefulWidget {
  const _ThumbTile({
    required this.entity,
    required this.selected,
    required this.onTap,
    required this.onThumb,
  });

  final AssetEntity entity;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Uint8List> onThumb;

  @override
  State<_ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<_ThumbTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ThumbTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.id != widget.entity.id) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final data = await widget.entity.thumbnailDataWithSize(
      const ThumbnailSize(300, 300),
    );
    if (!mounted || data == null) return;
    widget.onThumb(data);
    setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_bytes != null)
            Image.memory(_bytes!, fit: BoxFit.cover)
          else
            Container(color: AppColors.surfaceAlt),
          if (widget.selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.selected ? AppColors.accent : Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: widget.selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayThumb extends StatefulWidget {
  const _TrayThumb({required this.entity});
  final AssetEntity entity;

  @override
  State<_TrayThumb> createState() => _TrayThumbState();
}

class _TrayThumbState extends State<_TrayThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TrayThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.id != widget.entity.id) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final d = await widget.entity.thumbnailDataWithSize(
      const ThumbnailSize(120, 120),
    );
    if (!mounted) return;
    setState(() => _bytes = d);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: _bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.cover)
          : Container(color: AppColors.surfaceAlt),
    );
  }
}
