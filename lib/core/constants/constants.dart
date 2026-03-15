import 'package:flutter/material.dart';

class AppColors {
  // Premium Light Theme (Rider/Uber inspired)
  static const Color primary = Color(0xFF000000);    // Black (Main accent)
  static const Color secondary = Color(0xFF2E2E2E);  // Dark Grey
  static const Color accent = Color(0xFF276EF1);     // Uber Blue (Action color)
  
  static const Color background = Color(0xFFFFFFFF); // Pure White
  static const Color surface = Color(0xFFF6F6F6);    // Very Light Grey
  static const Color card = Color(0xFFFFFFFF);
  
  static const Color textBody = Color(0xFF545454);   // Dark Slate
  static const Color textHeader = Color(0xFF000000); // Black
  
  static const Color success = Color(0xFF05A357);   // Green
  static const Color error = Color(0xFFE11900);     // Red
  static const Color border = Color(0xFFEEEEEE);    // Light grey border
  
  static const LinearGradient premiumGradient = LinearGradient(
    colors: [primary, Color(0xFF1F1F1F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppConstants {
  static const String baseUrl = "http://192.168.1.2:8000";
}
