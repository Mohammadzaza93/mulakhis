import 'study.dart';

class Term {
  final String term;
  final String definition;
  const Term(this.term, this.definition);

  Map<String, dynamic> toJson() => {'term': term, 'definition': definition};
  factory Term.fromJson(Map<String, dynamic> j) =>
      Term('${j['term'] ?? ''}', '${j['definition'] ?? ''}');
}

List<String> _stringList(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : [];

List<Term> _termList(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((e) => Term.fromJson(Map<String, dynamic>.from(e)))
        .toList()
    : [];

String _string(Object? value) => value == null ? '' : value.toString();

String _stringOr(Object? value, String fallback) {
  final s = _string(value).trim();
  return s.isEmpty ? fallback : s;
}

String? _nullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

class SummaryItem {
  final String id;
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<Term> terms;
  final String language;
  final DateTime createdAt;

  /// النص المستخرج من الصوت أو الصور (إن وُجد).
  final String? transcript;

  /// مواد المراجعة (بطاقات واختبار) بعد توليدها لأول مرة.
  final StudyMaterial? study;

  const SummaryItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.terms,
    required this.language,
    required this.createdAt,
    this.transcript,
    this.study,
  });

  SummaryItem withStudy(StudyMaterial material) => SummaryItem(
        id: id,
        title: title,
        summary: summary,
        keyPoints: keyPoints,
        terms: terms,
        language: language,
        createdAt: createdAt,
        transcript: transcript,
        study: material,
      );

  /// يبني عنصراً من رد الخادم.
  factory SummaryItem.fromApi(Map<String, dynamic> j, String language) {
    return SummaryItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _stringOr(j['title'], 'ملخص جديد'),
      summary: _string(j['summary']),
      keyPoints: _stringList(j['key_points']),
      terms: _termList(j['terms']),
      language: language,
      createdAt: DateTime.now(),
      transcript: _nullableString(j['transcript']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'keyPoints': keyPoints,
        'terms': terms.map((t) => t.toJson()).toList(),
        'language': language,
        'createdAt': createdAt.toIso8601String(),
        'transcript': transcript,
        'study': study?.toJson(),
      };

  Map<String, dynamic> toCloudJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'key_points': keyPoints,
        'terms': terms.map((t) => t.toJson()).toList(),
        'language': language,
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'transcript': transcript,
        'study': study?.toJson(),
      };

  factory SummaryItem.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('عنصر بلا معرّف');
    }

    factory SummaryItem.fromCloud(Map<String, dynamic> j) {
      final createdAt = (j['created_at'] as num?)?.toInt();
      return SummaryItem(
        id: _stringOr(j['id'], DateTime.now().microsecondsSinceEpoch.toString()),
        title: _stringOr(j['title'], 'ملخص جديد'),
        summary: _string(j['summary']),
        keyPoints: _stringList(j['key_points'] ?? j['keyPoints']),
        terms: _termList(j['terms']),
        language: _stringOr(j['language'], 'ar'),
        createdAt: createdAt == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
        transcript: _nullableString(j['transcript']),
        study: j['study'] is Map
            ? StudyMaterial.fromJson(Map<String, dynamic>.from(j['study'] as Map))
            : null,
      );
    }
    return SummaryItem(
      id: id,
      title: _string(j['title']),
      summary: _string(j['summary']),
      keyPoints: _stringList(j['keyPoints'] ?? j['key_points']),
      terms: _termList(j['terms']),
      language: _stringOr(j['language'], 'ar'),
      createdAt: DateTime.tryParse(_string(j['createdAt'])) ?? DateTime.now(),
      transcript: _nullableString(j['transcript']),
      study: j['study'] is Map
          ? StudyMaterial.fromJson(Map<String, dynamic>.from(j['study'] as Map))
          : null,
    );
  }

  /// نص جاهز للنسخ أو المشاركة.
  String toPlainText() {
    final b = StringBuffer()
      ..writeln(title)
      ..writeln()
      ..writeln(summary);
    if (keyPoints.isNotEmpty) {
      b
        ..writeln()
        ..writeln('النقاط الرئيسية:');
      for (final p in keyPoints) {
        b.writeln('• $p');
      }
    }
    if (terms.isNotEmpty) {
      b
        ..writeln()
        ..writeln('المصطلحات:');
      for (final t in terms) {
        b.writeln('• ${t.term}: ${t.definition}');
      }
    }
    return b.toString().trim();
  }
}
