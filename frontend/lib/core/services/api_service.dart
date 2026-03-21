import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/constants.dart';

/// Centralized HTTP client for the SIBNA backend.
///
/// All requests that require authentication include the JWT
/// as a Bearer token in the Authorization header.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final String _base = AppConstants.baseUrl;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'jwt_token';

  // ── Token management ────────────────────────────────────────────────────

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<bool> hasValidToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    // Basic JWT expiry check without a full JWT library dependency
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload['exp'] as int?;
      if (exp == null) return false;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  // ── HTTP helpers ─────────────────────────────────────────────────────────

  Map<String, String> _headers({bool auth = false, String? token}) {
    final h = {'Content-Type': 'application/json'};
    if (auth && token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return json.decode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'status': 'error', 'message': 'Invalid server response (${res.statusCode})'};
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    try {
      final token = auth ? await getToken() : null;
      final res = await http.post(
        Uri.parse('$_base$path'),
        headers: _headers(auth: auth, token: token),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      return _decode(res);
    } on Exception catch (e) {
      debugPrint('ApiService POST $path error: $e');
      return {'status': 'error', 'message': 'Network error. Check your connection.'};
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    bool auth = false,
  }) async {
    try {
      final token = auth ? await getToken() : null;
      final res = await http.get(
        Uri.parse('$_base$path'),
        headers: _headers(auth: auth, token: token),
      ).timeout(const Duration(seconds: 15));
      return _decode(res);
    } on Exception catch (e) {
      debugPrint('ApiService GET $path error: $e');
      return {'status': 'error', 'message': 'Network error. Check your connection.'};
    }
  }

  // ── Auth endpoints ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> verifySim({
    required String? simPhone,
    required String enteredPhone,
    String? countryCode,
    required String deviceId,
  }) =>
      _post('/auth/sim/verify', {
        'sim_phone': simPhone,
        'entered_phone': enteredPhone,
        'country_code': countryCode,
        'device_id': deviceId,
      });

  Future<Map<String, dynamic>> register({
    required String phone,
    required String pubKey,
    required String deviceId,
    String? countryCode,
    String? deviceName,
    String? deviceType,
    bool simVerified = false,
  }) =>
      _post('/auth/register', {
        'phone': phone,
        'pub_key': pubKey,
        'device_id': deviceId,
        'country_code': countryCode,
        'device_name': deviceName,
        'device_type': deviceType,
        'sim_verified': simVerified,
      });

  Future<Map<String, dynamic>> getChallenge({
    required String phone,
    String? countryCode,
  }) =>
      _post('/auth/challenge', {
        'phone': phone,
        'country_code': countryCode,
      });

  Future<Map<String, dynamic>> verifyChallenge({
    required String challengeId,
    required String signedChallenge,
    required String deviceId,
  }) =>
      _post('/auth/verify-challenge', {
        'challenge_id': challengeId,
        'signed_challenge': signedChallenge,
        'device_id': deviceId,
      });

  Future<Map<String, dynamic>> linkEmail({
    required String phone,
    required String email,
    String? countryCode,
  }) =>
      _post('/auth/link-email', {
        'phone': phone,
        'email': email,
        'country_code': countryCode,
      });

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    String? countryCode,
    String? newPubKey,
    String? newDeviceId,
  }) async {
    final data = await _post('/auth/verify-otp', {
      'phone': phone,
      'otp': otp,
      'country_code': countryCode,
      if (newPubKey != null) 'new_pub_key': newPubKey,
      if (newDeviceId != null) 'new_device_id': newDeviceId,
    });
    final token = data['token'] as String?;
    if (token != null) await saveToken(token);
    return data;
  }

  Future<Map<String, dynamic>> initiateRecovery({
    required String phone,
    required String email,
    String? countryCode,
  }) =>
      _post('/auth/recovery/initiate', {
        'phone': phone,
        'email': email,
        'country_code': countryCode,
      });

  // ── Authenticated endpoints ───────────────────────────────────────────────

  Future<Map<String, dynamic>> updateProfile({
    required String phone,
    required String firstName,
    required String lastName,
    String? countryCode,
  }) =>
      _post(
        '/auth/update-profile',
        {
          'phone': phone,
          'first_name': firstName,
          'last_name': lastName,
          'country_code': countryCode,
        },
        auth: true,
      );

  Future<Map<String, dynamic>> getMe() => _get('/auth/me', auth: true);

  Future<Map<String, dynamic>> getDevices() =>
      _get('/auth/devices', auth: true);

  // ── Sign out ──────────────────────────────────────────────────────────────

  Future<void> signOut() => clearToken();
}
