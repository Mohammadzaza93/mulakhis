import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _api = ApiService();
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _requested = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final email = _email.text.trim();
    if (email.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await _api.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _requested = true;
        _message = 'أرسلنا رابط/رمز إعادة التعيين إذا كان البريد مسجلاً.';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      await _api.resetPassword(_token.text.trim(), _password.text);
      if (!mounted) return;
      setState(() => _message = 'تم تغيير كلمة المرور. يمكنك تسجيل الدخول الآن.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعادة تعيين كلمة المرور')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _email,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _request,
            child: const Text('إرسال طلب إعادة التعيين'),
          ),
          if (_requested) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _token,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'رمز/رابط إعادة التعيين',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_loading,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _reset,
              child: const Text('تغيير كلمة المرور'),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
