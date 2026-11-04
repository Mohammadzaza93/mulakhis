import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/api_service.dart';
import '../services/purchase_service.dart';
import '../services/session.dart';

class PaywallScreen extends StatefulWidget {
  /// رسالة اختيارية تُعرض أعلى الشاشة (مثلاً سبب الوصول إليها).
  final String? reason;
  const PaywallScreen({super.key, this.reason});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _api = ApiService();
  List<Package>? _packages;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!PurchaseService.enabled) {
      setState(() => _packages = []);
      return;
    }
    try {
      final user = Session.I.user;
      if (user != null) await PurchaseService.init(user.userId);
      final p = await PurchaseService.packages();
      if (mounted) setState(() => _packages = p);
    } catch (_) {
      if (mounted) {
        setState(() {
          _packages = [];
          _message = 'تعذّر تحميل الباقات الآن، حاول لاحقاً.';
        });
      }
    }
  }

  /// يخبرنا الخادم بالاشتراك عبر Webhook وقد يتأخر ثوانٍ، لذلك نسأل عدة مرات.
  Future<bool> _waitForPro() async {
    for (var i = 0; i < 10; i++) {
      try {
        final me = await _api.fetchMe();
        if (me.isPro) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<void> _run(Future<bool> Function() action,
      {required String success}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await action();
      if (!ok) return; // ألغى المستخدم
      final pro = await _waitForPro();
      if (!mounted) return;
      if (pro) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
        Navigator.of(context).pop(true);
      } else {
        setState(() => _message =
            'تمت العملية، وسيُفعَّل اشتراكك خلال لحظات. أعد فتح التطبيق إن تأخر.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'تعذّرت العملية، لم يُخصم منك شيء. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = Session.I.user;
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراك')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.reason != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(widget.reason!,
                    style: TextStyle(color: scheme.onSecondaryContainer)),
              ),
              const SizedBox(height: 16),
            ],
            Text('اجعل مذاكرتك أسرع',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _row(
                Icons.all_inclusive,
                'ملخصات أكثر كل شهر',
                user == null || user.isPro
                    ? null
                    : 'بدل ${user.limit} ملخصات مجانية شهرياً'),
            _row(Icons.mic, 'تسجيلات صوتية وصور وملفات', 'بكل الصيغ المدعومة'),
            _row(Icons.history, 'مكتبة ملخصاتك محفوظة', null),
            const SizedBox(height: 20),
            if (_packages == null)
              const Center(child: CircularProgressIndicator())
            else if (_packages!.isEmpty)
              Text(
                PurchaseService.enabled
                    ? 'لا توجد باقات متاحة حالياً.'
                    : 'الاشتراك غير مفعّل بعد في هذه النسخة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              for (final p in _packages!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => PurchaseService.buy(p),
                            success: 'تم تفعيل اشتراكك، شكراً لك!'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                    child: Text(
                        '${p.storeProduct.title} — ${p.storeProduct.priceString}'),
                  ),
                ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error)),
            ],
            if (PurchaseService.enabled)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await PurchaseService.restore();
                          return true;
                        }, success: 'تمت استعادة اشتراكك'),
                child: const Text('استعادة المشتريات'),
              ),
            const SizedBox(height: 8),
            Text(
              'يتجدد الاشتراك تلقائياً ما لم تلغه قبل موعد التجديد من إعدادات المتجر.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String? subtitle) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
      );
}
