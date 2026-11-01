/// تُضبط القيم عند التشغيل:
/// flutter run --dart-define=API_BASE_URL=https://api.example.com --dart-define=APP_API_KEY=...
class AppConfig {
  /// 10.0.2.2 هو عنوان جهازك من داخل محاكي أندرويد.
  /// في محاكي آيفون استخدم http://127.0.0.1:8000
  static const baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const appKey = String.fromEnvironment('APP_API_KEY');

  static const maxFileMb = 15;
}
