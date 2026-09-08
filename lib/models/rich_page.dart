enum TextModifier {
  bold,
  italic,
  underline,
  strikethrough,
  obfuscated,
}

enum LineAlignment {
  left,
  center,
  right,
}

class CharacterStyle {
  const CharacterStyle({
    this.color = 0xFF000000,
    this.modifiers = const <TextModifier>{},
  });

  static const CharacterStyle normal = CharacterStyle();

  final int color;
  final Set<TextModifier> modifiers;

  bool has(TextModifier modifier) => modifiers.contains(modifier);

  CharacterStyle copyWith({
    int? color,
    Set<TextModifier>? modifiers,
  }) {
    return CharacterStyle(
      color: color ?? this.color,
      modifiers: Set<TextModifier>.unmodifiable(modifiers ?? this.modifiers),
    );
  }

  CharacterStyle toggle(TextModifier modifier, bool enabled) {
    final next = Set<TextModifier>.from(modifiers);
    enabled ? next.add(modifier) : next.remove(modifier);
    return copyWith(modifiers: next);
  }

  Map<String, Object> toJson() => <String, Object>{
        'color': color,
        'modifiers': modifiers.map((modifier) => modifier.name).toList(),
      };

  factory CharacterStyle.fromJson(dynamic json) {
    if (json is! Map) {
      return normal;
    }
    final rawModifiers = json['modifiers'];
    final modifiers = <TextModifier>{};
    if (rawModifiers is List) {
      for (final dynamic raw in rawModifiers) {
        for (final modifier in TextModifier.values) {
          if (modifier.name == raw.toString()) {
            modifiers.add(modifier);
          }
        }
      }
    }
    return CharacterStyle(
      color: (json['color'] as num?)?.toInt() ?? normal.color,
      modifiers: Set<TextModifier>.unmodifiable(modifiers),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! CharacterStyle || color != other.color || modifiers.length != other.modifiers.length) {
      return false;
    }
    return modifiers.containsAll(other.modifiers);
  }

  @override
  int get hashCode => Object.hash(color, Object.hashAllUnordered(modifiers));
}

class StyleRun {
  const StyleRun({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final CharacterStyle style;

  Map<String, Object> toJson() => <String, Object>{
        'start': start,
        'end': end,
        'style': style.toJson(),
      };

  factory StyleRun.fromJson(dynamic json) {
    if (json is! Map) {
      return const StyleRun(start: 0, end: 0, style: CharacterStyle.normal);
    }
    return StyleRun(
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      style: CharacterStyle.fromJson(json['style']),
    );
  }
}

class RichPage {
  const RichPage({
    required this.text,
    this.runs = const <StyleRun>[],
    this.lineAlignments = const <int, LineAlignment>{},
    this.dateStamp,
    this.dateText,
    this.dateRuns = const <StyleRun>[],
  });

  static const RichPage empty = RichPage(text: '');
  static const CharacterStyle defaultDateStyle = CharacterStyle(
    color: 0xFF77716A,
    modifiers: <TextModifier>{TextModifier.italic},
  );

  final String text;
  final List<StyleRun> runs;
  final Map<int, LineAlignment> lineAlignments;
  final DateTime? dateStamp;
  final String? dateText;
  final List<StyleRun> dateRuns;

  factory RichPage.plain(String text) => RichPage(text: text);

  List<CharacterStyle> expandStyles() {
    final styles = List<CharacterStyle>.filled(
      text.length,
      CharacterStyle.normal,
      growable: true,
    );
    for (final run in runs) {
      final start = run.start.clamp(0, text.length).toInt();
      final end = run.end.clamp(start, text.length).toInt();
      for (var index = start; index < end; index++) {
        styles[index] = run.style;
      }
    }
    return styles;
  }

  LineAlignment alignmentForLine(int line) {
    return lineAlignments[line] ?? LineAlignment.left;
  }

  List<StyleRun> effectiveDateRuns(String resolvedText) {
    if (dateRuns.isNotEmpty || resolvedText.isEmpty) {
      return dateRuns;
    }
    return <StyleRun>[
      StyleRun(
        start: 0,
        end: resolvedText.length,
        style: defaultDateStyle,
      ),
    ];
  }

  RichPage copyWith({
    String? text,
    List<StyleRun>? runs,
    Map<int, LineAlignment>? lineAlignments,
    DateTime? dateStamp,
    bool clearDateStamp = false,
    String? dateText,
    bool clearDateText = false,
    List<StyleRun>? dateRuns,
    bool clearDateRuns = false,
  }) {
    return RichPage(
      text: text ?? this.text,
      runs: List<StyleRun>.unmodifiable(runs ?? this.runs),
      lineAlignments: Map<int, LineAlignment>.unmodifiable(
        lineAlignments ?? this.lineAlignments,
      ),
      dateStamp: clearDateStamp ? null : dateStamp ?? this.dateStamp,
      dateText: clearDateText ? null : dateText ?? this.dateText,
      dateRuns: List<StyleRun>.unmodifiable(
        clearDateRuns ? const <StyleRun>[] : dateRuns ?? this.dateRuns,
      ),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'text': text,
        'runs': runs.map((run) => run.toJson()).toList(),
        'lineAlignments': <String, String>{
          for (final entry in lineAlignments.entries)
            if (entry.value != LineAlignment.left)
              entry.key.toString(): entry.value.name,
        },
        if (dateStamp != null) 'dateStamp': dateStamp!.toIso8601String(),
        if (dateText != null) 'dateText': dateText!,
        if (dateRuns.isNotEmpty)
          'dateRuns': dateRuns.map((run) => run.toJson()).toList(),
    };

  factory RichPage.fromJson(dynamic json) {
    if (json is String) {
      return RichPage.plain(json);
    }
    if (json is! Map) {
      return empty;
    }
    final text = json['text']?.toString() ?? '';
    final rawRuns = json['runs'];
    final runs = rawRuns is List
        ? rawRuns.map(StyleRun.fromJson).where((run) => run.end > run.start).toList()
        : <StyleRun>[];
    final lineCount = '\n'.allMatches(text).length + 1;
    final lineAlignments = <int, LineAlignment>{};
    final rawLineAlignments = json['lineAlignments'];
    if (rawLineAlignments is Map) {
      for (final entry in rawLineAlignments.entries) {
        final line = int.tryParse(entry.key.toString());
        if (line == null || line < 0 || line >= lineCount) {
          continue;
        }
        for (final alignment in LineAlignment.values) {
          if (alignment != LineAlignment.left &&
              alignment.name == entry.value.toString()) {
            lineAlignments[line] = alignment;
            break;
          }
        }
      }
    }
    final dateStamp = DateTime.tryParse(json['dateStamp']?.toString() ?? '');
    final dateText = json.containsKey('dateText')
        ? json['dateText']?.toString() ?? ''
        : null;
    final rawDateRuns = json['dateRuns'];
    final dateRuns = rawDateRuns is List
        ? rawDateRuns
            .map(StyleRun.fromJson)
            .where((run) => run.end > run.start)
            .toList()
        : <StyleRun>[];
    return RichPage(
      text: text,
      runs: List<StyleRun>.unmodifiable(runs),
      lineAlignments: Map<int, LineAlignment>.unmodifiable(lineAlignments),
      dateStamp: dateStamp,
      dateText: dateText,
      dateRuns: List<StyleRun>.unmodifiable(dateRuns),
    );
  }
}
