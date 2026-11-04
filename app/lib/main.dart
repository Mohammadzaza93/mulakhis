import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';
import 'services/purchase_service.dart';
import 'services/session.dart';

void main() => runApp(const MulakhisApp());

class MulakhisApp extends StatelessWidget {
  const MulakhisApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF0E7C86),
      brightness: brightness,
    );
    return base.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(centerTitle: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مُلخِّص',
      debugShowCheckedModeBanner: false,
      // العربية هي اللغة الأساسية، ومنها يأتي اتجاه RTL تلقائياً.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// يقرر الشاشة الأولى: الرئيسية إن كانت الجلسة صالحة، وإلا تسجيل الدخول.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _ready = _check();

  Future<bool> _check() async {
    await Session.I.load();
    if (!Session.I.loggedIn) return false;
    try {
      final me = await ApiService().fetchMe();
      PurchaseService.init(me.userId).catchError((_) {});
      return true;
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await Session.I.clear();
        return false;
      }
      // لا اتصال بالخادم: ندخل بالمكتبة المحلية بدل إخراج المستخدم
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snap.data == true ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
