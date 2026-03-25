import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: KagiBusApp()));
}

class KagiBusApp extends StatelessWidget {
  const KagiBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kagi-Bus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FF88),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        fontFamily: 'monospace',
        // バンドルした NotoSansJP をフォールバックに指定。
        // monospace フォントに含まれない日本語グリフを NotoSansJP で補完し、
        // Linux 環境での文字化け（tofu box）を解消する。
        fontFamilyFallback: const ['NotoSansJP'],
      ),
      home: const HomeScreen(),
    );
  }
}
