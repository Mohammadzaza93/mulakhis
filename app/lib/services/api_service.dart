import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/study.dart';
import '../models/summary.dart';
import '../models/user.dart';
import 'session.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  const ApiException(this.message, [this.status]);

  bool get unauthorized => status == 401;
  bool get quotaExceeded => status == 402;

  @override
  String toString() => message;
}

class ApiService {
  static const _timeout = Duration(minutes: 5);
  static const _shortTimeout = Duration(seconds: 30);

  Map<String, String> get _authHeaders => {
        if (Session.I.token != null)
          'Authorization': 'Bearer ${Session.I.token}',
      };

  Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  // ---------- الحساب ----------
  Future<UserInfo> login(String email, String password) =>
      _auth('/auth/login', email, password);
  Future<UserInfo> register(String email, String password) =>
      _auth('/auth/register', email, password);

  Future<UserInfo> _auth(String path, String email, String password) async {
    final j = await _send(() => http
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_shortTimeout));
    final info = UserInfo.fromJson(j);
    await Session.I.save(j['token'] as String, info);
    return info;
  }

  Future<UserInfo> fetchMe() async {
    final j = await _send(() =>
        http.get(_uri('/me'), headers: _authHeaders).timeout(_shortTimeout));
    final info = UserInfo.fromJson(j);
    Session.I.user = info;
    return info;
  }

  // ---------- التلخيص ----------
  Future<SummaryItem> summarizeText(String text, String language) async {
    final j = await _send(() => http
        .post(
          _uri('/summarize/text'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8'
          },
          body: jsonEncode({'text': text, 'language': language}),
        )
        .timeout(_timeout));
    return SummaryItem.fromApi(j, language);
  }

  Future<SummaryItem> summarizeFile({
    required String filename,
    required List<int> bytes,
    required String language,
  }) =>
      _upload(
          '/summarize/file',
          [http.MultipartFile.fromBytes('file', bytes, filename: filename)],
          language);

  Future<SummaryItem> summarizeAudio({
    required String filename,
    required List<int> bytes,
    required String language,
  }) =>
      _upload(
          '/summarize/audio',
          [http.MultipartFile.fromBytes('file', bytes, filename: filename)],
          language);

  Future<SummaryItem> summarizeImages({
    required List<MapEntry<String, List<int>>> images, // اسم الملف -> البايتات
    required String language,
  }) =>
      _upload(
        '/summarize/image',
        [
          for (final e in images)
            http.MultipartFile.fromBytes('files', e.value, filename: e.key)
        ],
        language,
      );

  Future<StudyMaterial> generateStudy(SummaryItem item) async {
    final j = await _send(() => http
        .post(
          _uri('/study/generate'),
          headers: {
            ..._authHeaders,
            'Content-Type': 'application/json; charset=utf-8'
          },
          body: jsonEncode({
            'summary': item.summary,
            'key_points': item.keyPoints,
            'terms': item.terms.map((t) => t.toJson()).toList(),
            'language': item.language,
          }),
        )
        .timeout(_timeout));
    final material = StudyMaterial.fromJson(j);
    if (material.isEmpty) {
      throw const ApiException(
          'لم تنجح الخدمة في إعداد المراجعة، حاول مرة أخرى.');
    }
    return material;
  }

  Future<SummaryItem> _upload(
      String path, List<http.MultipartFile> files, String language) async {
    final j = await _send(() async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_authHeaders)
        ..fields['language'] = language
        ..files.addAll(files);
      final streamed = await req.send().timeout(_timeout);
      return http.Response.fromStream(streamed);
    });
    return SummaryItem.fromApi(j, language);
  }

  // ---------- أدوات ----------
  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() call) async {
    try {
      final r = await call();
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        throw const ApiException('رد غير متوقع من الخادم.');
      }
      throw ApiException(_errorMessage(r.statusCode, body), r.statusCode);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
          'استغرقت المعالجة وقتاً طويلاً، حاول بملف أصغر.');
    } on SocketException {
      throw const ApiException(
          'تعذّر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.');
    } on http.ClientException {
      throw const ApiException(
          'تعذّر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.');
    } on FormatException {
      throw const ApiException('رد غير متوقع من الخادم.');
    } on TypeError {
      throw const ApiException('رد غير متوقع من الخادم.');
    }
  }

  String _errorMessage(int status, String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] is String) return d['detail'] as String;
      // أخطاء التحقق من FastAPI (422) تأتي كقائمة
      if (d is Map && d['detail'] is List) return 'تحقق من البيانات المدخلة.';
    } catch (_) {}
    if (status == 401) return 'سجّل الدخول من جديد.';
    return 'حدث خطأ ($status). حاول لاحقاً.';
  }
}
