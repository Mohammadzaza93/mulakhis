import 'package:flutter/material.dart';

import '../models/study.dart';
import '../models/summary.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';
import 'paywall_screen.dart';

/// شاشة المراجعة: تولّد البطاقات والاختبار عند أول فتح ثم تحفظهما مع الملخص.
class StudyScreen extends StatefulWidget {
  final SummaryItem item;
  const StudyScreen({super.key, required this.item});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final _api = ApiService();
  final _storage = StorageService();

  StudyMaterial? _material;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _material = widget.item.study;
    if (_material == null || _material!.isEmpty) _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final material = await _api.generateStudy(widget.item);
      await _storage.update(widget.item.withStudy(material));
      _api.fetchMe().then((_) {}, onError: (_) {}); // تحديث العدّاد
      if (mounted) setState(() => _material = material);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        await Session.I.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
        return;
      }
      if (e.quotaExceeded) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PaywallScreen(reason: e.message)));
      }
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع، حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _material;
    if (m == null || m.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('المراجعة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _loading
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('جاري إعداد البطاقات والاختبار...'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error ?? 'لا توجد مواد مراجعة.', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _generate, child: const Text('إعادة المحاولة')),
                    ],
                  ),
          ),
        ),
      );
    }

    final tabs = <Tab>[
      if (m.flashcards.isNotEmpty) const Tab(text: 'البطاقات'),
      if (m.quiz.isNotEmpty) const Tab(text: 'الاختبار'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المراجعة'),
          bottom: tabs.length > 1 ? TabBar(tabs: tabs) : null,
        ),
        body: TabBarView(children: [
          if (m.flashcards.isNotEmpty) FlashcardsView(cards: m.flashcards),
          if (m.quiz.isNotEmpty) QuizView(questions: m.quiz),
        ]),
      ),
    );
  }
}

// ======================= البطاقات =======================

/// يعرض البطاقات واحدة واحدة. ما لم يعرفه الطالب يعود إلى آخر الطابور
/// حتى تنتهي كل البطاقات معروفة (تكرار بسيط داخل الجلسة).
class FlashcardsView extends StatefulWidget {
  final List<Flashcard> cards;
  const FlashcardsView({super.key, required this.cards});

  @override
  State<FlashcardsView> createState() => _FlashcardsViewState();
}

class _FlashcardsViewState extends State<FlashcardsView> {
  late List<Flashcard> _queue = List.of(widget.cards);
  bool _flipped = false;
  int _known = 0;
  int _again = 0;

  bool get _done => _queue.isEmpty;

  void _answer({required bool knew}) {
    setState(() {
      final card = _queue.removeAt(0);
      if (knew) {
        _known++;
      } else {
        _again++;
        _queue.add(card);
      }
      _flipped = false;
    });
  }

  void _restart() => setState(() {
        _queue = List.of(widget.cards);
        _flipped = false;
        _known = 0;
        _again = 0;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_done) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 64, color: scheme.primary),
              const SizedBox(height: 12),
              Text('أنهيت كل البطاقات', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('احتجت إعادة $_again مرة'),
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: _restart, child: const Text('ابدأ من جديد')),
            ],
          ),
        ),
      );
    }

    final card = _queue.first;
    final progress = widget.cards.isEmpty ? 0.0 : _known / widget.cards.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 8),
          Text('عرفت $_known من ${widget.cards.length}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: Semantics(
              button: true,
              label: _flipped ? 'الإجابة، اضغط للرجوع للسؤال' : 'السؤال، اضغط لإظهار الإجابة',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _flipped = !_flipped),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey('${card.front}-$_flipped'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _flipped ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_flipped ? 'الإجابة' : 'السؤال',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          Text(
                            _flipped ? card.back : card.front,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.6),
                          ),
                          if (!_flipped) ...[
                            const SizedBox(height: 20),
                            Text('اضغط لإظهار الإجابة',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _flipped ? () => _answer(knew: false) : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('أعد عليّ'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _flipped ? () => _answer(knew: true) : null,
                  icon: const Icon(Icons.check),
                  label: const Text('عرفتها'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================= الاختبار =======================

class QuizView extends StatefulWidget {
  final List<QuizQuestion> questions;
  const QuizView({super.key, required this.questions});

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  int _index = 0;
  int _score = 0;
  int? _selected; // null = لم يُجب بعد
  bool _finished = false;

  QuizQuestion get _q => widget.questions[_index];

  void _choose(int i) {
    if (_selected != null) return; // لا تغيير للإجابة بعد الاختيار
    setState(() {
      _selected = i;
      if (i == _q.answerIndex) _score++;
    });
  }

  void _next() {
    setState(() {
      if (_index + 1 >= widget.questions.length) {
        _finished = true;
      } else {
        _index++;
        _selected = null;
      }
    });
  }

  void _restart() => setState(() {
        _index = 0;
        _score = 0;
        _selected = null;
        _finished = false;
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.questions.length;

    if (_finished) {
      final ratio = total == 0 ? 0.0 : _score / total;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ratio >= 0.7 ? Icons.emoji_events : Icons.menu_book,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 12),
              Text('نتيجتك: $_score من $total',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(ratio >= 0.7 ? 'ممتاز! أنت متمكّن من المادة.' : 'راجع البطاقات ثم أعد المحاولة.'),
              const SizedBox(height: 20),
              FilledButton.tonal(onPressed: _restart, child: const Text('أعد الاختبار')),
            ],
          ),
        ),
      );
    }

    final answered = _selected != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(
            value: (_index + (answered ? 1 : 0)) / total, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 8),
        Text('السؤال ${_index + 1} من $total', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Text(_q.question,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.6)),
        const SizedBox(height: 16),
        for (var i = 0; i < _q.options.length; i++) _option(i, scheme),
        if (answered && _q.explanation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_q.explanation, style: TextStyle(color: scheme.onSecondaryContainer)),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: answered ? _next : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(_index + 1 >= total ? 'إنهاء' : 'التالي'),
        ),
      ],
    );
  }

  Widget _option(int i, ColorScheme scheme) {
    final answered = _selected != null;
    final isCorrect = i == _q.answerIndex;
    final isChosen = i == _selected;

    // اللون وحده لا يكفي: نضيف أيقونة لمن لا يميّزون الألوان
    Color? bg;
    Color border = scheme.outlineVariant;
    IconData? icon;
    if (answered && isCorrect) {
      bg = scheme.primaryContainer;
      border = scheme.primary;
      icon = Icons.check_circle;
    } else if (answered && isChosen) {
      bg = scheme.errorContainer;
      border = scheme.error;
      icon = Icons.cancel;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: answered ? null : () => _choose(i),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: answered && (isCorrect || isChosen) ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_q.options[i], style: const TextStyle(height: 1.5))),
              if (icon != null) Icon(icon, color: isCorrect ? scheme.primary : scheme.error),
            ],
          ),
        ),
      ),
    );
  }
}
