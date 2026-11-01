import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/summary.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'summary_screen.dart';

enum _Source { file, text }

class NewSummaryScreen extends StatefulWidget {
  const NewSummaryScreen({super.key});

  @override
  State<NewSummaryScreen> createState() => _NewSummaryScreenState();
}

class _NewSummaryScreenState extends State<NewSummaryScreen> {
  final _api = ApiService();
  final _storage = StorageService();
  final _textController = TextEditingController();

  _Source _source = _Source.file;
  String _language = 'ar';
  PlatformFile? _file;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_loading &&
      (_source == _Source.file
          ? _file != null
          : _textController.text.trim().length >= 50);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.size > AppConfig.maxFileMb * 1024 * 1024) {
      setState(() => _error = 'الملف أكبر من ${AppConfig.maxFileMb} ميغابايت');
      return;
    }
    setState(() {
      _file = f;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SummaryItem item;
      if (_source == _Source.file) {
        final bytes = _file!.bytes;
        if (bytes == null) throw const ApiException('تعذّرت قراءة الملف، اختره مرة أخرى.');
        item = await _api.summarizeFile(
            filename: _file!.name, bytes: bytes, language: _language);
      } else {
        item = await _api.summarizeText(_textController.text.trim(), _language);
      }
      await _storage.add(item);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SummaryScreen(item: item)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع، حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص جديد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<_Source>(
              segments: const [
                ButtonSegment(
                    value: _Source.file,
                    icon: Icon(Icons.upload_file),
                    label: Text('ملف')),
                ButtonSegment(
                    value: _Source.text,
                    icon: Icon(Icons.notes),
                    label: Text('نص')),
              ],
              selected: {_source},
              onSelectionChanged: _loading
                  ? null
                  : (s) => setState(() {
                        _source = s.first;
                        _error = null;
                      }),
            ),
            const SizedBox(height: 16),
            if (_source == _Source.file) _filePicker(scheme) else _textField(),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('لغة الملخص'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _language,
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: _loading ? null : (v) => setState(() => _language = v!),
                ),
              ],
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'جاري التلخيص...' : 'لخّص'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              Text(
                'قد يستغرق الملف الطويل دقيقة أو أكثر. أبقِ التطبيق مفتوحاً.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filePicker(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _loading ? null : _pickFile,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_file == null ? Icons.cloud_upload_outlined : Icons.description,
                  size: 40, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                _file?.name ?? 'اضغط لاختيار ملف (PDF أو DOCX أو TXT)',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_file == null)
                Text('حتى ${AppConfig.maxFileMb} ميغابايت',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField() {
    return TextField(
      controller: _textController,
      enabled: !_loading,
      minLines: 8,
      maxLines: 14,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'الصق نص المحاضرة هنا (50 حرفاً على الأقل)',
        border: OutlineInputBorder(),
      ),
    );
  }
}
