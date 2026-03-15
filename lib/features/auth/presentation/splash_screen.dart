import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_screen.dart';
import '../../vault/presentation/vault_screen.dart';
import '../../../core/constants/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Artificial delay to show the nice splash screen logo
    await Future.delayed(const Duration(seconds: 2)); 
    
    // Check for Enterprise Session Token
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'jwt_token');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // Valid session found -> Auto Login -> Route to Vault directly
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VaultScreen()),
      );
    } else {
      // No session -> Route to Login Auth Screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            Text(
              'SIBNA',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enterprise Security Vault',
              style: TextStyle(color: Colors.white70, letterSpacing: 1),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
