import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/splash_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: SibnaApp(),
    ),
  );
}

class SibnaApp extends StatelessWidget {
  const SibnaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIBNA Secure Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
