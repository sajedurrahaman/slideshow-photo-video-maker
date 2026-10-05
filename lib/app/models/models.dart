import '../core/constants/app_constants.dart';

enum SlideTransitionType {
  none,
  crossfade,
  erase,
  eraseSlide,
  pixelEffect,
  bar,
  crossMerge,
  rectZoomIn,
  rectZoomOut,
  crossShutter,
  rowSplit,
  colSplit,
  flipPageRight,
  dipToColor,
  filterColor,
  curvedDown,
  tiltDrift,
  jalousie,
  zoomIn,
  zoomOut,
  /// Native Whole3D_TB — vertical 3D fold (new from top).
  whole3dTb,
  /// Native Whole3D_BT — opposite of TB (new from bottom).
  whole3dBt,
}

class SlideTheme {
  final String id;
  final String name;
  final SlideTransitionType primaryEffect;
  final List<SlideTransitionType> effects;
  final String? musicAsset;

  const SlideTheme({
    required this.id,
    required this.name,
    required this.primaryEffect,
    required this.effects,
    this.musicAsset,
  });
}

/// Editor "Slide" picker items (Figma-style transition tiles).
class SlideTransitionOption {
  final String id;
  final String? assetPath;
  final SlideTransitionType type;

  /// Diamond/pixel dissolve grid (used when [type] is pixelEffect).
  final int gridCols;
  final int gridRows;
  final bool reverseDiagonal;
  /// If true, diamonds reveal top → bottom (ignores diagonal flags).
  final bool topToBottom;

  const SlideTransitionOption({
    required this.id,
    required this.type,
    this.assetPath,
    this.gridCols = 12,
    this.gridRows = 20,
    this.reverseDiagonal = false,
    this.topToBottom = false,
  });

  bool get isNone => type == SlideTransitionType.none;

  /// Serial: None → slide_01 … slide_08 (do not reorder).
  static const List<SlideTransitionOption> all = [
    SlideTransitionOption(id: 'none', type: SlideTransitionType.none),
    // Blue mark: same dissolve green used to show (dense reverse diagonal).
    SlideTransitionOption(
      id: 'slide_01',
      assetPath: 'assets/images/editor/transitions/slide_01.png',
      type: SlideTransitionType.pixelEffect,
      gridCols: 16,
      gridRows: 26,
      reverseDiagonal: true,
    ),
    // Green mark: same diamond style, but top → bottom.
    SlideTransitionOption(
      id: 'slide_02',
      assetPath: 'assets/images/editor/transitions/slide_02.png',
      type: SlideTransitionType.pixelEffect,
      gridCols: 16,
      gridRows: 26,
      topToBottom: true,
    ),
    SlideTransitionOption(
      id: 'slide_03',
      assetPath: 'assets/images/editor/transitions/slide_03.png',
      type: SlideTransitionType.erase,
    ),
    SlideTransitionOption(
      id: 'slide_04',
      assetPath: 'assets/images/editor/transitions/slide_04.png',
      type: SlideTransitionType.whole3dTb,
    ),
    SlideTransitionOption(
      id: 'slide_05',
      assetPath: 'assets/images/editor/transitions/slide_05.png',
      type: SlideTransitionType.whole3dBt,
    ),
    SlideTransitionOption(
      id: 'slide_06',
      assetPath: 'assets/images/editor/transitions/slide_06.png',
      type: SlideTransitionType.rectZoomIn,
    ),
    SlideTransitionOption(
      id: 'slide_07',
      assetPath: 'assets/images/editor/transitions/slide_07.png',
      type: SlideTransitionType.crossMerge,
    ),
    SlideTransitionOption(
      id: 'slide_08',
      assetPath: 'assets/images/editor/transitions/slide_08.png',
      type: SlideTransitionType.jalousie,
    ),
  ];
}

class AppThemes {
  static const List<SlideTheme> all = [
    SlideTheme(
      id: 'mixer',
      name: 'Mixer',
      primaryEffect: SlideTransitionType.pixelEffect,
      musicAsset: 'assets/music/songs_1.mp3',
      effects: [
        SlideTransitionType.pixelEffect,
        SlideTransitionType.eraseSlide,
        SlideTransitionType.erase,
        SlideTransitionType.crossfade,
        SlideTransitionType.dipToColor,
        SlideTransitionType.filterColor,
        SlideTransitionType.rectZoomOut,
        SlideTransitionType.rowSplit,
        SlideTransitionType.colSplit,
        SlideTransitionType.crossMerge,
        SlideTransitionType.crossShutter,
        SlideTransitionType.flipPageRight,
        SlideTransitionType.curvedDown,
        SlideTransitionType.tiltDrift,
      ],
    ),
    SlideTheme(
      id: 'crossfade',
      name: 'Crossfade',
      primaryEffect: SlideTransitionType.crossfade,
      musicAsset: 'assets/music/songs_6.mp3',
      effects: [
        SlideTransitionType.crossfade,
        SlideTransitionType.filterColor,
        SlideTransitionType.dipToColor,
      ],
    ),
    SlideTheme(
      id: 'erase_slide',
      name: 'Erase Slide',
      primaryEffect: SlideTransitionType.eraseSlide,
      musicAsset: 'assets/music/songs_2.mp3',
      effects: [SlideTransitionType.eraseSlide, SlideTransitionType.erase],
    ),
    SlideTheme(
      id: 'pixel',
      name: 'Pixel',
      primaryEffect: SlideTransitionType.pixelEffect,
      musicAsset: 'assets/music/songs_3.mp3',
      effects: [SlideTransitionType.pixelEffect, SlideTransitionType.bar],
    ),
    SlideTheme(
      id: 'cross_shutter',
      name: 'Cross Shutter',
      primaryEffect: SlideTransitionType.crossShutter,
      musicAsset: 'assets/music/songs_4.mp3',
      effects: [SlideTransitionType.crossShutter, SlideTransitionType.jalousie],
    ),
    SlideTheme(
      id: 'zoom_in',
      name: 'Zoom In',
      primaryEffect: SlideTransitionType.zoomIn,
      musicAsset: 'assets/music/songs_5.mp3',
      effects: [SlideTransitionType.zoomIn, SlideTransitionType.rectZoomIn],
    ),
    SlideTheme(
      id: 'zoom_out',
      name: 'Zoom Out',
      primaryEffect: SlideTransitionType.zoomOut,
      musicAsset: 'assets/music/songs_1.mp3',
      effects: [SlideTransitionType.zoomOut, SlideTransitionType.rectZoomOut],
    ),
    SlideTheme(
      id: 'split',
      name: 'Split',
      primaryEffect: SlideTransitionType.rowSplit,
      musicAsset: 'assets/music/songs_2.mp3',
      effects: [
        SlideTransitionType.rowSplit,
        SlideTransitionType.colSplit,
        SlideTransitionType.crossMerge,
      ],
    ),
    SlideTheme(
      id: 'flip',
      name: 'Flip Page',
      primaryEffect: SlideTransitionType.flipPageRight,
      musicAsset: 'assets/music/songs_6.mp3',
      effects: [
        SlideTransitionType.flipPageRight,
        SlideTransitionType.tiltDrift,
      ],
    ),
    SlideTheme(
      id: 'bar',
      name: 'Bar',
      primaryEffect: SlideTransitionType.bar,
      musicAsset: 'assets/music/songs_3.mp3',
      effects: [SlideTransitionType.bar, SlideTransitionType.jalousie],
    ),
  ];
}

class FrameAsset {
  final String id;
  final String assetPath;
  const FrameAsset(this.id, this.assetPath);

  static List<FrameAsset> get all => List.generate(30, (i) {
    final n = (i + 1).toString().padLeft(2, '0');
    return FrameAsset('frame_$n', 'assets/frames/frame_$n.webp');
  });
}

class MusicTrack {
  final String path;
  final String title;
  final Duration? duration;
  final bool isAsset;
  final int volume; // 0-100

  const MusicTrack({
    required this.path,
    required this.title,
    this.duration,
    this.isAsset = false,
    this.volume = 100,
  });

  MusicTrack copyWith({int? volume, Duration? duration}) {
    return MusicTrack(
      path: path,
      title: title,
      duration: duration ?? this.duration,
      isAsset: isAsset,
      volume: volume ?? this.volume,
    );
  }
}

class SlideshowPhoto {
  final String id;
  final String path;
  final PhotoFilterPreset filter;

  SlideshowPhoto({
    required this.id,
    required this.path,
    this.filter = PhotoFilterPreset.original,
  });

  SlideshowPhoto copyWith({PhotoFilterPreset? filter}) {
    return SlideshowPhoto(id: id, path: path, filter: filter ?? this.filter);
  }
}

class TitleCard {
  final String title;
  final String subtitle;
  final int backgroundArgb;
  final double durationSec;

  const TitleCard({
    this.title = 'My Slideshow',
    this.subtitle = '',
    this.backgroundArgb = 0xFF00BFA5,
    this.durationSec = 2.0,
  });

  TitleCard copyWith({
    String? title,
    String? subtitle,
    int? backgroundArgb,
    double? durationSec,
  }) {
    return TitleCard(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      backgroundArgb: backgroundArgb ?? this.backgroundArgb,
      durationSec: durationSec ?? this.durationSec,
    );
  }
}

enum OverlayKind { text, sticker }

class SlideOverlay {
  final String id;
  final OverlayKind kind;
  final double nx;
  final double ny;
  final double scale;
  final String? text;
  final int colorArgb;
  final String? stickerEmoji;

  const SlideOverlay({
    required this.id,
    required this.kind,
    this.nx = 0.5,
    this.ny = 0.5,
    this.scale = 1.0,
    this.text,
    this.colorArgb = 0xFFFFFFFF,
    this.stickerEmoji,
  });

  SlideOverlay copyWith({
    double? nx,
    double? ny,
    double? scale,
    String? text,
    int? colorArgb,
    String? stickerEmoji,
  }) {
    return SlideOverlay(
      id: id,
      kind: kind,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      scale: scale ?? this.scale,
      text: text ?? this.text,
      colorArgb: colorArgb ?? this.colorArgb,
      stickerEmoji: stickerEmoji ?? this.stickerEmoji,
    );
  }
}

class StickerItem {
  final String id;
  final String emoji;
  final String label;
  const StickerItem(this.id, this.emoji, this.label);

  static const all = <StickerItem>[
    StickerItem('heart', '❤️', 'Heart'),
    StickerItem('star', '⭐', 'Star'),
    StickerItem('fire', '🔥', 'Fire'),
    StickerItem('party', '🎉', 'Party'),
    StickerItem('camera', '📷', 'Camera'),
    StickerItem('flower', '🌸', 'Flower'),
    StickerItem('sun', '☀️', 'Sun'),
    StickerItem('moon', '🌙', 'Moon'),
    StickerItem('music', '🎵', 'Music'),
    StickerItem('clap', '👏', 'Clap'),
    StickerItem('love', '😍', 'Love'),
    StickerItem('cool', '😎', 'Cool'),
  ];
}

class BgOption {
  final String id;
  final String label;
  final int argb;
  const BgOption(this.id, this.label, this.argb);

  static const all = <BgOption>[
    BgOption('black', 'Black', 0xFF000000),
    BgOption('white', 'White', 0xFFFFFFFF),
    BgOption('teal', 'Teal', 0xFF00BFA5),
    BgOption('pink', 'Pink', 0xFFE91E63),
    BgOption('blue', 'Blue', 0xFF2196F3),
    BgOption('purple', 'Purple', 0xFF7C4DFF),
    BgOption('orange', 'Orange', 0xFFFF9800),
    BgOption('gray', 'Gray', 0xFF424242),
  ];
}
