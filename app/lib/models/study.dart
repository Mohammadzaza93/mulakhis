class Flashcard {
  final String front;
  final String back;
  const Flashcard(this.front, this.back);

  Map<String, dynamic> toJson() => {'front': front, 'back': back};
  factory Flashcard.fromJson(Map<String, dynamic> j) =>
      Flashcard(j['front'] as String? ?? '', j['back'] as String? ?? '');
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;

  const QuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.explanation = '',
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answer_index': answerIndex,
        'explanation': explanation,
      };

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
        question: j['question'] as String? ?? '',
        options: (j['options'] as List? ?? []).map((e) => e.toString()).toList(),
        answerIndex: (j['answer_index'] as num?)?.toInt() ?? 0,
        explanation: j['explanation'] as String? ?? '',
      );

  /// سؤال صالح للعرض: أربعة خيارات وإجابة داخل النطاق.
  bool get isValid =>
      question.isNotEmpty && options.length >= 2 && answerIndex >= 0 && answerIndex < options.length;
}

class StudyMaterial {
  final List<Flashcard> flashcards;
  final List<QuizQuestion> quiz;
  const StudyMaterial({required this.flashcards, required this.quiz});

  bool get isEmpty => flashcards.isEmpty && quiz.isEmpty;

  Map<String, dynamic> toJson() => {
        'flashcards': flashcards.map((e) => e.toJson()).toList(),
        'quiz': quiz.map((e) => e.toJson()).toList(),
      };

  factory StudyMaterial.fromJson(Map<String, dynamic> j) => StudyMaterial(
        flashcards: (j['flashcards'] as List? ?? [])
            .map((e) => Flashcard.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((c) => c.front.isNotEmpty && c.back.isNotEmpty)
            .toList(),
        quiz: (j['quiz'] as List? ?? [])
            .map((e) => QuizQuestion.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((q) => q.isValid)
            .toList(),
      );
}
