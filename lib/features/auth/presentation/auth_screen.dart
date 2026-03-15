import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:pinput/pinput.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:sim_card_info/sim_card_info.dart';
import 'package:sim_card_info/sim_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../core/constants/constants.dart';
import '../../../core/services/api_service.dart';
import '../../vault/presentation/vault_screen.dart';

enum AuthStep { 
  landing, 
  terms, 
  signInInfo, 
  confirmInfo, 
  recoveryPhone, 
  recoveryEmail, 
  otpVerify 
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthStep _currentStep = AuthStep.landing;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final ApiService _apiService = ApiService();
  final SimCardInfo _simCardInfo = SimCardInfo();
  
  bool _isLoading = false;
  String _completePhoneNumber = "";
  String _selectedCountryCode = "DZ";
  String? _simPhoneNumber;
  String? _carrierName;

  // Timer for Resend OTP
  Timer? _resendTimer;
  int _resendCountdown = 30;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _readSimCard();
    _phoneController.addListener(() {
      final text = _phoneController.text;
      if (text.startsWith('0')) {
        _phoneController.value = _phoneController.value.copyWith(
          text: text.replaceFirst('0', ''),
          selection: TextSelection.collapsed(offset: text.length - 1),
        );
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCountdown = 30;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _resendCountdown--;
        });
      }
    });
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;
    setState(() => _isLoading = true);
    try {
      await _apiService.linkEmail(
        phone: _completePhoneNumber.isNotEmpty ? _completePhoneNumber : (_simPhoneNumber ?? ""),
        email: _emailController.text,
      );
      _startResendTimer();
      // Professional Success Feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Verification code sent successfully', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(20),
        ),
      );
    } catch (e) {
      if (e.toString().contains('429')) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                SizedBox(width: 12),
                Text('Security Limit', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              'For your security, you have reached the maximum number of attempts. Please try again in 30 minutes.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('UNDERSTOOD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _readSimCard() async {
    // Permission request moved to signInInfo step
    try {
      final simInfoList = await _simCardInfo.getSimInfo();
      if (simInfoList != null && simInfoList.isNotEmpty) {
        setState(() {
          _simPhoneNumber = simInfoList.first.number;
          _carrierName = simInfoList.first.carrierName; // Fixed: Use carrierName
        });
      }
    } catch (_) {}
  }

  void _navigateToVault() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VaultScreen()),
    );
  }

  Widget _buildNextButton({required VoidCallback? onPressed, bool loading = false}) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        minimumSize: const Size(100, 50),
      ),
      child: loading 
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18),
            ],
          ),
    );
  }

  Widget _buildBackButton({required VoidCallback onPressed}) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFF1F1F1),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back, color: Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _buildCurrentStep(),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case AuthStep.landing:
        return _buildLandingView();
      case AuthStep.terms:
        return _buildTermsView();
      case AuthStep.signInInfo:
        return _buildSignInInfoView();
      case AuthStep.confirmInfo:
        return _buildConfirmInfoView();
      case AuthStep.recoveryPhone:
        return _buildRecoveryPhoneView();
      case AuthStep.recoveryEmail:
        return _buildRecoveryEmailView();
      case AuthStep.otpVerify:
        return _buildOtpView();
    }
  }

  Widget _buildLandingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        key: const ValueKey('landing'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeInDown(child: const Icon(Icons.security, size: 80, color: Colors.black)),
            const SizedBox(height: 48),
            FadeInUp(
              child: Text(
                'SIBNA Vault',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
              ),
            ),
            const SizedBox(height: 12),
            FadeInUp(
              delay: const Duration(milliseconds: 100),
              child: Text(
                'Highly secure local encryption for your data.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 80),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => setState(() => _currentStep = AuthStep.terms),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Start', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 300),
              child: TextButton(
                onPressed: () => setState(() => _currentStep = AuthStep.recoveryPhone),
                child: const Text(
                  'Recover Account',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 15, decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _termsAgreed = false;
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  Widget _buildTermsView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.landing), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 40),
                  FadeInLeft(
                    child: Text(
                      "Review Rider's Terms and Privacy Notice",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.black, 
                        fontWeight: FontWeight.w600,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 100),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54, height: 1.6, fontSize: 13),
                        children: [
                          const TextSpan(text: 'By selecting "I agree", I confirm that I have read and accept the '),
                          TextSpan(text: 'Terms of Use', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                          const TextSpan(text: ' and acknowledge the '),
                          TextSpan(text: 'Privacy Notice', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _termsAgreed = !_termsAgreed),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Text('I agree', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    SizedBox(
                      height: 26,
                      width: 26,
                      child: Checkbox(
                        value: _termsAgreed,
                        onChanged: (v) => setState(() => _termsAgreed = v ?? false),
                        activeColor: Colors.black,
                        checkColor: Colors.white,
                        side: const BorderSide(color: Colors.black, width: 1.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildBackButton(onPressed: () => setState(() => _currentStep = AuthStep.landing)),
                  const Spacer(),
                  _buildNextButton(
                    onPressed: _termsAgreed ? () => setState(() => _currentStep = AuthStep.signInInfo) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSignInInfoView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.terms), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 40),
                  FadeInLeft(
                    child: Text(
                      'Use your phone number to sign in to Rider',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.black, 
                        fontWeight: FontWeight.w600,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      "We'll use a Google service to verify your number with your carrier. It's simple and secure—and only takes a few seconds.",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54, height: 1.5, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              _buildBackButton(onPressed: () => setState(() => _currentStep = AuthStep.terms)),
              const Spacer(),
              _buildNextButton(onPressed: _handleSignInInfoNext),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmInfoView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.signInInfo), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 40),
                  FadeInLeft(
                    child: Text(
                      'Confirm your information',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.black, 
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text('Phone number', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(_simPhoneNumber ?? _completePhoneNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      const Icon(Icons.check_circle, color: Color(0xFF1A73E8), size: 18),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Text('First name', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('Last name', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.black, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              _buildBackButton(onPressed: () => setState(() => _currentStep = AuthStep.signInInfo)),
              const Spacer(),
              _buildNextButton(onPressed: _handleProfileSubmit, loading: _isLoading),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleSignInInfoNext() async {
    final status = await Permission.phone.request();
    if (status.isGranted) {
      await _readSimCard();
      if (_simPhoneNumber != null) {
        _showShareInfoBottomSheet();
      } else {
        setState(() => _currentStep = AuthStep.recoveryPhone);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone permission required for SIM verification.')));
    }
  }

  void _showShareInfoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28))
      ),
      builder: (context) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(28, 36, 28, MediaQuery.of(context).viewInsets.bottom + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share information with Rider?', 
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 19)
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F4E8), // Authentic beige
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE8E0CC), width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.phone_android, size: 28, color: Colors.black),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_carrierName ?? 'Vi', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
                              const SizedBox(height: 4),
                              Text(_simPhoneNumber ?? '', style: const TextStyle(fontSize: 16, color: Colors.black87, letterSpacing: 0.5)),
                              const SizedBox(height: 20),
                              const Text(
                                'This information will be shared:', 
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)
                              ),
                              const SizedBox(height: 4),
                              const Text('• Phone number', style: TextStyle(fontSize: 13, color: Colors.black87)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'When you click "Agree and Continue", Google will enable your carrier (${_carrierName ?? 'Vi'}) to share your number with Rider.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11, color: Colors.black45, height: 1.5),
                        children: [
                          const TextSpan(text: 'Provider terms: Allow your carrier to share your phone number with Google. Google will then share it with this app, see '),
                          TextSpan(
                            text: "Google's Privacy Policy", 
                            style: TextStyle(color: Colors.blue[800], decoration: TextDecoration.underline, fontWeight: FontWeight.w500)
                          ),
                          const TextSpan(text: ". App's use is then subject to the "),
                          TextSpan(
                            text: "app's Privacy Policy", 
                            style: TextStyle(color: Colors.blue[800], decoration: TextDecoration.underline, fontWeight: FontWeight.w500)
                          ),
                          const TextSpan(text: "."),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context), 
                        child: const Text('Cancel', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w500))
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _handleSimVerify();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7A5901),
                          minimumSize: const Size(180, 54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 0,
                        ),
                        child: const Text('Agree and Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  Future<void> _handleSimVerify() async {
    setState(() => _isLoading = true);
    try {
      String deviceId = "device_001";
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? "device_001";
        }
      } catch (_) {}

      final res = await _apiService.verifySim(
        simPhone: _simPhoneNumber, 
        enteredPhone: _simPhoneNumber!, 
        deviceId: deviceId 
      );

      if (res['next_step'] == 'profile' || res['status'] == 'match') {
        setState(() => _currentStep = AuthStep.confirmInfo);
      } else {
        setState(() => _currentStep = AuthStep.recoveryPhone);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleProfileSubmit() async {
    if (_firstNameController.text.isEmpty || _lastNameController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await _apiService.updateProfile(
        phone: _simPhoneNumber ?? _completePhoneNumber,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
      );
      _navigateToVault();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRecoveryPhoneView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              key: const ValueKey('rec_phone'),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.landing), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 20),
                  FadeInLeft(child: Text('Recovery', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 28))),
                  const SizedBox(height: 12),
                  FadeInLeft(child: Text('Enter your registered phone number.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16))),
                  const SizedBox(height: 48),
                  
                  if (_simPhoneNumber != null) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(backgroundColor: Color(0xFFF6F6F6), child: Icon(Icons.sim_card, color: Colors.black)),
                      title: Text(_simPhoneNumber!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Detected SIM card'),
                      trailing: const Text('Use this', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                      onTap: () {
                        setState(() {
                          String normalized = _simPhoneNumber!.replaceFirst('+', '');
                          if (normalized.startsWith('213')) normalized = normalized.replaceFirst('213', '');
                          if (normalized.startsWith('0')) normalized = normalized.replaceFirst('0', '');
                          _phoneController.text = normalized;
                          _completePhoneNumber = "+213$normalized";
                          _currentStep = AuthStep.recoveryEmail;
                        });
                      },
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                  ],
                  
                  IntlPhoneField(
                    controller: _phoneController,
                    initialCountryCode: 'DZ',
                    invalidNumberMessage: 'Enter a valid number format',
                    decoration: const InputDecoration(
                      labelText: 'Phone Number', 
                      counterText: '',
                      labelStyle: TextStyle(color: Colors.black54),
                      floatingLabelStyle: TextStyle(color: Colors.black),
                      errorStyle: TextStyle(color: Color(0xFF555555), fontSize: 13), // Professional subtle grey error
                      focusedErrorBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 2)),
                      errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFCCCCCC))),
                    ),
                    onChanged: (phone) {
                      _completePhoneNumber = phone.completeNumber;
                      _selectedCountryCode = phone.countryISOCode;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_completePhoneNumber.isNotEmpty) setState(() => _currentStep = AuthStep.recoveryEmail);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecoveryEmailView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              key: const ValueKey('rec_email'),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.recoveryPhone), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 20),
                  FadeInLeft(child: Text('Verify Email', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 26))),
                  const SizedBox(height: 12),
                  FadeInLeft(child: Text('Send a code to your registered email for $_completePhoneNumber', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, color: Colors.black54))),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email Address', hintText: 'your@email.com'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleRecoverySubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Text('Get Code'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              key: const ValueKey('otp'),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => setState(() => _currentStep = AuthStep.recoveryEmail), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(height: 20),
                  FadeInLeft(child: Text('Code Sent', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 26))),
                  const SizedBox(height: 12),
                  FadeInLeft(child: Text('Check your inbox at ${_emailController.text}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, color: Colors.black54))),
                  const SizedBox(height: 48),
                  FadeInUp(
                    child: Pinput(
                      length: 6,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      defaultPinTheme: PinTheme(
                        width: 56, height: 64,
                        textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        decoration: BoxDecoration(color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(8)),
                      ),
                      onCompleted: _handleOtpVerify,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        if (!_canResend)
                          Text(
                            'Resend code in ${_resendCountdown}s',
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          )
                        else
                          TextButton(
                            onPressed: _isLoading ? null : _resendCode,
                            child: const Text(
                              'Resend Code',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isLoading) const Center(child: CircularProgressIndicator(color: Colors.black)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRecoverySubmit() async {
    if (!_emailController.text.contains('@')) return;
    setState(() => _isLoading = true);
    try {
      await _apiService.linkEmail(
        phone: _completePhoneNumber, 
        email: _emailController.text
      );
      setState(() => _currentStep = AuthStep.otpVerify);
      _startResendTimer();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOtpVerify(String pin) async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.verifyOtp(phone: _completePhoneNumber, otp: pin);
      if (res['status'] == 'success' || res['status'] == 'recovery_success') {
        _navigateToVault();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
