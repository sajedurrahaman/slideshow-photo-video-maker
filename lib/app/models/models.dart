import '../core/constants/app_constants.dart';

enum SlideTransitionType {
  none,
  crossfade,
  erase,
  eraseSlide,
  pixelEffect,

  /// Random mosaic / scattered square dissolve (slide_11 icon).
  pixelScatter,

  /// Ordered solid grid-cell dissolve (slide_12 icon).
  pixelGrid,
  bar,
  crossMerge,

  /// slide_15 ↑↓←→ — NEW cross opens from center outward (inverse of Cross_Merge).
  crossOpen,
  rectZoomIn,
  rectZoomOut,

  /// Concentric center Rect_Zoom_In (NEW border-in, shrinking OLD hole).
  rectZoomCenter,
  crossShutter,
  rowSplit,
  colSplit,

  /// slide_07: Row_Split + Col_Split together — 4 OLD panes, center cross NEW.
  rowColSplit,
  flipPageRight,
  dipToColor,
  filterColor,
  curvedDown,
  tiltDrift,
  jalousie,

  /// Native Jalousie_BT (ic_t_16) — 8 horizontal louvers, rotateX 0→180°.
  jalousieBt,

  /// Native Jalousie_LR (ic_t_18) — 8 vertical louvers, rotateY 0→180°.
  jalousieLr,

  /// Native RollInTurn_Down_Up (ic_t_19) — CoverFlow strip wave, rotateY.
  rollInTurnLr,
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

  /// rowColSplit hinge (0–1). Icon/green-circle ≈ bottom-right.
  final double pivotNx;
  final double pivotNy;

  const SlideTransitionOption({
    required this.id,
    required this.type,
    this.assetPath,
    this.gridCols = 12,
    this.gridRows = 20,
    this.reverseDiagonal = false,
    this.topToBottom = false,
    this.pivotNx = 0.5,
    this.pivotNy = 0.5,
  });

  bool get isNone => type == SlideTransitionType.none;

  /// Serial picker order: None → slide_01 … (do not reorder casually).
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
    // Nested square bottom-right → NEW expands from BR over OLD.
    SlideTransitionOption(
      id: 'slide_06',
      assetPath: 'assets/images/editor/transitions/slide_06.png',
      type: SlideTransitionType.rectZoomIn,
    ),
    // Concentric nested squares (center iris) — previous center Rect_Zoom_In.
    SlideTransitionOption(
      id: 'slide_09',
      assetPath: 'assets/images/editor/transitions/slide_09.png',
      type: SlideTransitionType.rectZoomCenter,
    ),
    // 4-pane grid icon — splits meet at bottom-right hinge (green circle).
    SlideTransitionOption(
      id: 'slide_07',
      assetPath: 'assets/images/editor/transitions/slide_07.png',
      type: SlideTransitionType.rowColSplit,
      pivotNx: 0.72,
      pivotNy: 0.68,
    ),
    // Vertical columns — wipe right → left.
    SlideTransitionOption(
      id: 'slide_08',
      assetPath: 'assets/images/editor/transitions/slide_08.png',
      type: SlideTransitionType.jalousie,
    ),
    // Horizontal bars / blinds — wipe top → bottom.
    SlideTransitionOption(
      id: 'slide_10',
      assetPath: 'assets/images/editor/transitions/slide_10.png',
      type: SlideTransitionType.bar,
    ),
    // Scattered square mosaic dissolve.
    SlideTransitionOption(
      id: 'slide_11',
      assetPath: 'assets/images/editor/transitions/slide_11.png',
      type: SlideTransitionType.pixelScatter,
      gridCols: 22,
      gridRows: 22,
    ),
    // Uniform grid cells — slice + BR→TL mosaic (native ClipCraft).
    SlideTransitionOption(
      id: 'slide_12',
      assetPath: 'assets/images/editor/transitions/slide_12.png',
      type: SlideTransitionType.pixelGrid,
      gridCols: 8,
      gridRows: 8,
    ),
    // Left/right doors open — sides push outward (native Col_Split).
    SlideTransitionOption(
      id: 'slide_13',
      assetPath: 'assets/images/editor/transitions/slide_13.png',
      type: SlideTransitionType.colSplit,
    ),
    // Top/bottom doors open — native Row_Split (ic_t_13).
    SlideTransitionOption(
      id: 'slide_14',
      assetPath: 'assets/images/editor/transitions/slide_14.png',
      type: SlideTransitionType.rowSplit,
    ),
    // 4-way ↑↓←→ — NEW opens from center outward (not meeting at center).
    SlideTransitionOption(
      id: 'slide_15',
      assetPath: 'assets/images/editor/transitions/slide_15.png',
      type: SlideTransitionType.crossOpen,
    ),
    // Horizontal louvers / Venetian blinds — native Jalousie_BT (ic_t_16).
    SlideTransitionOption(
      id: 'slide_16',
      assetPath: 'assets/images/editor/transitions/slide_16.png',
      type: SlideTransitionType.jalousieBt,
    ),
    // Vertical louvers — native Jalousie_LR (ic_t_18).
    SlideTransitionOption(
      id: 'slide_17',
      assetPath: 'assets/images/editor/transitions/slide_17.png',
      type: SlideTransitionType.jalousieLr,
    ),
    // CoverFlow / RollInTurn — strip-by-strip rotateY (ic_t_19).
    SlideTransitionOption(
      id: 'slide_18',
      assetPath: 'assets/images/editor/transitions/slide_18.png',
      type: SlideTransitionType.rollInTurnLr,
    ),
  ];
}

/// How an overlay clip is composited onto the slideshow.
enum OverlayBlendMode {
  /// Black-background FX (e.g. hearts) — screen blend.
  screen,

  /// Green-screen FX — chroma key then overlay.
  chromaGreen,
}

/// Bundled particle / FX overlay clips shown in the Effects picker.
class OverlayEffect {
  final String id;
  final String name;
  final String assetPath;
  final String thumbPath;
  final OverlayBlendMode blend;

  const OverlayEffect({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.thumbPath,
    this.blend = OverlayBlendMode.screen,
  });

  static const effect01 = OverlayEffect(
    id: 'effect_01',
    name: 'Hearts',
    assetPath: 'assets/effects/effect_01.mp4',
    thumbPath: 'assets/effects/effect_01_thumb.jpg',
  );

  static const effect02 = OverlayEffect(
    id: 'effect_02',
    name: 'Petals',
    assetPath: 'assets/effects/effect_02.mp4',
    thumbPath: 'assets/effects/effect_02_thumb.jpg',
  );

  static const effect03 = OverlayEffect(
    id: 'effect_03',
    name: 'Glow',
    assetPath: 'assets/effects/effect_03.mp4',
    thumbPath: 'assets/effects/effect_03_thumb.jpg',
  );

  static const effect04 = OverlayEffect(
    id: 'effect_04',
    name: 'Butterflies',
    assetPath: 'assets/effects/effect_04.mp4',
    thumbPath: 'assets/effects/effect_04_thumb.jpg',
  );

  static const effect05 = OverlayEffect(
    id: 'effect_05',
    name: 'Stars',
    assetPath: 'assets/effects/effect_05.mp4',
    thumbPath: 'assets/effects/effect_05_thumb.jpg',
  );

  static const effect06 = OverlayEffect(
    id: 'effect_06',
    name: 'Flowers',
    assetPath: 'assets/effects/effect_06.mp4',
    thumbPath: 'assets/effects/effect_06_thumb.jpg',
  );

  /// Only these 6 video effects appear in the Effects list.
  static const List<OverlayEffect> all = [
    effect01,
    effect02,
    effect03,
    effect04,
    effect05,
    effect06,
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

  static List<FrameAsset> get all => List.generate(12, (i) {
    final n = (i + 1).toString().padLeft(2, '0');
    return FrameAsset('frame_$n', 'assets/frames/frame_$n.png');
  });
}

class MusicTrack {
  final String path;
  final String title;
  final Duration? duration;
  final bool isAsset;
  final int volume; // 0-100

  /// Where this track starts / ends on the video timeline (seconds).
  /// [timelineEndSec] null = play through the end of the video.
  final double timelineStartSec;
  final double? timelineEndSec;

  /// Trim within the source audio file (seconds).
  /// Preview/export play from [clipStartSec]; [clipEndSec] null = file end.
  final double clipStartSec;
  final double? clipEndSec;
  final bool fadeIn;
  final bool fadeOut;

  const MusicTrack({
    required this.path,
    required this.title,
    this.duration,
    this.isAsset = false,
    this.volume = 100,
    this.timelineStartSec = 0,
    this.timelineEndSec,
    this.clipStartSec = 0,
    this.clipEndSec,
    this.fadeIn = false,
    this.fadeOut = false,
  });

  MusicTrack copyWith({
    int? volume,
    Duration? duration,
    double? timelineStartSec,
    double? timelineEndSec,
    bool clearTimelineEnd = false,
    double? clipStartSec,
    double? clipEndSec,
    bool clearClipEnd = false,
    bool? fadeIn,
    bool? fadeOut,
  }) {
    return MusicTrack(
      path: path,
      title: title,
      duration: duration ?? this.duration,
      isAsset: isAsset,
      volume: volume ?? this.volume,
      timelineStartSec: timelineStartSec ?? this.timelineStartSec,
      timelineEndSec: clearTimelineEnd
          ? null
          : (timelineEndSec ?? this.timelineEndSec),
      clipStartSec: clipStartSec ?? this.clipStartSec,
      clipEndSec: clearClipEnd ? null : (clipEndSec ?? this.clipEndSec),
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
    );
  }

  /// Built-in Popular tracks shown in the editor music sheet and Library.
  static const popular = <MusicTrack>[
    MusicTrack(path: 'assets/music/songs_1.mp3', title: 'Popular Beat', isAsset: true),
    MusicTrack(path: 'assets/music/songs_2.mp3', title: 'Soft Piano', isAsset: true),
    MusicTrack(path: 'assets/music/songs_3.mp3', title: 'Upbeat Pop', isAsset: true),
    MusicTrack(path: 'assets/music/songs_4.mp3', title: 'Chill Wave', isAsset: true),
    MusicTrack(path: 'assets/music/songs_5.mp3', title: 'Cinematic', isAsset: true),
    MusicTrack(path: 'assets/music/songs_6.mp3', title: 'Happy Day', isAsset: true),
  ];
}

enum PhotoAnimationType {
  none,
  fade,
  slightZoom,
  zoomIn,
  zoomOut,
  shake,
  slideLeft,
  dynamicZoom,
  dynamicZoomAlt,
  wiper,
  pendulum,
  upAndDown,
  shake2,
  mirror,
  slideUp,
  slideRight,
  slideDown,
  leftAndRight,
  spinRight,
  spinLeft,
  spinUpper,
  mirrorOutside,
  bottomOut,
  leftOut,
  rightOut,
  topOut,
  dynamicZoomOut,
  flipLeft,
  flipLower,
  flipRight,
  slideOutTop,
  slideOutBottom,
  rotateFade,
  flyOutLeft,
  flyOutRight,
  flyOutUp,
}

class SlideshowPhoto {
  final String id;
  final String path;
  final PhotoFilterPreset filter;
  final double durationSec;
  final int? backgroundArgb;

  /// 0 is the sharp thumb fill. 1–4 add more blur. Null keeps a solid color.
  final int? backgroundBlurLevel;
  final double? cropAspectRatio;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final double cropDegrees;
  final bool mirrored;
  final bool flipped;
  final int rotationQuarterTurns;
  final PhotoAnimationType animationIn;
  final PhotoAnimationType animationOut;
  final PhotoAnimationType animationLoop;
  final double animationInDurationSec;
  final double animationOutDurationSec;
  final double animationLoopDurationSec;

  SlideshowPhoto({
    required this.id,
    required this.path,
    this.filter = PhotoFilterPreset.original,
    this.durationSec = AppConstants.defaultDurationSec,
    this.backgroundArgb,
    this.backgroundBlurLevel,
    this.cropAspectRatio,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropWidth = 1,
    this.cropHeight = 1,
    this.cropDegrees = 0,
    this.mirrored = false,
    this.flipped = false,
    this.rotationQuarterTurns = 0,
    this.animationIn = PhotoAnimationType.none,
    this.animationOut = PhotoAnimationType.none,
    this.animationLoop = PhotoAnimationType.none,
    this.animationInDurationSec = 1.0,
    this.animationOutDurationSec = 1.0,
    this.animationLoopDurationSec = 1.0,
  });

  SlideshowPhoto copyWith({
    String? path,
    PhotoFilterPreset? filter,
    double? durationSec,
    int? backgroundArgb,
    bool clearBackgroundArgb = false,
    int? backgroundBlurLevel,
    bool clearBackgroundBlur = false,
    double? cropAspectRatio,
    bool clearCropAspectRatio = false,
    double? cropLeft,
    double? cropTop,
    double? cropWidth,
    double? cropHeight,
    double? cropDegrees,
    bool? mirrored,
    bool? flipped,
    int? rotationQuarterTurns,
    PhotoAnimationType? animationIn,
    PhotoAnimationType? animationOut,
    PhotoAnimationType? animationLoop,
    double? animationInDurationSec,
    double? animationOutDurationSec,
    double? animationLoopDurationSec,
  }) {
    return SlideshowPhoto(
      id: id,
      path: path ?? this.path,
      filter: filter ?? this.filter,
      durationSec: durationSec ?? this.durationSec,
      backgroundArgb: clearBackgroundArgb
          ? null
          : backgroundArgb ?? this.backgroundArgb,
      backgroundBlurLevel: clearBackgroundBlur
          ? null
          : backgroundBlurLevel ?? this.backgroundBlurLevel,
      cropAspectRatio: clearCropAspectRatio
          ? null
          : cropAspectRatio ?? this.cropAspectRatio,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      cropDegrees: cropDegrees ?? this.cropDegrees,
      mirrored: mirrored ?? this.mirrored,
      flipped: flipped ?? this.flipped,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      animationIn: animationIn ?? this.animationIn,
      animationOut: animationOut ?? this.animationOut,
      animationLoop: animationLoop ?? this.animationLoop,
      animationInDurationSec:
          animationInDurationSec ?? this.animationInDurationSec,
      animationOutDurationSec:
          animationOutDurationSec ?? this.animationOutDurationSec,
      animationLoopDurationSec:
          animationLoopDurationSec ?? this.animationLoopDurationSec,
    );
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

enum TextCaseMode { none, sentence, upper, lower }

enum TextAlignMode { left, center, right }

/// Sentinel so [SlideOverlay.copyWith] can clear nullable color fields.
const Object slideOverlayUnset = Object();

class SlideOverlay {
  final String id;
  final OverlayKind kind;
  final double nx;
  final double ny;
  final double scale;
  final double rotation;
  final String? text;
  final int colorArgb;
  final double opacity;
  final String fontFamily;
  final int fontWeight;
  final double fontSize;
  final TextAlignMode align;
  final TextCaseMode textCase;
  final double letterSpacing;
  final double lineHeight;
  final double curve;
  final int? strokeColorArgb;
  final double strokeWidth;
  final int? bgColorArgb;
  final double bgOpacity;
  final double bgCorner;
  final int? shadowColorArgb;
  final double shadowDistance;
  final double shadowAngle;
  final double shadowOpacity;
  final double shadowBlur;
  final int? gradientEndArgb;
  final String? templateId;
  final String? stickerEmoji;

  const SlideOverlay({
    required this.id,
    required this.kind,
    this.nx = 0.5,
    this.ny = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
    this.text,
    this.colorArgb = 0xFFFFFFFF,
    this.opacity = 1,
    this.fontFamily = '',
    this.fontWeight = 700,
    this.fontSize = 36,
    this.align = TextAlignMode.center,
    this.textCase = TextCaseMode.none,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.curve = 0,
    this.strokeColorArgb,
    this.strokeWidth = 0,
    this.bgColorArgb,
    this.bgOpacity = 0.15,
    this.bgCorner = 10,
    this.shadowColorArgb,
    this.shadowDistance = 4,
    this.shadowAngle = 45,
    this.shadowOpacity = 0.6,
    this.shadowBlur = 6,
    this.gradientEndArgb,
    this.templateId,
    this.stickerEmoji,
  });

  String get displayText {
    final raw = text ?? '';
    switch (textCase) {
      case TextCaseMode.none:
        return raw;
      case TextCaseMode.upper:
        return raw.toUpperCase();
      case TextCaseMode.lower:
        return raw.toLowerCase();
      case TextCaseMode.sentence:
        if (raw.isEmpty) return raw;
        return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
    }
  }

  SlideOverlay copyWith({
    double? nx,
    double? ny,
    double? scale,
    double? rotation,
    String? text,
    int? colorArgb,
    double? opacity,
    String? fontFamily,
    int? fontWeight,
    double? fontSize,
    TextAlignMode? align,
    TextCaseMode? textCase,
    double? letterSpacing,
    double? lineHeight,
    double? curve,
    Object? strokeColorArgb = slideOverlayUnset,
    double? strokeWidth,
    Object? bgColorArgb = slideOverlayUnset,
    double? bgOpacity,
    double? bgCorner,
    Object? shadowColorArgb = slideOverlayUnset,
    double? shadowDistance,
    double? shadowAngle,
    double? shadowOpacity,
    double? shadowBlur,
    Object? gradientEndArgb = slideOverlayUnset,
    Object? templateId = slideOverlayUnset,
    String? stickerEmoji,
  }) {
    return SlideOverlay(
      id: id,
      kind: kind,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      text: text ?? this.text,
      colorArgb: colorArgb ?? this.colorArgb,
      opacity: opacity ?? this.opacity,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      align: align ?? this.align,
      textCase: textCase ?? this.textCase,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      curve: curve ?? this.curve,
      strokeColorArgb: identical(strokeColorArgb, slideOverlayUnset)
          ? this.strokeColorArgb
          : strokeColorArgb as int?,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      bgColorArgb: identical(bgColorArgb, slideOverlayUnset)
          ? this.bgColorArgb
          : bgColorArgb as int?,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      bgCorner: bgCorner ?? this.bgCorner,
      shadowColorArgb: identical(shadowColorArgb, slideOverlayUnset)
          ? this.shadowColorArgb
          : shadowColorArgb as int?,
      shadowDistance: shadowDistance ?? this.shadowDistance,
      shadowAngle: shadowAngle ?? this.shadowAngle,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      gradientEndArgb: identical(gradientEndArgb, slideOverlayUnset)
          ? this.gradientEndArgb
          : gradientEndArgb as int?,
      templateId: identical(templateId, slideOverlayUnset)
          ? this.templateId
          : templateId as String?,
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
