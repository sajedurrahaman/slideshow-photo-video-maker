class AppConstants {
  static const appName = 'Slideshows';
  static const packageId = 'app.graphics_cycle.clipCraft';
  static const creationsFolder = 'SlideShow';
  static const minPhotos = 4;
  static const maxPhotos = 30;
  static const framesPerTransition = 22;
  static const holdFrames = 8;
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
