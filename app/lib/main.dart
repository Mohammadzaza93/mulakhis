import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/home_screen.dart';

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
      home: const HomeScreen(),
    );
  }
}
