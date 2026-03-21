import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary    = Color(0xFF000000);
  static const Color secondary  = Color(0xFF2E2E2E);
  static const Color accent     = Color(0xFF276EF1);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface    = Color(0xFFF6F6F6);
  static const Color card       = Color(0xFFFFFFFF);
  static const Color textBody   = Color(0xFF545454);
  static const Color textHeader = Color(0xFF000000);
  static const Color success    = Color(0xFF05A357);
  static const Color error      = Color(0xFFE11900);
  static const Color border     = Color(0xFFEEEEEE);

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [primary, Color(0xFF1F1F1F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppConstants {
  AppConstants._();

  /// Base URL for the SIBNA backend API.
  /// Override via --dart-define=BASE_URL=https://... at build time:
  ///   flutter build apk --dart-define=BASE_URL=https://api.sibna.dev
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8000', // Android emulator localhost
  );

  static const String appName = 'SIBNA';
}
