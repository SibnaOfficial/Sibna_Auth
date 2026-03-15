import 'package:flutter/material.dart';
import '../constants/constants.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Outfit', // High-end font
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSurface: AppColors.textHeader,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHeader, fontSize: 34, letterSpacing: -1.0),
        displayMedium: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textHeader, fontSize: 26, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textHeader, fontSize: 24, letterSpacing: -0.5),
        titleLarge: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textHeader, fontSize: 22),
        titleMedium: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textHeader, fontSize: 18),
        bodyLarge: TextStyle(color: AppColors.textHeader, fontSize: 17, height: 1.4),
        bodyMedium: TextStyle(color: AppColors.textBody, fontSize: 15, height: 1.4),
        bodySmall: TextStyle(color: AppColors.textBody, fontSize: 13, height: 1.4),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        hintStyle: const TextStyle(color: Color(0xFFAFAFAF)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}
