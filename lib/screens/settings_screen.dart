import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_version.dart';
import '../models/app_settings.dart';
import '../services/game_sound_service.dart';
import '../services/android_platform.dart';
import '../theme/app_background.dart';
import '../theme/book_and_quill_theme.dart';
import '../widgets/pixel_button.dart';

enum _SettingsSection { settings, sounds, background }

extension on _SettingsSection {
  String get label => switch (this) {
        _SettingsSection.settings => 'SETTINGS',
        _SettingsSection.sounds => 'SOUNDS',
        _SettingsSection.background => 'BACKGROUND',
      };
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.initialSettings,
    required this.sounds,
    required this.fullscreenListenable,
    required this.onToggleFullscreen,
    required this.onOpenStats,
    required this.onImportBook,
    super.key,
  });

  final AppSettings initialSettings;
  final GameSoundService sounds;
  final ValueListenable<bool> fullscreenListenable;
  final Future<bool> Function() onToggleFullscreen;
  final Future<void> Function(AppSettings settings) onOpenStats;
  final Future<void> Function() onImportBook;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings = widget.initialSettings;
  final ScrollController _scrollController = ScrollController();
  _SettingsSection _section = _SettingsSection.settings;
  int _sectionDirection = 1;
  bool _committed = false;
  bool _libraryActionRunning = false;

  void _applyPreview() => widget.sounds.applySettings(_settings);

  void _replaceSettings(AppSettings settings, {bool audio = false}) {
    setState(() => _settings = settings);
    if (audio) {
      _applyPreview();
    }
  }

  void _setMasterVolume(double value) {
    _replaceSettings(_settings.copyWith(masterVolume: value), audio: true);
    widget.sounds.playSliderTick('master-volume', value);
  }

  void _setPageTurnVolume(double value) {
    _replaceSettings(_settings.copyWith(pageTurnVolume: value), audio: true);
    widget.sounds.playSliderTick('book-turn-volume', value);
  }

  void _setClickVolume(double value) {
    _replaceSettings(_settings.copyWith(clickVolume: value), audio: true);
    widget.sounds.playSliderTick('click-volume', value);
  }

  void _setSliderVolume(double value) {
    _replaceSettings(_settings.copyWith(sliderVolume: value), audio: true);
    widget.sounds.playSliderTick('slider-volume', value);
  }

  void _setMusicVolume(double value) {
    _replaceSettings(_settings.copyWith(musicVolume: value), audio: true);
    widget.sounds.playSliderTick('music-volume', value);
  }

  void _setBookSize(double value) {
    _replaceSettings(_settings.copyWith(bookSizeScale: value));
    widget.sounds.playSliderTick(
      'book-size',
      ((value - 0.6) / 0.8).clamp(0.0, 1.0).toDouble(),
    );
  }

  void _toggleDefaultPageMode() {
    _replaceSettings(_settings.copyWith(
      openBooksInTwoPageMode: !_settings.openBooksInTwoPageMode,
    ));
  }

  void _toggleEditorControls() {
    _replaceSettings(_settings.copyWith(
      autoHideEditorControls: !_settings.autoHideEditorControls,
    ));
  }

  void _toggleNewBookColors() {
    _replaceSettings(_settings.copyWith(
      randomizeNewBookColors: !_settings.randomizeNewBookColors,
    ));
  }

  void _togglePageDateFormat() {
    _replaceSettings(_settings.copyWith(
      pageDateFormat:
          _settings.pageDateFormat == PageDateFormat.dateOnly
              ? PageDateFormat.dateAndTime
              : PageDateFormat.dateOnly,
    ));
  }

  void _cycleMusicFrequency() {
    final values = MusicFrequency.values;
    final next = values[(values.indexOf(_settings.musicFrequency) + 1) %
        values.length];
    _replaceSettings(_settings.copyWith(musicFrequency: next), audio: true);
  }

  void _toggleMusicToast() {
    _replaceSettings(
      _settings.copyWith(musicToast: !_settings.musicToast),
      audio: true,
    );
  }

  void _cycleMusicIsland() {
    final AppSettings next;
    if (!_settings.musicIsland) {
      next = _settings.copyWith(
        musicIsland: true,
        musicIslandAlwaysExpanded: false,
      );
    } else if (!_settings.musicIslandAlwaysExpanded) {
      next = _settings.copyWith(musicIslandAlwaysExpanded: true);
    } else {
      next = _settings.copyWith(
        musicIsland: false,
        musicIslandAlwaysExpanded: false,
      );
    }
    _replaceSettings(next, audio: true);
  }

  void _setBackgroundOpacity(double value) {
    final opacity = value.clamp(0.0, 1.0).toDouble();
    _replaceSettings(_settings.copyWith(backgroundOpacity: opacity));
    widget.sounds.playSliderTick('background-opacity', opacity);
  }

  void _setBackground(String backgroundId) {
    _replaceSettings(
      _settings.copyWith(backgroundId: backgroundId),
      audio: true,
    );
  }

  void _showSection(_SettingsSection next, {int? direction}) {
    if (next == _section) {
      return;
    }
    final currentIndex = _SettingsSection.values.indexOf(_section);
    final nextIndex = _SettingsSection.values.indexOf(next);
    setState(() {
      _sectionDirection = direction ?? (nextIndex > currentIndex ? 1 : -1);
      _section = next;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    widget.sounds.play(GameSound.click, pitch: 0.94, volumeScale: 0.7);
  }

  void _handleSliderScroll(
    PointerSignalEvent event, {
    required double value,
    required double step,
    required double minimum,
    required double maximum,
    required ValueChanged<double> onChanged,
  }) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final next = (value + (delta < 0 ? step : -step))
          .clamp(minimum, maximum)
          .toDouble();
      if (next != value) {
        onChanged(next);
      }
    });
  }

  Future<void> _confirmResetDefaults() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: BookAndQuillColors.woodDark,
            title: const Text('Reset all settings?'),
            content: const Text(
              'This restores every setting, sound level, and background to '
              'its default value.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('RESET SETTINGS'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _settings = AppSettings.defaults);
    _applyPreview();
  }

  void _finish() {
    _committed = true;
    _applyPreview();
    Navigator.of(context).pop(_settings);
  }

  Future<bool> _cancel() async {
    if (!_committed) {
      widget.sounds.applySettings(widget.initialSettings);
    }
    return true;
  }

  Future<void> _runLibraryAction(Future<void> Function() action) async {
    if (_libraryActionRunning) {
      return;
    }
    setState(() => _libraryActionRunning = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _libraryActionRunning = false);
      }
    }
  }

  Widget _buildSettingsSection() {
    final bookSizePercent = (_settings.bookSizeScale * 100).round();
    return Column(
      key: const ValueKey<_SettingsSection>(_SettingsSection.settings),
      children: <Widget>[
        _SettingsRow(
          title: 'DEFAULT BOOK VIEW',
          description: AndroidPlatform.isAndroid
              ? 'Two pages on wide screens; one page on phones'
              : 'Used whenever a book is opened',
          control: PixelButton(
            label: _settings.openBooksInTwoPageMode ? '2 PAGES' : '1 PAGE',
            width: 132,
            compact: true,
            sounds: widget.sounds,
            onPressed: _toggleDefaultPageMode,
          ),
        ),
        const SizedBox(height: 22),
        if (!AndroidPlatform.isAndroid) ...<Widget>[
        _SettingsRow(
          title: 'BOOK SIZE',
          description: '$bookSizePercent%  •  Updates when you return to a book',
          control: _MinecraftSlider(
            value: _settings.bookSizeScale,
            minimum: 0.6,
            maximum: 1.4,
            divisions: 16,
            onChanged: _setBookSize,
            onPointerSignal: (event) => _handleSliderScroll(
              event,
              value: _settings.bookSizeScale,
              step: 0.05,
              minimum: 0.6,
              maximum: 1.4,
              onChanged: _setBookSize,
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsRow(
          title: 'INTERFACE CONTROLS',
          description: 'Editor panels, Done, and shelf navigation controls',
          control: PixelButton(
            label: _settings.autoHideEditorControls
                ? 'AUTO-HIDE'
                : 'ALWAYS VISIBLE',
            width: 154,
            compact: true,
            sounds: widget.sounds,
            onPressed: _toggleEditorControls,
          ),
        ),
        const SizedBox(height: 22),
        ],
        _SettingsRow(
          title: 'PAGE DATE',
          description: AndroidPlatform.isAndroid
              ? 'Format used by the Date button in Tools'
              : 'Format used when DATE or Ctrl+D adds a stamp',
          control: PixelButton(
            label: _settings.pageDateFormat.label,
            width: 148,
            compact: true,
            sounds: widget.sounds,
            onPressed: _togglePageDateFormat,
          ),
        ),
        const SizedBox(height: 22),
        _SettingsRow(
          title: 'NEW BOOK COLORS',
          description: 'Random Minecraft color or original book texture',
          control: PixelButton(
            label: _settings.randomizeNewBookColors ? 'RANDOM' : 'ORIGINAL',
            width: 132,
            compact: true,
            sounds: widget.sounds,
            onPressed: _toggleNewBookColors,
          ),
        ),
        const SizedBox(height: 22),
        if (!AndroidPlatform.isAndroid)
        _SettingsRow(
          title: 'FULLSCREEN',
          description: 'F11 toggles fullscreen anywhere',
          control: ValueListenableBuilder<bool>(
            valueListenable: widget.fullscreenListenable,
            builder: (context, fullscreen, _) => PixelButton(
              label: fullscreen ? 'FULLSCREEN' : 'WINDOWED',
              width: 132,
              compact: true,
              sounds: widget.sounds,
              onPressed: widget.onToggleFullscreen,
            ),
          ),
        ),
        const SizedBox(height: 27),
        const _SettingsSectionHeader('LIBRARY TOOLS'),
        const SizedBox(height: 16),
        _SettingsRow(
          title: 'STATISTICS',
          description: 'View your library and writing activity',
          control: PixelButton(
            label: 'STATS',
            width: 120,
            compact: true,
            enabled: !_libraryActionRunning,
            sounds: widget.sounds,
            onPressed: () => _runLibraryAction(
              () => widget.onOpenStats(_settings),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SettingsRow(
          title: 'IMPORT BOOK',
          description: 'Add a saved book to the first empty slot',
          control: PixelButton(
            label: 'IMPORT',
            width: 120,
            compact: true,
            enabled: !_libraryActionRunning,
            sounds: widget.sounds,
            onPressed: () => _runLibraryAction(widget.onImportBook),
          ),
        ),
      ],
    );
  }

  Widget _buildSoundsSection() {
    const buttonWidth = 154.0;
    String percent(double value) => '${(value * 100).round()}%';
    return Column(
      key: const ValueKey<_SettingsSection>(_SettingsSection.sounds),
      children: <Widget>[
        _volumeRow(
          title: 'MASTER VOLUME',
          value: _settings.masterVolume,
          description: percent(_settings.masterVolume),
          setter: _setMasterVolume,
        ),
        const SizedBox(height: 22),
        _volumeRow(
          title: 'BOOK TURN VOLUME',
          value: _settings.pageTurnVolume,
          description: '${percent(_settings.pageTurnVolume)}  •  Release to preview',
          setter: _setPageTurnVolume,
          onChangeEnd: (_) => widget.sounds.play(GameSound.pageTurn),
        ),
        const SizedBox(height: 22),
        _volumeRow(
          title: 'CLICK VOLUME',
          value: _settings.clickVolume,
          description: percent(_settings.clickVolume),
          setter: _setClickVolume,
        ),
        const SizedBox(height: 22),
        _volumeRow(
          title: 'SLIDER VOLUME',
          value: _settings.sliderVolume,
          description: percent(_settings.sliderVolume),
          setter: _setSliderVolume,
        ),
        const SizedBox(height: 22),
        _volumeRow(
          title: 'MUSIC VOLUME',
          value: _settings.musicVolume,
          description: percent(_settings.musicVolume),
          setter: _setMusicVolume,
        ),
        const SizedBox(height: 24),
        _SettingsRow(
          title: 'MUSIC FREQUENCY',
          description: 'Off, normal pauses, or continuous music',
          control: PixelButton(
            label: _settings.musicFrequency.label,
            width: buttonWidth,
            compact: true,
            sounds: widget.sounds,
            onPressed: _cycleMusicFrequency,
          ),
        ),
        const SizedBox(height: 22),
        _SettingsRow(
          title: 'MUSIC ISLAND',
          description: AndroidPlatform.isAndroid
              ? 'Open with the arrow, keep it always big, or hide it'
              : 'Expand on hover, keep it always big, or hide it',
          control: PixelButton(
            label: !_settings.musicIsland
                ? 'OFF'
                : _settings.musicIslandAlwaysExpanded
                    ? 'ALWAYS BIG'
                    : 'ON',
            width: buttonWidth,
            compact: true,
            sounds: widget.sounds,
            onPressed: _cycleMusicIsland,
          ),
        ),
        const SizedBox(height: 22),
        _SettingsRow(
          title: 'MUSIC TOAST',
          description: 'Show the song and artist when music begins',
          control: PixelButton(
            label: _settings.musicToast ? 'ON' : 'OFF',
            width: buttonWidth,
            compact: true,
            sounds: widget.sounds,
            onPressed: _toggleMusicToast,
          ),
        ),
      ],
    );
  }

  Widget _volumeRow({
    required String title,
    required String description,
    required double value,
    required ValueChanged<double> setter,
    ValueChanged<double>? onChangeEnd,
  }) {
    return _SettingsRow(
      title: title,
      description: description,
      control: _MinecraftSlider(
        value: value,
        minimum: 0,
        maximum: 1,
        divisions: 20,
        onChanged: setter,
        onChangeEnd: onChangeEnd,
        onPointerSignal: (event) => _handleSliderScroll(
          event,
          value: value,
          step: 0.05,
          minimum: 0,
          maximum: 1,
          onChanged: setter,
        ),
      ),
    );
  }

  Widget _buildBackgroundSection() {
    return Column(
      key: const ValueKey<_SettingsSection>(_SettingsSection.background),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Choose the block texture used behind your library, books, settings, and statistics.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFB5AFA5), fontSize: 12),
        ),
        const SizedBox(height: 22),
        _SettingsRow(
          title: 'BACKGROUND OPACITY',
          description: '${(_settings.backgroundOpacity * 100).round()}%'
              '  •  Adjust the opacity of the background',
          control: _MinecraftSlider(
            value: _settings.backgroundOpacity,
            minimum: 0,
            maximum: 1,
            divisions: 100,
            onChanged: _setBackgroundOpacity,
            onPointerSignal: (event) => _handleSliderScroll(
              event,
              value: _settings.backgroundOpacity,
              step: 0.01,
              minimum: 0,
              maximum: 1,
              onChanged: _setBackgroundOpacity,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            for (final preset in AppBackgroundCatalog.presets)
              _BackgroundChoice(
                preset: preset,
                selected: preset.id == _settings.backgroundId,
                sounds: widget.sounds,
                onSelected: () => _setBackground(preset.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    final values = _SettingsSection.values;
    final index = values.indexOf(_section);
    final previous = values[(index - 1 + values.length) % values.length];
    final next = values[(index + 1) % values.length];
    if (AndroidPlatform.isAndroid) {
      Widget label(_SettingsSection section, bool active, int direction) =>
        Expanded(flex: active ? 2 : 1, child: InkWell(
          onTap: active ? null : () => _showSection(section, direction: direction),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: FittedBox(fit: BoxFit.scaleDown,
              child: Text(section.label, style: TextStyle(
                color: active ? Colors.white : const Color(0xFF91897C),
                fontSize: active ? 22 : 14))),
          ),
        ));
      return Row(children: <Widget>[
        label(previous, false, -1), label(_section, true, 0), label(next, false, 1),
      ]);
    }
    return SizedBox(
      height: 46,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SectionLabel(
              label: previous.label,
              alignment: Alignment.centerLeft,
              onTap: () => _showSection(previous, direction: -1),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              _section.label,
              key: ValueKey<_SettingsSection>(_section),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                letterSpacing: 2,
                shadows: <Shadow>[
                  Shadow(color: Colors.black, offset: Offset(3, 3)),
                ],
              ),
            ),
          ),
          Expanded(
            child: _SectionLabel(
              label: next.label,
              alignment: Alignment.centerRight,
              onTap: () => _showSection(next, direction: 1),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_section) {
      _SettingsSection.settings => _buildSettingsSection(),
      _SettingsSection.sounds => _buildSoundsSection(),
      _SettingsSection.background => _buildBackgroundSection(),
    };
    return WillPopScope(
      onWillPop: _cancel,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AppBackground(
                    backgroundId: _settings.backgroundId,
                    opacity: _settings.backgroundOpacity,
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.all(AndroidPlatform.isAndroid ? 12 : 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Container(
                          padding: AndroidPlatform.isAndroid
                              ? const EdgeInsets.fromLTRB(14, 16, 14, 20)
                              : const EdgeInsets.fromLTRB(30, 24, 30, 25),
                          decoration: BoxDecoration(
                            color: const Color(0xEB17110D),
                            border: Border.all(
                              color: const Color(0xFF8B8B8B),
                              width: 3,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Colors.black87,
                                offset: Offset(7, 7),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _buildSectionHeader(),
                              const SizedBox(height: 21),
                              ClipRect(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 330),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    final offset = Tween<Offset>(
                                      begin: Offset(
                                        _sectionDirection.toDouble() * 0.18,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(animation);
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: offset,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: content,
                                ),
                              ),
                              const SizedBox(height: 31),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 10,
                                children: <Widget>[
                                  PixelButton(
                                    label: 'RESET',
                                    width: 136,
                                    sounds: widget.sounds,
                                    onPressed: () => _confirmResetDefaults(),
                                  ),
                                  PixelButton(
                                    label: 'DONE',
                                    width: 136,
                                    sounds: widget.sounds,
                                    onPressed: _finish,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'BOOK AND QUILL  •  VERSION ${AppVersion.value}  •  Made by SHANTIASHAMS',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: BookAndQuillColors.gold,
                                  fontSize: 11,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.alignment,
    required this.onTap,
  });

  final String label;
  final Alignment alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF77736D),
              fontSize: 15,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MinecraftSlider extends StatelessWidget {
  const _MinecraftSlider({
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.divisions,
    required this.onChanged,
    required this.onPointerSignal,
    this.onChangeEnd,
  });

  final double value;
  final double minimum;
  final double maximum;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final void Function(PointerSignalEvent event) onPointerSignal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AndroidPlatform.isAndroid
          ? (MediaQuery.sizeOf(context).width - 64).clamp(120.0, 270.0).toDouble()
          : 270,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: onPointerSignal,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: BookAndQuillColors.gold,
            inactiveTrackColor: const Color(0xFF3C3C3C),
            thumbColor: const Color(0xFFE0E0E0),
            overlayColor: const Color(0x33F4C950),
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: value,
            min: minimum,
            max: maximum,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    );
  }
}

class _BackgroundChoice extends StatefulWidget {
  const _BackgroundChoice({
    required this.preset,
    required this.selected,
    required this.sounds,
    required this.onSelected,
  });

  final AppBackgroundPreset preset;
  final bool selected;
  final GameSoundService sounds;
  final VoidCallback onSelected;

  @override
  State<_BackgroundChoice> createState() => _BackgroundChoiceState();
}

class _BackgroundChoiceState extends State<_BackgroundChoice> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          widget.sounds.play(GameSound.click);
          widget.onSelected();
        },
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.preset.label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              border: Border.all(
                color: widget.selected
                    ? BookAndQuillColors.gold
                    : _hovering
                        ? Colors.white
                        : const Color(0xFF636363),
                width: widget.selected ? 3 : 2,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Colors.black54, offset: Offset(3, 3)),
              ],
            ),
            child: ClipRect(
              child: BlockTextureImage(preset: widget.preset),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.description,
    required this.control,
  });

  final String title;
  final String description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 570;
        final text = Column(
          crossAxisAlignment:
              narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              textAlign: narrow ? TextAlign.center : TextAlign.left,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: narrow ? TextAlign.center : TextAlign.left,
              style: const TextStyle(
                color: Color(0xFFAAA49A),
                fontSize: 11,
              ),
            ),
          ],
        );
        if (narrow) {
          return Column(
            children: <Widget>[
              text,
              const SizedBox(height: 11),
              control,
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: text),
            const SizedBox(width: 24),
            control,
          ],
        );
      },
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(height: 1, color: Color(0xFF5A554F)),
        const SizedBox(height: 17),
        Text(
          label,
          style: const TextStyle(
            color: BookAndQuillColors.gold,
            fontSize: 14,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}
