import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:pinput/pinput.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:sim_card_info/sim_card_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../core/constants/constants.dart';
import '../../../core/services/api_service.dart';
import '../../vault/presentation/vault_screen.dart';

enum _Step {
  landing,
  terms,
  signInInfo,
  confirmInfo,
  recoveryPhone,
  recoveryEmail,
  otpVerify,
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Step _step = _Step.landing;

  final _api = ApiService.instance;
  final _sim = SimCardInfo();

  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  bool _isLoading = false;
  bool _termsAgreed = false;
  String _fullPhone = '';
  String _countryCode = 'DZ';
  String? _simPhone;
  String? _carrierName;

  // OTP resend timer
  Timer? _timer;
  int _countdown = 30;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _tryReadSim();
    _phoneCtrl.addListener(_stripLeadingZero);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl
      ..removeListener(_stripLeadingZero)
      ..dispose();
    _emailCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _stripLeadingZero() {
    final t = _phoneCtrl.text;
    if (t.startsWith('0')) {
      _phoneCtrl.value = _phoneCtrl.value.copyWith(
        text: t.substring(1),
        selection: TextSelection.collapsed(offset: t.length - 1),
      );
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _countdown = 30;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown == 0) {
        setState(() => _canResend = true);
        t.cancel();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _tryReadSim() async {
    try {
      final list = await _sim.getSimInfo();
      if (list != null && list.isNotEmpty) {
        if (mounted) {
          setState(() {
            _simPhone = list.first.number;
            _carrierName = list.first.carrierName;
          });
        }
      }
    } catch (_) {}
  }

  Future<String> _deviceId() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) return (await info.androidInfo).id;
      if (Platform.isIOS) return (await info.iosInfo).identifierForVendor ?? 'unknown';
    } catch (_) {}
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _goTo(_Step s) => setState(() => _step = s);

  void _toVault() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VaultScreen()),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.landing:      return _landing();
      case _Step.terms:        return _terms();
      case _Step.signInInfo:   return _signInInfo();
      case _Step.confirmInfo:  return _confirmInfo();
      case _Step.recoveryPhone: return _recoveryPhone();
      case _Step.recoveryEmail: return _recoveryEmail();
      case _Step.otpVerify:    return _otpView();
    }
  }

  // ── Common widgets ─────────────────────────────────────────────────────────

  Widget _nextBtn({required VoidCallback? onPressed, bool loading = false}) {
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
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
    );
  }

  Widget _backBtn(VoidCallback onPressed) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFF1F1F1),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back, color: Colors.black),
      ),
    );
  }

  // ── Steps ──────────────────────────────────────────────────────────────────

  Widget _landing() {
    return Padding(
      key: const ValueKey('landing'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeInDown(child: const Icon(Icons.security_rounded, size: 80, color: Colors.black)),
            const SizedBox(height: 48),
            FadeInUp(
              child: Text(
                '${AppConstants.appName} Vault',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
              ),
            ),
            const SizedBox(height: 12),
            FadeInUp(
              delay: const Duration(milliseconds: 100),
              child: Text(
                'Secure end-to-end encrypted storage for your data.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 80),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _goTo(_Step.terms),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Get Started',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            FadeInUp(
              delay: const Duration(milliseconds: 300),
              child: TextButton(
                onPressed: () => _goTo(_Step.recoveryPhone),
                child: const Text(
                  'Recover Account',
                  style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _terms() {
    return Column(
      key: const ValueKey('terms'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.landing),
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(height: 40),
                FadeInLeft(
                  child: Text(
                    'Terms and Privacy',
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
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.black54, height: 1.6, fontSize: 13),
                      children: [
                        const TextSpan(
                            text:
                                'By selecting "I agree", I confirm that I have read and accept the '),
                        TextSpan(
                            text: 'Terms of Use',
                            style: TextStyle(
                                color: Colors.blue[800], fontWeight: FontWeight.bold)),
                        const TextSpan(text: ' and the '),
                        TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                                color: Colors.blue[800], fontWeight: FontWeight.bold)),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _termsAgreed = !_termsAgreed),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Text('I agree',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
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
                  _backBtn(() => _goTo(_Step.landing)),
                  const Spacer(),
                  _nextBtn(
                    onPressed: _termsAgreed ? () => _goTo(_Step.signInInfo) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signInInfo() {
    return Column(
      key: const ValueKey('signInInfo'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.terms),
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(height: 40),
                FadeInLeft(
                  child: Text(
                    'Verify your phone number',
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
                    'SIBNA will detect your SIM card to verify your number quickly and securely.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.black54, height: 1.5, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              _backBtn(() => _goTo(_Step.terms)),
              const Spacer(),
              _nextBtn(onPressed: _onSignInNext, loading: _isLoading),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onSignInNext() async {
    setState(() => _isLoading = true);
    try {
      final status = await Permission.phone.request();
      if (status.isGranted) {
        await _tryReadSim();
        if (_simPhone != null) {
          _showSimSheet();
        } else {
          _goTo(_Step.recoveryPhone);
        }
      } else {
        _goTo(_Step.recoveryPhone);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSimSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              28, 36, 28, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share phone number with ${AppConstants.appName}?',
                style: Theme.of(ctx)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, fontSize: 19),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F4E8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8E0CC)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sim_card, size: 28, color: Colors.black),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _carrierName ?? 'Carrier',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _simPhone ?? '',
                            style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                                letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _goTo(_Step.recoveryPhone);
                    },
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.black, fontSize: 16)),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleSimVerify();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(160, 54),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Confirm',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSimVerify() async {
    if (_simPhone == null) return;
    setState(() => _isLoading = true);
    try {
      final devId = await _deviceId();
      final res = await _api.verifySim(
        simPhone: _simPhone,
        enteredPhone: _simPhone!,
        deviceId: devId,
      );
      if (res['status'] == 'match') {
        _fullPhone = res['phone'] as String? ?? _simPhone!;
        _goTo(_Step.confirmInfo);
      } else {
        _goTo(_Step.recoveryPhone);
      }
    } catch (e) {
      _showError('Verification error. Please try manually.');
      _goTo(_Step.recoveryPhone);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _confirmInfo() {
    return Column(
      key: const ValueKey('confirmInfo'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.signInInfo),
                    icon: const Icon(Icons.arrow_back)),
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
                Text('Phone number',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_fullPhone.isNotEmpty ? _fullPhone : (_simPhone ?? ''),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle,
                        color: Color(0xFF1A73E8), size: 18),
                  ],
                ),
                const SizedBox(height: 48),
                Text('First name',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 32),
                Text('Last name',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF6F6F6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Colors.black, width: 1.5)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              _backBtn(() => _goTo(_Step.signInInfo)),
              const Spacer(),
              _nextBtn(onPressed: _handleProfileSubmit, loading: _isLoading),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleProfileSubmit() async {
    final fn = _firstNameCtrl.text.trim();
    final ln = _lastNameCtrl.text.trim();
    if (fn.isEmpty || ln.isEmpty) {
      _showError('Please enter your first and last name.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final phone = _fullPhone.isNotEmpty ? _fullPhone : (_simPhone ?? '');
      final res = await _api.updateProfile(
          phone: phone, firstName: fn, lastName: ln);
      if (res['status'] == 'success') {
        _toVault();
      } else {
        _showError(res['message'] as String? ?? 'Error saving profile.');
      }
    } catch (e) {
      _showError('Network error. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _recoveryPhone() {
    return Column(
      key: const ValueKey('recoveryPhone'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.landing),
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(height: 20),
                FadeInLeft(
                  child: Text('Recovery',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 28)),
                ),
                const SizedBox(height: 12),
                FadeInLeft(
                  child: Text('Enter your registered phone number.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 16)),
                ),
                const SizedBox(height: 48),
                if (_simPhone != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                        backgroundColor: Color(0xFFF6F6F6),
                        child: Icon(Icons.sim_card, color: Colors.black)),
                    title: Text(_simPhone!,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_carrierName ?? 'Detected SIM'),
                    trailing: const Text('Use this',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.bold)),
                    onTap: () => setState(() {
                      _fullPhone = _simPhone!;
                      _step = _Step.recoveryEmail;
                    }),
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                ],
                IntlPhoneField(
                  controller: _phoneCtrl,
                  initialCountryCode: 'DZ',
                  invalidNumberMessage: 'Enter a valid phone number',
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    counterText: '',
                  ),
                  onChanged: (phone) {
                    _fullPhone = phone.completeNumber;
                    _countryCode = phone.countryISOCode;
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _fullPhone.isNotEmpty
                  ? () => _goTo(_Step.recoveryEmail)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Next'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recoveryEmail() {
    return Column(
      key: const ValueKey('recoveryEmail'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.recoveryPhone),
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(height: 20),
                FadeInLeft(
                  child: Text('Verify Email',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 26)),
                ),
                const SizedBox(height: 12),
                FadeInLeft(
                  child: Text(
                    'We will send a 6-digit code to your registered email.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 15, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'your@email.com',
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleRecoverySubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Send Code'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRecoverySubmit() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Please enter a valid email address.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _api.linkEmail(phone: _fullPhone, email: email);
      _goTo(_Step.otpVerify);
      _startTimer();
    } catch (e) {
      _showError('Could not send code. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _otpView() {
    return Column(
      key: const ValueKey('otp'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                    onPressed: () => _goTo(_Step.recoveryEmail),
                    icon: const Icon(Icons.arrow_back)),
                const SizedBox(height: 20),
                FadeInLeft(
                  child: Text('Enter Code',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 26)),
                ),
                const SizedBox(height: 12),
                FadeInLeft(
                  child: Text(
                    'Check your inbox at ${_emailCtrl.text}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 15, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 48),
                FadeInUp(
                  child: Pinput(
                    length: 6,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    defaultPinTheme: PinTheme(
                      width: 56,
                      height: 64,
                      textStyle: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    focusedPinTheme: PinTheme(
                      width: 56,
                      height: 64,
                      textStyle: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F6F6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                    ),
                    onCompleted: _handleOtpVerify,
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: _canResend
                      ? TextButton(
                          onPressed: _isLoading ? null : _resendCode,
                          child: const Text(
                            'Resend Code',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline),
                          ),
                        )
                      : Text(
                          'Resend code in ${_countdown}s',
                          style: const TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                        child: CircularProgressIndicator(color: Colors.black)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;
    setState(() => _isLoading = true);
    try {
      await _api.linkEmail(phone: _fullPhone, email: _emailCtrl.text.trim());
      _startTimer();
      _showSuccess('Verification code sent.');
    } catch (e) {
      _showError('Could not send code. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOtpVerify(String pin) async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.verifyOtp(phone: _fullPhone, otp: pin);
      if (res['status'] == 'success' || res['status'] == 'recovery_success') {
        _toVault();
      } else {
        _showError(res['message'] as String? ?? 'Invalid code. Please try again.');
      }
    } catch (e) {
      _showError('Network error. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
