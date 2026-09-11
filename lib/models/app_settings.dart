import '../services/android_platform.dart';

enum MusicFrequency {
  off,
  defaultFrequency,
  constant;

  String get label => switch (this) {
        MusicFrequency.off => 'OFF',
        MusicFrequency.defaultFrequency => 'DEFAULT',
        MusicFrequency.constant => 'CONSTANT',
      };

  String get storageValue => switch (this) {
        MusicFrequency.off => 'off',
        MusicFrequency.defaultFrequency => 'default',
        MusicFrequency.constant => 'constant',
      };

  static MusicFrequency fromStorage(Object? value) {
    return switch (value) {
      'off' => MusicFrequency.off,
      'constant' => MusicFrequency.constant,
      // Older builds stored a Frequent option. Preserve enabled music when
      // migrating those settings by folding it into the new Default mode.
      'frequent' => MusicFrequency.defaultFrequency,
      _ => MusicFrequency.defaultFrequency,
    };
  }
}

enum PageDateFormat {
  dateOnly,
  dateAndTime;

  String get label => switch (this) {
        PageDateFormat.dateOnly => 'DATE',
        PageDateFormat.dateAndTime => 'DATE & TIME',
      };

  String get storageValue => switch (this) {
        PageDateFormat.dateOnly => 'date',
        PageDateFormat.dateAndTime => 'dateTime',
      };

  static PageDateFormat fromStorage(Object? value) {
    return value == 'dateTime'
        ? PageDateFormat.dateAndTime
        : PageDateFormat.dateOnly;
  }
}

String formatPageDate(DateTime value, PageDateFormat format) {
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  final date = '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  if (format == PageDateFormat.dateOnly) {
    return date;
  }
  return '$date ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class AppSettings {
  const AppSettings({
    this.masterVolume = 1.0,
    this.pageTurnVolume = 0.8,
    this.clickVolume = 0.5,
    this.sliderVolume = 0.5,
    this.musicVolume = 0.35,
    this.musicFrequency = MusicFrequency.defaultFrequency,
    this.musicToast = true,
    this.musicIsland = true,
    this.musicIslandAlwaysExpanded = false,
    this.openBooksInTwoPageMode = false,
    this.bookSizeScale = 1.0,
    this.autoHideEditorControls = true,
    this.randomizeNewBookColors = true,
    this.pageDateFormat = PageDateFormat.dateOnly,
    this.backgroundId = 'stone_bricks',
    this.backgroundOpacity = defaultBackgroundOpacity,
  });

  final double masterVolume;
  final double pageTurnVolume;
  final double clickVolume;
  final double sliderVolume;
  final double musicVolume;
  final MusicFrequency musicFrequency;
  final bool musicToast;
  final bool musicIsland;
  final bool musicIslandAlwaysExpanded;
  final bool openBooksInTwoPageMode;
  final double bookSizeScale;
  final bool autoHideEditorControls;
  final bool randomizeNewBookColors;
  final PageDateFormat pageDateFormat;
  final String backgroundId;
  final double backgroundOpacity;

  static const double defaultBackgroundOpacity = 0.4;
  static const AppSettings defaults = AppSettings();
  static const AppSettings androidDefaults = AppSettings(
    musicFrequency: MusicFrequency.off,
    musicIsland: false,
  );
  static AppSettings get platformDefaults =>
      AndroidPlatform.isAndroid ? androidDefaults : defaults;

  bool get soundEnabled => masterVolume > 0;

  AppSettings copyWith({
    double? masterVolume,
    double? pageTurnVolume,
    double? clickVolume,
    double? sliderVolume,
    double? musicVolume,
    MusicFrequency? musicFrequency,
    bool? musicToast,
    bool? musicIsland,
    bool? musicIslandAlwaysExpanded,
    bool? openBooksInTwoPageMode,
    double? bookSizeScale,
    bool? autoHideEditorControls,
    bool? randomizeNewBookColors,
    PageDateFormat? pageDateFormat,
    String? backgroundId,
    double? backgroundOpacity,
  }) {
    return AppSettings(
      masterVolume: masterVolume ?? this.masterVolume,
      pageTurnVolume: pageTurnVolume ?? this.pageTurnVolume,
      clickVolume: clickVolume ?? this.clickVolume,
      sliderVolume: sliderVolume ?? this.sliderVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      musicFrequency: musicFrequency ?? this.musicFrequency,
      musicToast: musicToast ?? this.musicToast,
      musicIsland: musicIsland ?? this.musicIsland,
      musicIslandAlwaysExpanded:
          musicIslandAlwaysExpanded ?? this.musicIslandAlwaysExpanded,
      openBooksInTwoPageMode:
          openBooksInTwoPageMode ?? this.openBooksInTwoPageMode,
      bookSizeScale: bookSizeScale ?? this.bookSizeScale,
      autoHideEditorControls:
          autoHideEditorControls ?? this.autoHideEditorControls,
      randomizeNewBookColors:
          randomizeNewBookColors ?? this.randomizeNewBookColors,
      pageDateFormat: pageDateFormat ?? this.pageDateFormat,
      backgroundId: backgroundId ?? this.backgroundId,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'formatVersion': 9,
      // Retained for older builds that may read the same settings file.
      'soundEnabled': soundEnabled,
      'masterVolume': masterVolume,
      'pageTurnVolume': pageTurnVolume,
      'clickVolume': clickVolume,
      'sliderVolume': sliderVolume,
      'musicVolume': musicVolume,
      'musicFrequency': musicFrequency.storageValue,
      'musicToast': musicToast,
      'musicIsland': musicIsland,
      'musicIslandAlwaysExpanded': musicIslandAlwaysExpanded,
      'openBooksInTwoPageMode': openBooksInTwoPageMode,
      'bookSizeScale': bookSizeScale,
      'autoHideEditorControls': autoHideEditorControls,
      'randomizeNewBookColors': randomizeNewBookColors,
      'pageDateFormat': pageDateFormat.storageValue,
      'backgroundId': backgroundId,
      'backgroundOpacity': backgroundOpacity,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    double normalized(String key, double fallback) {
      return ((json[key] as num?)?.toDouble() ?? fallback)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    final legacyEnabled = json['soundEnabled'] as bool? ?? true;
    final storedMaster = json['masterVolume'] as num?;
    final storedBookSize = (json['bookSizeScale'] as num?)?.toDouble();
    return AppSettings(
      masterVolume: storedMaster == null
          ? (legacyEnabled ? 1.0 : 0.0)
          : storedMaster.toDouble().clamp(0.0, 1.0).toDouble(),
      pageTurnVolume: normalized('pageTurnVolume', defaults.pageTurnVolume),
      clickVolume: normalized('clickVolume', defaults.clickVolume),
      sliderVolume: normalized('sliderVolume', defaults.sliderVolume),
      musicVolume: normalized('musicVolume', defaults.musicVolume),
      musicFrequency:
          json['musicFrequency'] == null
              ? platformDefaults.musicFrequency
              : MusicFrequency.fromStorage(json['musicFrequency']),
      musicToast: json['musicToast'] as bool? ?? true,
      musicIsland: json['musicIsland'] as bool? ?? platformDefaults.musicIsland,
      musicIslandAlwaysExpanded:
          json['musicIslandAlwaysExpanded'] as bool? ?? false,
      openBooksInTwoPageMode:
          json['openBooksInTwoPageMode'] as bool? ?? false,
      bookSizeScale:
          (storedBookSize ?? 1.0).clamp(0.6, 1.4).toDouble(),
      autoHideEditorControls:
          json['autoHideEditorControls'] as bool? ?? true,
      randomizeNewBookColors:
          json['randomizeNewBookColors'] as bool? ?? true,
      pageDateFormat: PageDateFormat.fromStorage(json['pageDateFormat']),
      backgroundId: json['backgroundId'] as String? ?? 'stone_bricks',
      backgroundOpacity:
          normalized('backgroundOpacity', defaultBackgroundOpacity),
    );
  }
}
