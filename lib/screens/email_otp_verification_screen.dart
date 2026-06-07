import 'dart:async';

import 'package:flutter/material.dart';

import '../home_page.dart';
import '../services/auth_service.dart';
import 'auth_widgets.dart';

class EmailOtpVerificationScreen extends StatefulWidget {
  const EmailOtpVerificationScreen({
    super.key,
    required this.name,
    required this.email,
    required this.mobile,
    required this.dob,
    required this.gender,
    required this.country,
    required this.password,
    required this.privacyConsent,
    required this.hipaaConsent,
  });

  final String name;
  final String email;
  final String mobile;
  final String dob;
  final String gender;
  final String country;
  final String password;
  final bool privacyConsent;
  final bool hipaaConsent;

  @override
  State<EmailOtpVerificationScreen> createState() =>
      _EmailOtpVerificationScreenState();
}

class _EmailOtpVerificationScreenState
    extends State<EmailOtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _authService = AuthService();

  Timer? _timer;
  int _seconds = 60;
  bool _loading = false;
  bool _resending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _seconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) {
        timer.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds -= 1);
      }
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.register(
      name: widget.name,
      email: widget.email,
      mobile: widget.mobile,
      dob: widget.dob,
      gender: widget.gender,
      country: widget.country,
      password: widget.password,
      privacyConsent: widget.privacyConsent,
      hipaaConsent: widget.hipaaConsent,
      otp: _otpController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (!result.success || result.data == null) return;

    _timer?.cancel();
    await _authService.saveSession(result.data!);
    if (!mounted) return;

    showAuthSnackBar(context, 'Registration successful.');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (_) => false,
    );
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = '';
    });

    final result = await _authService.sendRegisterOtp(
      email: widget.email,
      password: widget.password,
      dob: widget.dob,
      privacyConsent: widget.privacyConsent,
      hipaaConsent: widget.hipaaConsent,
    );

    if (!mounted) return;

    setState(() {
      _resending = false;
      _error = result.success ? '' : result.message;
    });

    if (result.success) {
      showAuthSnackBar(context, 'OTP resent successfully.');
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Verify Your Email',
      subtitle: 'We sent a 6-digit OTP to ${widget.email}',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            OtpTextField(
              controller: _otpController,
              onChanged: (_) => setState(() => _error = ''),
            ),
            const SizedBox(height: 12),
            _seconds > 0
                ? Text('Resend in ${_seconds}s')
                : TextButton(
                    onPressed: _resending || _loading ? null : _resend,
                    child: Text(_resending ? 'Resending...' : 'Resend OTP'),
                  ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            AuthButton(
              label: 'Verify & Create Account',
              loadingLabel: 'Verifying...',
              loading: _loading,
              onPressed: _verify,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
