import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';

class ApiService {
  final String baseUrl = AppConstants.baseUrl;

  Future<Map<String, dynamic>> verifySim({
    required String? simPhone,
    required String enteredPhone,
    String? countryCode,
    required String deviceId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/sim/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sim_phone': simPhone,
        'entered_phone': enteredPhone,
        'country_code': countryCode,
        'device_id': deviceId,
      }),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> linkEmail({
    required String phone,
    required String email,
    String? countryCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/link-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'email': email,
        'country_code': countryCode,
      }),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    String? countryCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'otp': otp,
        'country_code': countryCode,
      }),
    );
    final data = jsonDecode(response.body);
    if (data['token'] != null) {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'jwt_token', value: data['token']);
    }
    return data;
  }

  Future<Map<String, dynamic>> updateProfile({
    required String phone,
    String? countryCode,
    required String firstName,
    required String lastName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/update-profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'country_code': countryCode,
        'first_name': firstName,
        'last_name': lastName,
      }),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getVaultData(String token) async {
    // Simulated Vault Data since this part is "New Application Feature"
    await Future.delayed(const Duration(seconds: 1));
    return {
      'status': 'success',
      'notes': [
        {'id': 1, 'title': 'Personal Keys', 'content': 'XYZ-123-ABC', 'date': '2024-03-12'},
        {'id': 2, 'title': 'Crypto Seed', 'content': 'Apple Banana Cherry...', 'date': '2024-03-11'},
      ]
    };
  }
}
