import 'package:flutter/material.dart';

import '../models/summary.dart';
import '../services/api_service.dart';

class AskScreen extends StatefulWidget {
  final SummaryItem item;
  const AskScreen({super.key, required this.item});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _answer;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await _api.ask(widget.item, q);
      if (!mounted) return;
      setState(() => _answer = out);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('اسأل الملف')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            enabled: !_loading,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'اكتب سؤالك عن هذا الملخص',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: const Text('اسأل'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
          if (_answer != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_answer!['answer']?.toString() ?? ''),
                    if ((_answer!['citations'] as List?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      const Text('الاقتباسات:', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      for (final c in (_answer!['citations'] as List))
                        Text('• ${c.toString()}'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
