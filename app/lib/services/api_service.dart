import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/summary.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static const _timeout = Duration(minutes: 3);

  Map<String, String> get _headers => {
        if (AppConfig.appKey.isNotEmpty) 'X-App-Key': AppConfig.appKey,
      };

  Future<SummaryItem> summarizeText(String text, String language) async {
    final res = await _send(() => http
        .post(
          Uri.parse('${AppConfig.baseUrl}/summarize/text'),
          headers: {..._headers, 'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({'text': text, 'language': language}),
        )
        .timeout(_timeout));
    return SummaryItem.fromApi(res, language);
  }

  Future<SummaryItem> summarizeFile({
    required String filename,
    required List<int> bytes,
    required String language,
  }) async {
    final res = await _send(() async {
      final req = http.MultipartRequest(
          'POST', Uri.parse('${AppConfig.baseUrl}/summarize/file'))
        ..headers.addAll(_headers)
        ..fields['language'] = language
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await req.send().timeout(_timeout);
      return http.Response.fromStream(streamed);
    });
    return SummaryItem.fromApi(res, language);
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    try {
      final r = await call();
      final body = utf8.decode(r.bodyBytes);
      if (r.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(body) as Map);
      }
      throw ApiException(_errorMessage(r.statusCode, body));
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('استغرقت المعالجة وقتاً طويلاً، حاول بملف أصغر.');
    } on SocketException {
      throw const ApiException('تعذّر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.');
    } on http.ClientException {
      throw const ApiException('تعذّر الاتصال بالخادم. تأكد من الإنترنت ثم أعد المحاولة.');
    } on FormatException {
      throw const ApiException('رد غير متوقع من الخادم.');
    }
  }

  String _errorMessage(int status, String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] is String) return d['detail'] as String;
    } catch (_) {}
    if (status == 401) return 'غير مصرّح بالدخول إلى الخدمة.';
    return 'حدث خطأ ($status). حاول لاحقاً.';
  }
}
