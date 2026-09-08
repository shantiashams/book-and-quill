import 'dart:math' as math;

import 'rich_page.dart';

class BookRecord {
  const BookRecord({
    required this.id,
    required this.slot,
    required this.title,
    required this.pages,
    required this.spreadStart,
    required this.createdAt,
    required this.updatedAt,
    this.author = '',
    this.favorite = false,
    this.signed = false,
    this.visualVariant = 0,
    this.coverPresetIndex = 14,
    this.customCoverColorValue = 0xFF993333,
  });

  static final math.Random _appearanceRandom = math.Random();
  static const int visualVariantCount = 6;
  static const int coverPresetCount = 16;
  static const int originalCoverPreset = -2;
  static const int customCoverPreset = -1;

  final String id;
  final int slot;
  final String title;
  final List<RichPage> pages;
  final int spreadStart;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String author;
  final bool favorite;
  final bool signed;
  final int visualVariant;
  final int coverPresetIndex;
  final int customCoverColorValue;

  factory BookRecord.fresh(
    int slot, {
    bool randomizeCoverColor = true,
  }) {
    final now = DateTime.now();
    return BookRecord(
      id: '${now.microsecondsSinceEpoch}-$slot',
      slot: slot,
      title: 'Book ${slot + 1}',
      pages: const <RichPage>[RichPage.empty],
      spreadStart: 0,
      createdAt: now,
      updatedAt: now,
      visualVariant: _appearanceRandom.nextInt(visualVariantCount),
      coverPresetIndex: randomizeCoverColor
          ? _appearanceRandom.nextInt(coverPresetCount)
          : originalCoverPreset,
    );
  }

  BookRecord copyWith({
    String? id,
    int? slot,
    String? title,
    List<RichPage>? pages,
    int? spreadStart,
    DateTime? updatedAt,
    DateTime? createdAt,
    String? author,
    bool? favorite,
    bool? signed,
    int? visualVariant,
    int? coverPresetIndex,
    int? customCoverColorValue,
  }) {
    return BookRecord(
      id: id ?? this.id,
      slot: slot ?? this.slot,
      title: title ?? this.title,
      pages: List<RichPage>.unmodifiable(pages ?? this.pages),
      spreadStart: spreadStart ?? this.spreadStart,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      author: author ?? this.author,
      favorite: favorite ?? this.favorite,
      signed: signed ?? this.signed,
      visualVariant: visualVariant ?? this.visualVariant,
      coverPresetIndex: coverPresetIndex ?? this.coverPresetIndex,
      customCoverColorValue:
          customCoverColorValue ?? this.customCoverColorValue,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'slot': slot,
      'title': title,
      'pages': pages.map((page) => page.toJson()).toList(),
      'spreadStart': spreadStart,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'author': author,
      'favorite': favorite,
      'signed': signed,
      'visualVariant': visualVariant,
      'coverPresetIndex': coverPresetIndex,
      'customCoverColorValue': customCoverColorValue,
    };
  }

  factory BookRecord.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final pages = rawPages is List
        ? rawPages.map(RichPage.fromJson).toList()
        : <RichPage>[RichPage.empty];
    if (pages.isEmpty) {
      pages.add(RichPage.empty);
    }

    final slot = (json['slot'] as num?)?.toInt() ?? 0;
    final now = DateTime.now();
    final id = json['id']?.toString() ?? '${now.microsecondsSinceEpoch}-$slot';
    final appearanceHash = _stableAppearanceHash(id);
    final storedVariant = (json['visualVariant'] as num?)?.toInt();
    final storedPreset = (json['coverPresetIndex'] as num?)?.toInt();
    final storedCustomColor =
        (json['customCoverColorValue'] as num?)?.toInt();
    return BookRecord(
      id: id,
      slot: slot,
      title: json['title']?.toString() ?? 'Book ${slot + 1}',
      pages: List<RichPage>.unmodifiable(pages),
      spreadStart: (json['spreadStart'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      author: json['author']?.toString() ?? '',
      favorite: json['favorite'] == true,
      signed: json['signed'] == true,
      visualVariant: storedVariant != null &&
              storedVariant >= 0 &&
              storedVariant < visualVariantCount
          ? storedVariant
          : appearanceHash % visualVariantCount,
      coverPresetIndex: storedPreset != null &&
              storedPreset >= originalCoverPreset &&
              storedPreset < coverPresetCount
          ? storedPreset
          : (appearanceHash ~/ visualVariantCount) % coverPresetCount,
      customCoverColorValue:
          (storedCustomColor ?? 0xFF993333) & 0xFFFFFFFF,
    );
  }

  static int _stableAppearanceHash(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  String get searchableText => <String>[
        title,
        author,
        ...pages.map((page) => page.text),
      ].join('\n').toLowerCase();

  bool get hasWriting => pages.any((page) => page.text.trim().isNotEmpty);
}
