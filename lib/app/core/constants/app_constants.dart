class AppConstants {
  static const appName = 'Slideshows';
  static const packageId = 'app.graphics_cycle.clipCraft';
  static const creationsFolder = 'SlideShow';
  /// Editor project drafts (JSON + copied photos) — not exported MP4s.
  static const draftsFolder = 'SlideShowDrafts';
  static const minPhotos = 4;
  static const maxPhotos = 30;
  /// Preview + export transition length (same for both).
  /// Split evenly: 8 at end of A + 8 at start of B.
  static const framesPerTransition = 16;
  /// Editor preview uses the same count as export.
  static const previewFramesPerTransition = framesPerTransition;
  static const holdFrames = 8;

  /// Outgoing half — **end** of photo A (8 of 16).
  static int transitionOutFrames([int total = framesPerTransition]) =>
      total ~/ 2;

  /// Incoming half — **start** of photo B (8 of 16).
  static int transitionInFrames([int total = framesPerTransition]) =>
      total - transitionOutFrames(total);
  static const defaultDurationSec = 2.0;
  static const durations = <double>[
    1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0,
  ];
}

enum AspectPreset {
  square,
  fourFive,
  portrait9x16,
  landscape16x9,
  threeFour,
  fourThree,
  twoThree,
  threeTwo,
  oneTwo,
  twoOne,
}

extension AspectPresetX on AspectPreset {
  String get label => switch (this) {
        AspectPreset.threeFour => '3:4',
        AspectPreset.fourThree => '4:3',
        AspectPreset.twoThree => '2:3',
        AspectPreset.threeTwo => '3:2',
        AspectPreset.square => '1:1',
        AspectPreset.fourFive => '4:5',
        AspectPreset.portrait9x16 => '9:16',
        AspectPreset.landscape16x9 => '16:9',
        AspectPreset.oneTwo => '1:2',
        AspectPreset.twoOne => '2:1',
      };

  double get ratio => switch (this) {
        AspectPreset.threeFour => 3 / 4,
        AspectPreset.fourThree => 4 / 3,
        AspectPreset.twoThree => 2 / 3,
        AspectPreset.threeTwo => 3 / 2,
        AspectPreset.square => 1,
        AspectPreset.fourFive => 4 / 5,
        AspectPreset.portrait9x16 => 9 / 16,
        AspectPreset.landscape16x9 => 16 / 9,
        AspectPreset.oneTwo => 1 / 2,
        AspectPreset.twoOne => 2 / 1,
      };

  /// Longest edge follows export quality. The other edge keeps [ratio].
  (int, int) sizeForQuality(ExportQuality quality) {
    final long = switch (quality) {
      ExportQuality.p480 => 480,
      ExportQuality.p720 => 720,
      ExportQuality.p1080 => 1080,
    };
    return sizeForLongEdge(long);
  }

  /// Longest edge [long]; the other edge keeps [ratio].
  (int, int) sizeForLongEdge(int long) {
    final r = ratio;
    if ((r - 1).abs() < 0.001) return (long, long);
    if (r > 1) return (long, (long / r).round());
    return ((long * r).round(), long);
  }
}

enum ExportQuality { p480, p720, p1080 }

extension ExportQualityX on ExportQuality {
  String get label => switch (this) {
        ExportQuality.p480 => '480P',
        ExportQuality.p720 => '720P',
        ExportQuality.p1080 => '1080P',
      };
}

enum PhotoFilterPreset {
  original,
  vivid,
  warm,
  cold,
  mono,
  fade,
}

extension PhotoFilterPresetX on PhotoFilterPreset {
  String get label => switch (this) {
        PhotoFilterPreset.original => 'Original',
        PhotoFilterPreset.vivid => 'Vivid',
        PhotoFilterPreset.warm => 'Warm',
        PhotoFilterPreset.cold => 'Cold',
        PhotoFilterPreset.mono => 'B&W',
        PhotoFilterPreset.fade => 'Fade',
      };
}
