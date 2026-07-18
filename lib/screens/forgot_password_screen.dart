import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  bool _showOtpStep = false;
  bool _showResetStep = false;
  bool _canResendOtp = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String _error = '';
  String _success = '';
  String _resetToken = '';
  DateTime? _otpSentAt;
  Timer? _resendTimer;
  int _remainingSeconds = 0;

  static const int _resendCooldownSeconds = 60;

  static const Color _primary = Color(0xFF052269);
  static const Color _primaryLight = Color(0xFF3B63D9);
  static const Color _textDark = Color(0xFF0A0E27);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _surface = Color(0xFFF6F8FC);
  static const Color _border = Color(0xFFE4E8F1);

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otpValue => _otpControllers.map((c) => c.text).join();

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
    if (_otpFocusNodes.isNotEmpty) {
      FocusScope.of(context).requestFocus(_otpFocusNodes.first);
    }
  }

  Future<void> _sendOtp() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    if (email.isEmpty || !AuthValidators.isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });

    final result = await _authService.sendForgotOtp(email);
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success) {
        _showOtpStep = true;
        _showResetStep = false;
        _otpSentAt = DateTime.now();
        _canResendOtp = false;
        _success = 'A verification code has been sent to your email.';
        _clearOtpFields();
        _startResendCooldown();
      } else {
        _error = result.message.isNotEmpty
            ? result.message
            : 'Could not send OTP.';
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;
    final otp = _otpValue.trim();
    if (otp.length < 6) {
      setState(() => _error = 'Enter the complete 6-digit OTP.');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });

    final result = await _authService.verifyForgotOtp(
      email: _emailController.text.trim(),
      otp: otp,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _resetToken = result.data!.resetToken;
        _showResetStep = true;
        _showOtpStep = false;
        _resendTimer?.cancel();
        _success = 'OTP verified successfully.';
      } else {
        _error = result.message.isNotEmpty
            ? result.message
            : 'Invalid OTP. Please try again.';
      }
    });
  }

  Future<void> _resetPassword() async {
    if (_loading) return;
    final passwordError = AuthValidators.passwordError(
      _newPasswordController.text,
    );
    if (passwordError.isNotEmpty) {
      setState(() => _error = passwordError);
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });

    final result = await _authService.resetPassword(
      resetToken: _resetToken,
      newPassword: _newPasswordController.text,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success) {
        _success = 'Password reset successfully! Please sign in.';
        _showResetStep = false;
        _showOtpStep = false;
        _emailController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        _error = result.message.isNotEmpty ? result.message : 'Reset failed.';
      }
    });

    if (result.success && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _canResendOtp = false;
    _remainingSeconds = _resendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed =
          DateTime.now().difference(_otpSentAt ?? DateTime.now()).inSeconds;
      final remaining = (_resendCooldownSeconds - elapsed).clamp(0, _resendCooldownSeconds);
      setState(() => _remainingSeconds = remaining);
      if (remaining <= 0) {
        setState(() => _canResendOtp = true);
        timer.cancel();
      }
    });
  }

  void _goBack() {
    setState(() {
      _error = '';
      _success = '';
      if (_showResetStep) {
        _showResetStep = false;
        _showOtpStep = true;
      } else if (_showOtpStep) {
        _showOtpStep = false;
        _resendTimer?.cancel();
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _iconBadge(
                      _showResetStep
                          ? Icons.lock_reset_rounded
                          : _showOtpStep
                              ? Icons.vpn_key_rounded
                              : Icons.lock_outline_rounded,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _showResetStep
                          ? 'Set New Password'
                          : _showOtpStep
                              ? 'Enter OTP'
                              : 'Forgot Password',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _showResetStep
                          ? 'Create a new password for your account.'
                          : _showOtpStep
                              ? 'OTP sent to'
                              : "Enter your registered email and we'll send a reset OTP.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textMuted,
                        height: 1.4,
                      ),
                    ),
                    if (_showOtpStep) ...[
                      const SizedBox(height: 2),
                      Text(
                        _emailController.text.trim(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _primaryLight,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_error.isNotEmpty) ...[
                      _messageBox(_error, isError: true),
                      const SizedBox(height: 14),
                    ],
                    if (_success.isNotEmpty) ...[
                      _messageBox(_success, isError: false),
                      const SizedBox(height: 14),
                    ],
                    if (!_showOtpStep && !_showResetStep) _buildEmailStep(),
                    if (_showOtpStep) _buildOtpStep(),
                    if (_showResetStep) _buildResetStep(),
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: _loading ? null : _goBack,
                      icon: const Icon(Icons.arrow_back_rounded,
                          size: 16, color: _textMuted),
                      label: const Text(
                        'Back',
                        style: TextStyle(
                          color: _textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(IconData icon) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryLight, _primary],
        ),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 32),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Email Address'),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration(
            Icons.email_outlined,
            'Your registered email',
          ),
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Send Reset OTP',
          onPressed: _loading ? null : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final resendReady = _canResendOtp || _otpSentAt == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) => _otpBox(i)),
        ),
        const SizedBox(height: 16),
        if (!resendReady)
          Text.rich(
            TextSpan(
              text: "Didn't receive it? ",
              style: const TextStyle(fontSize: 13, color: _textMuted),
              children: [
                TextSpan(
                  text: 'Resend in ${_remainingSeconds}s',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
              ],
            ),
          )
        else
          GestureDetector(
            onTap: _loading ? null : _sendOtp,
            child: Text.rich(
              TextSpan(
                text: "Didn't receive it? ",
                style: const TextStyle(fontSize: 13, color: _textMuted),
                children: const [
                  TextSpan(
                    text: 'Resend OTP',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _primaryLight,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Verify OTP',
          onPressed: _loading ? null : _verifyOtp,
        ),
      ],
    );
  }

  Widget _otpBox(int index) {
    return Padding(
      padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
      child: SizedBox(
        width: 46,
        height: 54,
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textDark,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: _surface,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
          ),
          onChanged: (value) {
            if (value.isNotEmpty && index < 5) {
              FocusScope.of(context).requestFocus(_otpFocusNodes[index + 1]);
            } else if (value.isEmpty && index > 0) {
              FocusScope.of(context).requestFocus(_otpFocusNodes[index - 1]);
            }
            setState(() {});
          },
        ),
      ),
    );
  }

  Widget _buildResetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('New Password'),
        const SizedBox(height: 8),
        TextField(
          controller: _newPasswordController,
          obscureText: _obscureNewPassword,
          decoration: _inputDecoration(
            Icons.lock_outline,
            'Enter new password',
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNewPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _textMuted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscureNewPassword = !_obscureNewPassword),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _label('Confirm Password'),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: _inputDecoration(
            Icons.lock_outline,
            'Confirm new password',
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _textMuted,
                size: 20,
              ),
              onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Reset Password',
          onPressed: _loading ? null : _resetPassword,
        ),
      ],
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onPressed}) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: disabled
                ? [Colors.grey.shade400, Colors.grey.shade400]
                : [_primaryLight, _primary],
          ),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: _primary.withOpacity(0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        letterSpacing: 0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF374151),
        ),
      );

  InputDecoration _inputDecoration(IconData icon, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
      prefixIcon: Icon(icon, color: _textMuted, size: 20),
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }

  Widget _messageBox(String message, {required bool isError}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? const Color(0xFFFECACA) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: isError ? const Color(0xFFDC2626) : const Color(0xFF047857),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isError ? const Color(0xFFDC2626) : const Color(0xFF047857),
              ),
            ),
          ),
        ],
      ),
    );
  }
}