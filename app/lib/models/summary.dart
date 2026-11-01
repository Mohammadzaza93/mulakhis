class Term {
  final String term;
  final String definition;
  const Term(this.term, this.definition);

  Map<String, dynamic> toJson() => {'term': term, 'definition': definition};
  factory Term.fromJson(Map<String, dynamic> j) =>
      Term(j['term'] as String? ?? '', j['definition'] as String? ?? '');
}

class SummaryItem {
  final String id;
  final String title;
  final String summary;
  final List<String> keyPoints;
  final List<Term> terms;
  final String language;
  final DateTime createdAt;

  const SummaryItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.terms,
    required this.language,
    required this.createdAt,
  });

  /// يبني عنصراً من رد الخادم.
  factory SummaryItem.fromApi(Map<String, dynamic> j, String language) {
    return SummaryItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: j['title'] as String? ?? 'ملخص جديد',
      summary: j['summary'] as String? ?? '',
      keyPoints: (j['key_points'] as List? ?? []).map((e) => e.toString()).toList(),
      terms: (j['terms'] as List? ?? [])
          .map((e) => Term.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      language: language,
      createdAt: DateTime.now(),
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
      };

  factory SummaryItem.fromJson(Map<String, dynamic> j) => SummaryItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        keyPoints: (j['keyPoints'] as List? ?? []).map((e) => e.toString()).toList(),
        terms: (j['terms'] as List? ?? [])
            .map((e) => Term.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        language: j['language'] as String? ?? 'ar',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

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
