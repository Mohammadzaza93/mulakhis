import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';

/// جلسة المستخدم: الرمز يُحفظ في التخزين الآمن للجهاز (Keychain/Keystore).
class Session {
  Session._();
  static final Session I = Session._();

  static const _tokenKey = 'auth_token';
  final _storage = const FlutterSecureStorage();

  String? token;
  UserInfo? user;

  bool get loggedIn => token != null;

  Future<void> load() async {
    token = await _storage.read(key: _tokenKey);
  }

  Future<void> save(String newToken, UserInfo info) async {
    token = newToken;
    user = info;
    await _storage.write(key: _tokenKey, value: newToken);
  }

  Future<void> clear() async {
    token = null;
    user = null;
    await _storage.delete(key: _tokenKey);
  }
}
