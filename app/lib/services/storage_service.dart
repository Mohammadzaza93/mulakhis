import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/summary.dart';

/// تخزين محلي بسيط للمكتبة. في الإصدار التالي يُستبدل بقاعدة بيانات/مزامنة سحابية.
class StorageService {
  static const _key = 'summaries_v1';

  Future<List<SummaryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      final items = list
          .map((e) => SummaryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<SummaryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SummaryItem item) async {
    final items = await load();
    await _write([item, ...items]);
  }

  Future<void> remove(String id) async {
    final items = await load();
    await _write(items.where((e) => e.id != id).toList());
  }
}
