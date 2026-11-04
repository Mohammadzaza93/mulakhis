import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// تُضبط القيم عند التشغيل أو البناء، مثال:
/// flutter run --dart-define=API_BASE_URL=https://api.example.com
class AppConfig {
  /// 10.0.2.2 هو عنوان جهازك من داخل محاكي أندرويد.
  /// في محاكي آيفون استخدم http://127.0.0.1:8000
  static const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000');

  /// مفاتيح RevenueCat العامة (Public SDK keys) لكل منصة. اتركها فارغة لتعطيل الشراء.
  static const _rcIos = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const _rcAndroid = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static String get revenueCatKey =>
      defaultTargetPlatform == TargetPlatform.iOS ? _rcIos : _rcAndroid;

  static const maxFileMb = 15;
  static const maxAudioMb = 25;
  static const maxImages = 10;
}
