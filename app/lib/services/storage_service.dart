import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/summary.dart';
import 'api_service.dart';

/// تخزين محلي مع مزامنة سحابية اختيارية عند توفر الاتصال.
class StorageService {
  static const _key = 'summaries_v1';

  Future<List<SummaryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final items = <SummaryItem>[];
      for (final e in list) {
        if (e is! Map) continue;
        try {
          items.add(SummaryItem.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<SummaryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SummaryItem item) async {
    final items = await load();
    await _write([item, ...items]);
    _pushCloud(item);
  }

  Future<void> update(SummaryItem item) async {
    final items = await load();
    await _write([for (final e in items) e.id == item.id ? item : e]);
    _pushCloud(item);
  }

  Future<void> remove(String id) async {
    final items = await load();
    await _write(items.where((e) => e.id != id).toList());
    ApiService().deleteLibraryItem(id).catchError((_) {});
  }

  void _pushCloud(SummaryItem item) {
    ApiService().upsertLibraryItem(item).catchError((_) {});
  }

  /// يجلب المكتبة السحابية ويدمجها مع المحلية (الأحدث يفوز).
  Future<List<SummaryItem>> syncWithCloud() async {
    final local = await load();
    try {
      final remote = await ApiService().fetchLibrary();
      final map = <String, SummaryItem>{};
      for (final e in local) {
        map[e.id] = e;
      }
      for (final e in remote) {
        final existing = map[e.id];
        if (existing == null || e.createdAt.isAfter(existing.createdAt)) {
          map[e.id] = e;
        }
      }
      final remoteIds = remote.map((e) => e.id).toSet();
      for (final e in local) {
        if (!remoteIds.contains(e.id)) {
          ApiService().upsertLibraryItem(e).catchError((_) {});
        }
      }
      final merged = map.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _write(merged);
      return merged;
    } catch (_) {
      return local;
    }
  }
}
