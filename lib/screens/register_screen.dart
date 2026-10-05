import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../widgets/apple_sign_in_button.dart';
import '../models/api_result.dart';
import '../models/auth_response.dart';
import '../widgets/google_sign_in_web_stub.dart'
    if (dart.library.js_interop) 'package:google_sign_in_web/web_only.dart'
    as web_only;
import '../models/register_model.dart';
import '../services/auth_repository.dart';
import '../services/auth_validators.dart';
import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/consent_checkboxes.dart';
import '../widgets/geo_phone_controller.dart';
import '../widgets/geo_phone_fields.dart';
import 'main_screen.dart';
import 'social_signup_completion_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// Email sign-up. Same fields, order and rules as the web registration form:
/// Full Name, Email, Country, State / Province, City, Phone (country code
/// synced with Country), Password, then the three consents. A brand-new
/// Google / Apple user is sent on to [SocialSignupCompletionScreen].
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const int _stepForm = 0;
  static const int _stepOtp = 1;

  int _currentStep = _stepForm;
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  String _error = '';

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Country / State / City / Phone (and their sync), and the 3 consents.
  final _geo = GeoPhoneController();
  final _consents = ConsentController();

  // OTP
  final _otpController = TextEditingController();
  int _otpTimer = 0;

  final _authRepository = AuthRepository();
  final _authService = AuthService();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;
  Timer? _googleWebTimeoutTimer;
  Timer? _otpCountdownTimer;

  @override
  void initState() {
    super.initState();
    // Country list + India's states, so the pickers are ready by the time the
    // user reaches them.
    _geo.init();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await GoogleSignIn.instance.initialize();
        _googleAuthSubscription = GoogleSignIn.instance.authenticationEvents
            .listen(
              (event) async {
                if (event is GoogleSignInAuthenticationEventSignIn) {
                  await _handleGoogleSignedIn(event.user);
                }
              },
              onError: (Object error) {
                _googleWebTimeoutTimer?.cancel();
                if (!mounted) return;
                setState(() {
                  _googleLoading = false;
                  _error = 'Google Sign-In failed. Please try again.';
                });
              },
            );
      });
    }
  }

  @override
  void dispose() {
    _googleAuthSubscription?.cancel();
    _googleWebTimeoutTimer?.cancel();
    _otpCountdownTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _geo.dispose();
    _consents.dispose();
    super.dispose();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────
  void _startTimer() {
    // Cancel any prior chain before starting a new one — without this, a
    // submit → back-to-form → resubmit cycle could leave two countdowns
    // running concurrently, halving the intended 60s cooldown.
    _otpCountdownTimer?.cancel();
    setState(() => _otpTimer = 60);
    _otpCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _otpTimer <= 1) {
        timer.cancel();
        if (mounted) setState(() => _otpTimer = 0);
        return;
      }
      setState(() => _otpTimer--);
    });
  }

  // ── Submit registration → send OTP ────────────────────────────────────────
  Future<void> _handleRegisterSubmit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (!_consents.allAccepted) {
      _setError(kConsentError);
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authRepository.sendRegisterOtp(
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      mobile: _geo.fullNumber,
      privacyConsent: _consents.privacy,
      hipaaConsent: _consents.hipaa,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      _startTimer();
      setState(() => _currentStep = _stepOtp);
      showAuthSnackBar(context, 'OTP sent to your email');
    } else {
      _setError(result.message);
    }
  }

  // ── OTP submit → create account ───────────────────────────────────────────
  Future<void> _handleOtpSubmit() async {
    // Also guards against the auto-submit-on-6th-digit path (OtpTextField's
    // onChanged) firing a second time while a tap on the submit button is
    // already in flight.
    if (_loading) return;
    final otp = _otpController.text.trim();
    if (otp.length < 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _setError('Enter the complete 6-digit OTP');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final formData = RegisterFormData(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      mobile: _geo.fullNumber,
      country: _geo.countryName,
      state: _geo.state,
      city: _geo.city,
      privacyConsent: _consents.privacy,
      hipaaConsent: _consents.hipaa,
    );

    final request = formData.toRegisterRequest(otp);
    final ApiResult<AuthResponse> result;
    try {
      result = await _authRepository.register(request);
    } catch (_) {
      // AuthRepository.register() saves the session (secure storage) after
      // a successful API call — if that save throws (e.g. secure storage
      // unavailable on this device), the account already exists server-side
      // but we can't leave the button spinning forever with no way out.
      if (!mounted) return;
      setState(() => _loading = false);
      _setError(
        'Your account was created, but we could not sign you in automatically. Please log in.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      showAuthSnackBar(context, 'Registration successful!');
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } else {
      _setError(result.message);
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _handleResendOtp() async {
    // The 60s cooldown (_otpTimer) throttles repeat resends once _startTimer
    // has run, but there's a window right after a tap, before that timer
    // starts, where a fast double-tap could still fire this twice.
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await _authRepository.sendRegisterOtp(
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      mobile: _geo.fullNumber,
      privacyConsent: _consents.privacy,
      hipaaConsent: _consents.hipaa,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success) {
      _startTimer();
      showAuthSnackBar(context, 'OTP resent');
    } else {
      _setError(result.message);
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

  // ── Google / Apple ────────────────────────────────────────────────────────
  Future<void> _handleGoogleSignUp() async {
    if (_googleLoading) return;
    if (kIsWeb) {
      setState(() {
        _googleLoading = true;
        _error = '';
      });
      // See login_screen.dart's identical timeout: cancelling the web popup
      // may not emit any authenticationEvents-stream event at all, which
      // previously left this button stuck on its loading spinner forever.
      _googleWebTimeoutTimer?.cancel();
      _googleWebTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (!mounted || !_googleLoading) return;
        setState(() {
          _googleLoading = false;
          _error =
              'Google Sign-In was cancelled or timed out. Please try again.';
        });
      });
      return;
    }

    setState(() {
      _googleLoading = true;
      _error = '';
    });

    final result = await _authService.googleLogin();
    if (!mounted) return;
    setState(() {
      _googleLoading = false;
      _error = result.success ? '' : result.message;
    });

    if (!result.success) return;
    if (result.isNewUser) {
      await SocialSignupCompletionScreen.open(
        context,
        SocialSignupSession(
          name: result.googleName,
          email: result.googleEmail,
          googleAccessToken: result.accessToken,
        ),
      );
      return;
    }

    if (result.authResponse == null) return;
    try {
      await _authService.saveSession(result.authResponse!);
    } catch (_) {
      // The Google account was already registered server-side — only the
      // local session save failed (e.g. secure storage unavailable), so
      // don't leave the user staring at a button with no feedback.
      if (!mounted) return;
      setState(() {
        _error =
            'Your account was created, but we could not sign you in automatically. Please log in.';
      });
      return;
    }
    if (!mounted) return;
    showAuthSnackBar(context, 'Registration Successful');
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  Future<void> _handleAppleSignUp() async {
    if (_appleLoading || _loading || _googleLoading) return;
    setState(() {
      _appleLoading = true;
      _error = '';
    });
    final result = await _authService.appleLogin();
    if (!mounted) return;
    setState(() {
      _appleLoading = false;
      _error = result.success || result.cancelled ? '' : result.message;
    });

    if (!result.success) return;

    if (result.isNewUser) {
      await SocialSignupCompletionScreen.open(
        context,
        SocialSignupSession(
          name: result.name,
          email: result.email,
          appleCredential: result.credential,
        ),
      );
      return;
    }

    if (result.authResponse == null) return;
    await _authService.saveSession(result.authResponse!);
    if (!mounted) return;
    showAuthSnackBar(context, 'Registration Successful');
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  Future<void> _handleGoogleSignedIn(GoogleSignInAccount account) async {
    _googleWebTimeoutTimer?.cancel();
    try {
      const scopes = ['openid', 'profile', 'email'];
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      final result = await _authService.googleLoginWithAccessToken(
        authorization.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _error = result.success ? '' : result.message;
      });

      if (!result.success) return;
      if (result.isNewUser) {
        await SocialSignupCompletionScreen.open(
          context,
          SocialSignupSession(
            name: result.googleName,
            email: result.googleEmail,
            googleAccessToken: result.accessToken,
          ),
        );
        return;
      }

      if (result.authResponse == null) return;
      await _authService.saveSession(result.authResponse!);
      if (!mounted) return;
      showAuthSnackBar(context, 'Registration Successful');
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _error = 'Google Sign-In failed.';
      });
    }
  }

  // ── Input decoration ──────────────────────────────────────────────────────
  InputDecoration _dec({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xff1a3a5c), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xfff9fafb),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.09)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xff1a3a5c), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xff1a3a5c),
        letterSpacing: 0.3,
      ),
    ),
  );

  // ── Error box ─────────────────────────────────────────────────────────────
  Widget _errorBox(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.red.shade100),
    ),
    child: Text(
      msg,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.red.shade700,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
  );

  // ── Password strength checklist ───────────────────────────────────────────
  Widget _buildPasswordChecklist() {
    final pw = _passwordController.text;
    if (pw.isEmpty) {
      return Text(
        'Password must have: 8+ chars, uppercase, lowercase, number & symbol',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      );
    }
    final checks = [
      (pw.length >= 8, 'At least 8 characters'),
      (RegExp(r'[A-Z]').hasMatch(pw), 'One uppercase letter'),
      (RegExp(r'[a-z]').hasMatch(pw), 'One lowercase letter'),
      (RegExp(r'[0-9]').hasMatch(pw), 'One number'),
      (
        RegExp(r'[^A-Za-z0-9]').hasMatch(pw),
        'One special character (!@#\$...)',
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: checks.map((c) {
        final met = c.$1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              met ? Icons.check_circle : Icons.cancel,
              size: 13,
              color: met ? Colors.green.shade600 : Colors.red.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              c.$2,
              style: TextStyle(
                fontSize: 11,
                color: met ? Colors.green.shade600 : Colors.red.shade400,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1 — Registration form
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Personal Information ────────────────────────────────────────
          _section('Personal Information'),

          // Full Name
          TextFormField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: _dec(label: 'Full Name', icon: Icons.person_outline),
            onChanged: (v) {
              final cleaned = v.replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
              if (cleaned != v) {
                _nameController.value = _nameController.value.copyWith(
                  text: cleaned,
                  selection: TextSelection.collapsed(offset: cleaned.length),
                );
              }
            },
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Enter your full name';
              if (val.length < 2) return 'Please enter your full name';
              if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val)) {
                return 'Name must contain only letters';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Email
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: _dec(label: 'Email Address', icon: Icons.mail_outline),
            validator: (v) {
              if ((v?.trim() ?? '').isEmpty) return 'Enter your email address';
              if (!AuthValidators.isValidEmail(v!)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          // ── Location & Contact: Country, State, City, Phone ─────────────
          _section('Location & Contact'),
          GeoPhoneFields(controller: _geo),
          const SizedBox(height: 24),

          // ── Security ───────────────────────────────────────────────────
          _section('Security'),

          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: _dec(
              label: 'Password',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              final err = AuthValidators.passwordError(v ?? '');
              return err.isEmpty ? null : err;
            },
          ),
          const SizedBox(height: 8),
          _buildPasswordChecklist(),
          const SizedBox(height: 24),

          // ── Consent ────────────────────────────────────────────────────
          _section('Consent'),
          ConsentCheckboxes(controller: _consents),

          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            _errorBox(_error),
          ],
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _handleRegisterSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff1a3a5c),
                disabledBackgroundColor: const Color(
                  0xff1a3a5c,
                ).withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Sign Up',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          _googleSignupButton(),
          if (AuthService.isAppleSignInSupported) ...[
            const SizedBox(height: 12),
            AppleSignInButton(
              onPressed: _handleAppleSignUp,
              loading: _appleLoading,
              disabled: _loading || _googleLoading,
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                'Already have an account?',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Sign In',
                  style: TextStyle(
                    color: Color(0xff1a3a5c),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _googleSignupButton() {
    if (kIsWeb) {
      return SizedBox(
        width: double.infinity,
        height: 54,
        child: web_only.renderButton(),
      );
    }

    final disabled = _loading || _googleLoading || _appleLoading;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: disabled ? null : _handleGoogleSignUp,
        icon: _googleLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.g_mobiledata, size: 22),
        label: Text(
          _googleLoading ? 'Connecting...' : 'Continue with Google',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xff1a3a5c),
          side: const BorderSide(color: Color(0xffd1d5db)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — OTP Verification
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOtpStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _currentStep = _stepForm;
                      _error = '';
                    }),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xff1a3a5c),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Verify Your Email',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.email_outlined,
                  color: Color(0xff1a3a5c),
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  children: [
                    const TextSpan(
                      text: 'We sent a 6-digit security code to\n',
                    ),
                    TextSpan(
                      text: _emailController.text,
                      style: const TextStyle(
                        color: Color(0xff2563eb),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OtpTextField(
                controller: _otpController,
                onChanged: (v) {
                  if (v.length == 6) _handleOtpSubmit();
                },
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                _errorBox(_error),
              ],
              const SizedBox(height: 18),
              _otpTimer > 0
                  ? Text(
                      'Resend in ${_otpTimer}s',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Didn't receive it? ",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        GestureDetector(
                          onTap: _loading ? null : _handleResendOtp,
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(
                              color: Color(0xff2563eb),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleOtpSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1a3a5c),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify & Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: _currentStep == _stepForm ? 'Create Account' : 'Verify Email',
      subtitle: _currentStep == _stepForm
          ? 'Join Humancare Connect and take charge of your health'
          : 'Enter the OTP code',
      child: _currentStep == _stepForm ? _buildForm() : _buildOtpStep(),
    );
  }
}
