import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Shared host for CapCut TextToolsSheet + LiveTextOverlaysLayer.
/// Implemented by [SlideshowProject] and video editor's [TextOverlayStore].
abstract class TextOverlayHost implements Listenable {
  List<SlideOverlay> get overlays;
  void addOverlay(SlideOverlay overlay);
  void updateOverlay(SlideOverlay overlay);
  void removeOverlay(String id);
}

/// Standalone overlay store for the video editor.
class TextOverlayStore extends ChangeNotifier implements TextOverlayHost {
  final List<SlideOverlay> _overlays = <SlideOverlay>[];

  @override
  List<SlideOverlay> get overlays => _overlays;

  @override
  void addOverlay(SlideOverlay overlay) {
    _overlays.add(overlay);
    notifyListeners();
  }

  @override
  void updateOverlay(SlideOverlay overlay) {
    final i = _overlays.indexWhere((e) => e.id == overlay.id);
    if (i < 0) return;
    _overlays[i] = overlay;
    notifyListeners();
  }

  @override
  void removeOverlay(String id) {
    _overlays.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void clear() {
    if (_overlays.isEmpty) return;
    _overlays.clear();
    notifyListeners();
  }
}
