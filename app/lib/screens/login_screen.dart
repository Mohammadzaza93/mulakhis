import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/purchase_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = ApiService();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _hidden = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid =>
      _email.text.contains('@') && _password.text.length >= (_register ? 8 : 1);

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final pass = _password.text;
      final user = _register ? await _api.register(email, pass) : await _api.login(email, pass);
      PurchaseService.init(user.userId).catchError((_) {});
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.auto_stories, size: 56, color: scheme.primary),
                    const SizedBox(height: 12),
                    Text('مُلخِّص',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      _register ? 'أنشئ حسابك لتبدأ بتلخيص محاضراتك' : 'سجّل الدخول لمتابعة ملخصاتك',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      enabled: !_loading,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_loading,
                      obscureText: _hidden,
                      autofillHints: [
                        _register ? AutofillHints.newPassword : AutofillHints.password
                      ],
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _valid && !_loading ? _submit() : null,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        helperText: _register ? '8 أحرف على الأقل' : null,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'إظهار' : 'إخفاء',
                          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
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
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _valid && !_loading ? _submit : null,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? 'إنشاء حساب' : 'دخول'),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(_register ? 'لدي حساب بالفعل' : 'ليس لدي حساب، إنشاء حساب جديد'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
