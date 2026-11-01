import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config.dart';
import '../models/summary.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';
import 'paywall_screen.dart';
import 'summary_screen.dart';

enum _Source { file, audio, image, text }

class NewSummaryScreen extends StatefulWidget {
  const NewSummaryScreen({super.key});

  @override
  State<NewSummaryScreen> createState() => _NewSummaryScreenState();
}

class _NewSummaryScreenState extends State<NewSummaryScreen> {
  final _api = ApiService();
  final _storage = StorageService();
  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  final _picker = ImagePicker();

  _Source _source = _Source.file;
  String _language = 'ar';
  bool _loading = false;
  String? _error;

  // ملف
  PlatformFile? _file;

  // صوت
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String? _audioName;
  List<int>? _audioBytes;

  // صور
  final List<XFile> _images = [];

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_loading || _recording) return false;
    switch (_source) {
      case _Source.file:
        return _file != null;
      case _Source.audio:
        return _audioBytes != null;
      case _Source.image:
        return _images.isNotEmpty;
      case _Source.text:
        return _textController.text.trim().length >= 50;
    }
  }

  // ---------- ملف ----------
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

  // ---------- صوت ----------
  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (!await _recorder.hasPermission()) {
      setState(() => _error = 'نحتاج إذن الميكروفون للتسجيل. فعّله من إعدادات الجهاز.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 48000,
      ),
      path: path,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
      _audioBytes = null;
      _audioName = null;
      _error = null;
    });
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    if (path == null) {
      setState(() => _recording = false);
      return;
    }
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    if (bytes.length > AppConfig.maxAudioMb * 1024 * 1024) {
      setState(() {
        _recording = false;
        _error = 'التسجيل أكبر من ${AppConfig.maxAudioMb} ميغابايت، قسّمه إلى تسجيلين.';
      });
      return;
    }
    setState(() {
      _recording = false;
      _audioBytes = bytes;
      _audioName = path.split('/').last;
    });
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'webm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    if (f.size > AppConfig.maxAudioMb * 1024 * 1024) {
      setState(() => _error = 'الملف الصوتي أكبر من ${AppConfig.maxAudioMb} ميغابايت');
      return;
    }
    setState(() {
      _audioBytes = f.bytes;
      _audioName = f.name;
      _error = null;
    });
  }

  // ---------- صور ----------
  Future<void> _addImages({required bool camera}) async {
    final room = AppConfig.maxImages - _images.length;
    if (room <= 0) {
      setState(() => _error = 'الحد الأقصى ${AppConfig.maxImages} صور.');
      return;
    }
    List<XFile> picked;
    if (camera) {
      final one = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      picked = one == null ? [] : [one];
    } else {
      picked = await _picker.pickMultiImage(imageQuality: 85);
    }
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked.take(room));
      _error = picked.length > room ? 'أُضيفت $room صور فقط (الحد الأقصى ${AppConfig.maxImages}).' : null;
    });
  }

  // ---------- إرسال ----------
  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SummaryItem item;
      switch (_source) {
        case _Source.file:
          final bytes = _file!.bytes;
          if (bytes == null) throw const ApiException('تعذّرت قراءة الملف، اختره مرة أخرى.');
          item = await _api.summarizeFile(
              filename: _file!.name, bytes: bytes, language: _language);
        case _Source.audio:
          item = await _api.summarizeAudio(
              filename: _audioName ?? 'audio.m4a', bytes: _audioBytes!, language: _language);
        case _Source.image:
          final list = <MapEntry<String, List<int>>>[];
          for (final x in _images) {
            list.add(MapEntry(x.name, await x.readAsBytes()));
          }
          item = await _api.summarizeImages(images: list, language: _language);
        case _Source.text:
          item = await _api.summarizeText(_textController.text.trim(), _language);
      }
      await _storage.add(item);
      _api.fetchMe().then((_) {}, onError: (_) {}); // تحديث العدّاد
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => SummaryScreen(item: item)));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        await Session.I.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      } else if (e.quotaExceeded) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PaywallScreen(reason: e.message)));
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'حدث خطأ غير متوقع، حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- واجهة ----------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص جديد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              children: [
                _chip(_Source.file, Icons.upload_file, 'ملف'),
                _chip(_Source.audio, Icons.mic, 'صوت'),
                _chip(_Source.image, Icons.photo_camera, 'صور'),
                _chip(_Source.text, Icons.notes, 'نص'),
              ],
            ),
            const SizedBox(height: 16),
            switch (_source) {
              _Source.file => _filePicker(scheme),
              _Source.audio => _audioSection(scheme),
              _Source.image => _imageSection(scheme),
              _Source.text => _textField(),
            },
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
                child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_loading ? 'جاري التلخيص...' : 'لخّص'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              Text(
                'قد يستغرق التسجيل أو الملف الطويل دقائق. أبقِ التطبيق مفتوحاً.',
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

  Widget _chip(_Source s, IconData icon, String label) => ChoiceChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: _source == s,
        onSelected: _loading || _recording
            ? null
            : (_) => setState(() {
                  _source = s;
                  _error = null;
                }),
      );

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

  Widget _audioSection(ColorScheme scheme) {
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(_elapsed.inMinutes)}:${two(_elapsed.inSeconds % 60)}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            _recording
                ? time
                : _audioBytes != null
                    ? 'تم التسجيل: ${_audioName ?? ''}'
                    : 'سجّل المحاضرة أو اختر ملفاً صوتياً',
            textAlign: TextAlign.center,
            style: _recording
                ? Theme.of(context).textTheme.headlineMedium
                : Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _toggleRecording,
            icon: Icon(_recording ? Icons.stop : Icons.mic),
            label: Text(_recording ? 'إيقاف التسجيل' : (_audioBytes != null ? 'تسجيل من جديد' : 'ابدأ التسجيل')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: _recording ? scheme.errorContainer : null,
            ),
          ),
          if (!_recording)
            TextButton.icon(
              onPressed: _loading ? null : _pickAudioFile,
              icon: const Icon(Icons.audio_file_outlined),
              label: const Text('اختيار ملف صوتي'),
            ),
          Text('حتى ${AppConfig.maxAudioMb} ميغابايت (نحو ساعتين من التسجيل)',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _imageSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => _addImages(camera: true),
                icon: const Icon(Icons.photo_camera),
                label: const Text('كاميرا'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => _addImages(camera: false),
                icon: const Icon(Icons.photo_library),
                label: const Text('المعرض'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_images.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text('صوّر صفحات الكتاب أو السبورة (حتى ${AppConfig.maxImages} صور)',
                textAlign: TextAlign.center),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _images.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(_images[i].path),
                          width: 96, height: 96, fit: BoxFit.cover),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: InkWell(
                        onTap: _loading ? null : () => setState(() => _images.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
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
