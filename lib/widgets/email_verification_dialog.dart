import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_design_system.dart';
import '../services/auth_service.dart';

/// Verifies that the account owner controls their **current** email address
/// before a pending email change is written to the profile.
///
/// The backend has no dedicated "verify email change" endpoint and must not be
/// modified, so this reuses the existing password-reset OTP flow via
/// [AuthService.sendEmailChangeOtp] / [AuthService.verifyEmailChangeOtp]. A
/// code is sent to [currentEmail]; the change is only allowed once the user
/// enters it correctly.
///
/// Returns `true` when verification succeeded, `false` when the user dismissed
/// the dialog without verifying.
Future<bool> showEmailVerificationDialog({
  required BuildContext context,
  required String currentEmail,
  required String newEmail,
  AuthService? authService,
}) async {
  final verified = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmailVerificationDialog(
      currentEmail: currentEmail,
      newEmail: newEmail,
      authService: authService ?? AuthService(),
    ),
  );
  return verified ?? false;
}

class _EmailVerificationDialog extends StatefulWidget {
  const _EmailVerificationDialog({
    required this.currentEmail,
    required this.newEmail,
    required this.authService,
  });

  final String currentEmail;
  final String newEmail;
  final AuthService authService;

  @override
  State<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 60;

  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  bool _sending = false;
  bool _verifying = false;
  bool _canResend = false;
  String _error = '';
  String _info = '';

  DateTime? _otpSentAt;
  Timer? _resendTimer;
  int _remainingSeconds = 0;

  bool get _busy => _sending || _verifying;
  String get _otpValue => _otpControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    // Send the first code automatically as soon as the dialog opens — the
    // user has already committed to the change by tapping Save.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOtp(initial: true));
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
    if (mounted && _otpFocusNodes.isNotEmpty) {
      FocusScope.of(context).requestFocus(_otpFocusNodes.first);
    }
  }

  Future<void> _sendOtp({bool initial = false}) async {
    if (_busy) return;
    if (!initial && !_canResend) return;

    setState(() {
      _sending = true;
      _error = '';
      _info = '';
    });

    final result =
        await widget.authService.sendEmailChangeOtp(widget.currentEmail);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (result.success) {
        _otpSentAt = DateTime.now();
        _canResend = false;
        _info = initial
            ? 'We sent a 6-digit code to your current email address.'
            : 'A new code has been sent to your current email address.';
        _clearOtpFields();
        _startResendCooldown();
      } else {
        _error = result.message.isNotEmpty
            ? result.message
            : 'Could not send the verification code. Please try again.';
        // Allow an immediate retry when the send itself failed.
        _canResend = true;
        _resendTimer?.cancel();
        _remainingSeconds = 0;
      }
    });
  }

  Future<void> _verifyOtp() async {
    if (_busy) return;

    final otp = _otpValue.trim();
    if (otp.length < _otpLength) {
      setState(() => _error = 'Enter the complete 6-digit code.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = '';
      _info = '';
    });

    final result = await widget.authService.verifyEmailChangeOtp(
      email: widget.currentEmail,
      otp: otp,
    );
    if (!mounted) return;

    if (result.success) {
      _resendTimer?.cancel();
      setState(() {
        _verifying = false;
        _info = 'Verified. Updating your email…';
      });
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _verifying = false;
      _error = result.message.isNotEmpty
          ? result.message
          : 'Invalid or expired code. Please try again.';
      _clearOtpFields();
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    _canResend = false;
    _remainingSeconds = _resendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed =
          DateTime.now().difference(_otpSentAt ?? DateTime.now()).inSeconds;
      final remaining = (_resendCooldownSeconds - elapsed)
          .clamp(0, _resendCooldownSeconds)
          .toInt();
      setState(() => _remainingSeconds = remaining);
      if (remaining <= 0) {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.mark_email_read_outlined,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Verify your email',
                        style: AppType.display(size: 18)),
                  ),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                    splashRadius: 20,
                    tooltip: 'Cancel',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: AppType.body(size: 13.5, height: 1.45)
                      .copyWith(color: AppColors.textSecondary),
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code sent to '),
                    TextSpan(
                      text: widget.currentEmail,
                      style: AppType.body(size: 13.5, weight: FontWeight.w700)
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: ' to confirm changing your email to '),
                    TextSpan(
                      text: widget.newEmail,
                      style: AppType.body(size: 13.5, weight: FontWeight.w700)
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_error.isNotEmpty) ...[
                _MessageBox(message: _error, isError: true),
                const SizedBox(height: 14),
              ] else if (_info.isNotEmpty) ...[
                _MessageBox(message: _info, isError: false),
                const SizedBox(height: 14),
              ],
              _OtpRow(
                controllers: _otpControllers,
                focusNodes: _otpFocusNodes,
                enabled: !_busy,
                onChanged: () => setState(() {}),
                onCompleted: _verifyOtp,
              ),
              const SizedBox(height: 16),
              _ResendRow(
                sending: _sending,
                canResend: _canResend,
                remainingSeconds: _remainingSeconds,
                onResend: _busy ? null : () => _sendOtp(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_busy || _otpValue.length < _otpLength)
                          ? null
                          : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.4),
                        disabledForegroundColor: Colors.white70,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Verify & Update'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── OTP input row ────────────────────────────────────────────────────────────

class _OtpRow extends StatelessWidget {
  const _OtpRow({
    required this.controllers,
    required this.focusNodes,
    required this.enabled,
    required this.onChanged,
    required this.onCompleted,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    const count = 6;
    const gap = 8.0;

    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == count - 1 ? 0.0 : gap),
            child: SizedBox(
              height: 54,
              child: TextField(
                  controller: controllers[i],
                  focusNode: focusNodes[i],
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  style: AppType.body(size: 20, weight: FontWeight.w700)
                      .copyWith(color: AppColors.textPrimary),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (value) {
                    if (value.length > 1) {
                      // Handle a pasted / autofilled multi-digit string.
                      final digits =
                          value.replaceAll(RegExp(r'\D'), '').split('');
                      for (var j = 0; j < count; j++) {
                        controllers[j].text =
                            j < digits.length ? digits[j] : '';
                      }
                      final next =
                          digits.length >= count ? count - 1 : digits.length;
                      FocusScope.of(context).requestFocus(focusNodes[next]);
                    } else if (value.isNotEmpty && i < count - 1) {
                      FocusScope.of(context).requestFocus(focusNodes[i + 1]);
                    } else if (value.isEmpty && i > 0) {
                      FocusScope.of(context).requestFocus(focusNodes[i - 1]);
                    }
                    onChanged();
                    if (controllers.map((c) => c.text).join().length == count) {
                      FocusScope.of(context).unfocus();
                      onCompleted();
                    }
                  },
                ),
              ),
            ),
          );
        }),
      );
  }
}

// ── Resend row ───────────────────────────────────────────────────────────────

class _ResendRow extends StatelessWidget {
  const _ResendRow({
    required this.sending,
    required this.canResend,
    required this.remainingSeconds,
    required this.onResend,
  });

  final bool sending;
  final bool canResend;
  final int remainingSeconds;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    if (sending) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.6, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Text('Sending code…',
              style: AppType.body(size: 13)
                  .copyWith(color: AppColors.textSecondary)),
        ],
      );
    }

    if (!canResend) {
      return Text.rich(
        TextSpan(
          text: "Didn't get the code? ",
          style: AppType.body(size: 13).copyWith(color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: 'Resend in ${remainingSeconds}s',
              style: AppType.body(size: 13, weight: FontWeight.w700)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: onResend,
        child: Text.rich(
          TextSpan(
            text: "Didn't get the code? ",
            style:
                AppType.body(size: 13).copyWith(color: AppColors.textSecondary),
            children: [
              TextSpan(
                text: 'Resend code',
                style: AppType.body(size: 13, weight: FontWeight.w700).copyWith(
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Inline status message ────────────────────────────────────────────────────

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final fg = isError ? const Color(0xFFDC2626) : const Color(0xFF047857);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppType.body(size: 13, weight: FontWeight.w600)
                  .copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
