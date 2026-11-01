import 'package:flutter/material.dart';

import '../models/summary.dart';
import '../services/api_service.dart';
import '../services/purchase_service.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';
import 'new_summary_screen.dart';
import 'paywall_screen.dart';
import 'summary_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  List<SummaryItem>? _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _storage.load();
    if (mounted) setState(() => _items = items);
    try {
      await ApiService().fetchMe();
      if (mounted) setState(() {});
    } catch (_) {
      // بدون اتصال: نعرض آخر قيمة معروفة
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _logout() async {
    await PurchaseService.logOut();
    await Session.I.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _delete(SummaryItem item) async {
    await _storage.remove(item.id);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم حذف الملخص'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () async {
            await _storage.add(item);
            _reload();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final user = Session.I.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مُلخِّص'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: ActionChip(
                avatar: Icon(user.isPro ? Icons.workspace_premium : Icons.bolt, size: 18),
                label: Text(user.isPro ? 'Pro · ${user.remaining}' : '${user.remaining}/${user.limit}'),
                tooltip: user.isPro ? 'اشتراكك فعّال' : 'ملخصات متبقية هذا الشهر',
                onPressed: user.isPro ? null : () => _open(const PaywallScreen()),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'plan') _open(const PaywallScreen());
            },
            itemBuilder: (_) => [
              if (user != null)
                PopupMenuItem(enabled: false, child: Text(user.email)),
              if (user != null && !user.isPro)
                const PopupMenuItem(value: 'plan', child: Text('الاشتراك')),
              const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const NewSummaryScreen()),
        icon: const Icon(Icons.add),
        label: const Text('ملخص جديد'),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Dismissible(
                      key: ValueKey(item.id),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) => _delete(item),
                      child: Card(
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle:
                              Text(item.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(_formatDate(item.createdAt),
                              style: Theme.of(context).textTheme.bodySmall),
                          onTap: () => _open(SummaryScreen(item: item)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text('لا توجد ملخصات بعد', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'سجّل محاضرتك، أو صوّر صفحات، أو ارفع ملف PDF أو Word، وسيجهّز لك التطبيق ملخصاً ونقاطاً رئيسية.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
