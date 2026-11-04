import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/summary.dart';
import '../services/storage_service.dart';
import 'ask_screen.dart';
import 'study_screen.dart';

class SummaryScreen extends StatefulWidget {
  final SummaryItem item;
  const SummaryScreen({super.key, required this.item});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late SummaryItem item = widget.item;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: item.toPlainText()));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم نسخ الملخص')));
  }

  /// بعد العودة من المراجعة نقرأ العنصر المحفوظ، فإن وُلّدت المواد لا تُولَّد ثانيةً.
  Future<void> _openStudy() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StudyScreen(item: item)));
    final saved = (await StorageService().load()).where((e) => e.id == item.id);
    if (mounted && saved.isNotEmpty) setState(() => item = saved.first);
  }

  @override
  Widget build(BuildContext context) {
    final hasTranscript = (item.transcript ?? '').trim().isNotEmpty;
    return DefaultTabController(
      length: hasTranscript ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'نسخ',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: hasTranscript,
            tabs: [
              const Tab(text: 'الملخص'),
              const Tab(text: 'النقاط'),
              const Tab(text: 'المصطلحات'),
              if (hasTranscript) const Tab(text: 'النص الأصلي'),
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'ask-${widget.item.id}',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AskScreen(item: item))),
              icon: const Icon(Icons.question_answer_outlined),
              label: const Text('اسأل'),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'study-${widget.item.id}',
              onPressed: _openStudy,
              icon: const Icon(Icons.quiz_outlined),
              label: Text(item.study == null ? 'راجع (بطاقات واختبار)' : 'راجع'),
            ),
          ],
        ),
        body: TabBarView(children: [
          _SummaryTab(text: item.summary),
          _PointsTab(points: item.keyPoints),
          _TermsTab(terms: item.terms),
          if (hasTranscript) _SummaryTab(text: item.transcript!),
        ]),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final String text;
  const _SummaryTab({required this.text});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        text.isEmpty ? 'لا يوجد ملخص.' : text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.9),
      ),
    );
  }
}

class _PointsTab extends StatelessWidget {
  final List<String> points;
  const _PointsTab({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const Center(child: Text('لا توجد نقاط.'));
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: points.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Icon(Icons.circle,
                size: 8, color: Theme.of(context).colorScheme.primary),
          ),
          Expanded(
            child: SelectableText(points[i],
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(height: 1.7)),
          ),
        ],
      ),
    );
  }
}

class _TermsTab extends StatelessWidget {
  final List<Term> terms;
  const _TermsTab({required this.terms});

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const Center(child: Text('لا توجد مصطلحات.'));
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: terms.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(terms[i].term,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SelectableText(terms[i].definition),
            ],
          ),
        ),
      ),
    );
  }
}
