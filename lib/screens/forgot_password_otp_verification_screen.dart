import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'auth_widgets.dart';
import 'reset_password_screen.dart';

class ForgotPasswordOtpVerificationScreen extends StatefulWidget {
  const ForgotPasswordOtpVerificationScreen({
    super.key,
    required this.email,
  });

  final String email;

  @override
  State<ForgotPasswordOtpVerificationScreen> createState() =>
      _ForgotPasswordOtpVerificationScreenState();
}

class _ForgotPasswordOtpVerificationScreenState
    extends State<ForgotPasswordOtpVerificationScreen> {
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

  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.verifyForgotOtp(
      email: widget.email,
      otp: _otpController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    final resetToken = result.data?.resetToken ?? '';
    if (!result.success || resetToken.isEmpty) return;

    _timer?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(resetToken: resetToken),
      ),
    );
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = '';
    });

    final result = await _authService.sendForgotOtp(widget.email);

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
      title: 'Enter OTP',
      subtitle: 'OTP sent to ${widget.email}',
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
              label: 'Verify OTP',
              loadingLabel: 'Verifying...',
              loading: _loading,
              onPressed: _verifyOtp,
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
