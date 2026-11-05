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
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _reload();
  }

  Future<void> _logout() async {
    await Session.I.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _syncCloud() async {
    try {
      final items = await _storage.syncWithCloud(ApiService());
      if (!mounted) return;
      setState(() => _items = items);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('\u062a\u0645\u062a \u0627\u0644\u0645\u0632\u0627\u0645\u0646\u0629')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('\u062a\u0639\u0630\u0651\u0631\u062a \u0627\u0644\u0645\u0632\u0627\u0645\u0646\u0629')));
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('\u062d\u0630\u0641 \u0627\u0644\u062d\u0633\u0627\u0628'),
            content: const Text(
                '\u0633\u064a\u064f\u062d\u0630\u0641 \u0627\u0644\u062d\u0633\u0627\u0628 \u0648\u0628\u064a\u0627\u0646\u0627\u062a\u0647 \u0646\u0647\u0627\u0626\u064a\u0627\u064b. \u0647\u0644 \u0623\u0646\u062a \u0645\u062a\u0623\u0643\u062f\u061f'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('\u0625\u0644\u063a\u0627\u0621')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('\u062d\u0630\u0641')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ApiService().deleteAccount();
      await _logout();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final user = Session.I.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('\u0645\u064f\u0644\u062e\u0651\u0650\u0635'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  user.isPro
                      ? 'Pro'
                      : '${user.used}/${user.limit}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              if (user != null)
                PopupMenuItem(enabled: false, child: Text(user.email)),
              const PopupMenuItem(value: 'sync', child: Text('\u0645\u0632\u0627\u0645\u0646\u0629 \u0627\u0644\u0645\u0643\u062a\u0628\u0629')),
              if (user != null && !user.isPro)
                const PopupMenuItem(value: 'plan', child: Text('\u0627\u0644\u0627\u0634\u062a\u0631\u0627\u0643')),
              const PopupMenuItem(
                  value: 'delete-account', child: Text('\u062d\u0630\u0641 \u0627\u0644\u062d\u0633\u0627\u0628')),
              const PopupMenuItem(value: 'logout', child: Text('\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c')),
            ],
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'plan') _open(const PaywallScreen());
              if (v == 'sync') _syncCloud();
              if (v == 'delete-account') _deleteAccount();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const NewSummaryScreen()),
        icon: const Icon(Icons.add),
        label: const Text('\u0645\u0644\u062e\u0635 \u062c\u062f\u064a\u062f'),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Text(
                    '\u0644\u0627 \u0645\u0644\u062e\u0635\u0627\u062a \u0628\u0639\u062f.\n\u0627\u0636\u063a\u0637 + \u0644\u0628\u062f\u0621 \u0623\u0648\u0644 \u0645\u0644\u062e\u0635.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Card(
                      child: ListTile(
                        title: Text(item.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.summary,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => _open(SummaryScreen(item: item)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _storage.remove(item.id);
                            await _reload();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
