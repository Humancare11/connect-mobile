import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/api_result.dart';
import '../models/auth_response.dart';
import '../models/location_model.dart';
import '../widgets/google_sign_in_web_stub.dart'
    if (dart.library.js_interop) 'package:google_sign_in_web/web_only.dart'
    as web_only;
import '../models/register_model.dart';
import '../services/auth_repository.dart';
import '../services/auth_validators.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../utils/dial_codes.dart';
import '../widgets/auth_widgets.dart';
import 'main_screen.dart';

String _getDobError(String dob) {
  if (dob.isEmpty) return 'Select Date of Birth';
  final parsed = DateTime.tryParse(dob);
  if (parsed == null) return 'Enter a valid Date of Birth';
  if (parsed.isAfter(DateTime.now())) {
    return 'Date of Birth cannot be in the future';
  }
  if (parsed.isBefore(DateTime(1900))) {
    return 'Date of Birth must be in or after 1900';
  }
  return '';
}

const List<String> _genders = ['Male', 'Female', 'Other', 'Prefer Not to Say'];

String _normalizeLocationName(String value) {
  const diacritics = <String, String>{
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'Ā': 'A',
    'Ă': 'A',
    'Ą': 'A',
    'Ǎ': 'A',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'ă': 'a',
    'ą': 'a',
    'ǎ': 'a',
    'Ç': 'C',
    'Ć': 'C',
    'Č': 'C',
    'Ĉ': 'C',
    'Ċ': 'C',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ĉ': 'c',
    'ċ': 'c',
    'Ð': 'D',
    'Ď': 'D',
    'Đ': 'D',
    'ð': 'd',
    'ď': 'd',
    'đ': 'd',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Ē': 'E',
    'Ĕ': 'E',
    'Ė': 'E',
    'Ę': 'E',
    'Ě': 'E',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ĕ': 'e',
    'ė': 'e',
    'ę': 'e',
    'ě': 'e',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'Ĩ': 'I',
    'Ī': 'I',
    'Ĭ': 'I',
    'Į': 'I',
    'İ': 'I',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ĩ': 'i',
    'ī': 'i',
    'ĭ': 'i',
    'į': 'i',
    'ı': 'i',
    'Ñ': 'N',
    'Ń': 'N',
    'Ň': 'N',
    'Ņ': 'N',
    'ñ': 'n',
    'ń': 'n',
    'ň': 'n',
    'ņ': 'n',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'Ø': 'O',
    'Ō': 'O',
    'Ŏ': 'O',
    'Ő': 'O',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'ō': 'o',
    'ŏ': 'o',
    'ő': 'o',
    'Ś': 'S',
    'Š': 'S',
    'Ş': 'S',
    'Ŝ': 'S',
    'Ș': 'S',
    'ś': 's',
    'š': 's',
    'ş': 's',
    'ŝ': 's',
    'ș': 's',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'Ũ': 'U',
    'Ū': 'U',
    'Ŭ': 'U',
    'Ů': 'U',
    'Ű': 'U',
    'Ų': 'U',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ũ': 'u',
    'ū': 'u',
    'ŭ': 'u',
    'ů': 'u',
    'ű': 'u',
    'ų': 'u',
    'Ý': 'Y',
    'Ÿ': 'Y',
    'ý': 'y',
    'ÿ': 'y',
    'Ž': 'Z',
    'Ź': 'Z',
    'Ż': 'Z',
    'ž': 'z',
    'ź': 'z',
    'ż': 'z',
  };

  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    if (rune >= 0x1AB0 && rune <= 0x1AFF) continue;
    if (rune >= 0x1DC0 && rune <= 0x1DFF) continue;
    if (rune >= 0x20D0 && rune <= 0x20FF) continue;
    if (rune >= 0xFE20 && rune <= 0xFE2F) continue;

    final char = String.fromCharCode(rune);
    buffer.write(diacritics[char] ?? char);
  }

  return buffer
      .toString()
      .replaceAll(RegExp(r"[^A-Za-z0-9\s\-']"), ' ')
      .replaceAll(RegExp(r"\s+"), ' ')
      .trim();
}

// ─────────────────────────────────────────────────────────────────────────────
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
  bool _showGoogleComplete = false;
  String _error = '';
  String _googleAccessToken = '';
  String _googleName = '';
  String _googleEmail = '';

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileController = TextEditingController();
  // Only used by the Google Sign-In profile-completion screen below — the
  // email/OTP registration form (the one being aligned with the web app's
  // fields) no longer collects DOB, gender or country.
  final _dobController = TextEditingController();

  String _selectedGender = '';
  String _selectedCountry = '';
  String _selectedDialCode = '';
  bool _obscurePassword = true;
  bool _termsConsent = false;
  bool _privacyConsent = false;
  bool _hipaaConsent = false;

  // Country list, loaded from the location API — also only feeds the Google
  // completion screen's country dropdown and this form's phone dial-code
  // picker below now, not a standalone "Country" field.
  List<String> _countries = [];
  Map<String, Country> _countryLookup = {};
  bool _loadingCountries = false;

  // OTP
  final _otpController = TextEditingController();
  int _otpTimer = 0;

  final _authRepository = AuthRepository();
  final _authService = AuthService();
  final LocationService _locationService = LocationService();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;
  Timer? _googleWebTimeoutTimer;
  Timer? _otpCountdownTimer;

  @override
  void initState() {
    super.initState();
    // Same default as the web app's PhoneInputField (defaultCountry="IN") —
    // set instantly rather than waiting on the country-list fetch below, so
    // the field never shows a blank/unresolved dial code.
    _selectedDialCode = '+91';
    _fetchCountries();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await GoogleSignIn.instance.initialize();
        _googleAuthSubscription = GoogleSignIn.instance.authenticationEvents.listen(
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
    _mobileController.dispose();
    _dobController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Location API ──────────────────────────────────────────────────────────
  Future<void> _fetchCountries() async {
    setState(() => _loadingCountries = true);
    final result = await _locationService.getCountries();
    if (!mounted) return;
    if (result.success) {
      final countries = result.data ?? [];
      final countryNames = countries
          .map((c) => _normalizeLocationName(c.name))
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _countries = countryNames;
        _countryLookup = {
          for (final country in countries)
            _normalizeLocationName(country.name): country,
        };
      });
      _clearLocationError();
    } else {
      _setLocationError(result.message);
    }
    setState(() => _loadingCountries = false);
  }

  void _applyDialCodeForCountry(String? iso2) {
    _selectedDialCode = dialCodeForIso2(iso2);
  }

  // ── Searchable bottom-sheet picker ────────────────────────────────────────
  Future<String?> _showSearchSheet(String title, List<String> options) {
    String filter = '';
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final filtered = filter.isEmpty
              ? options
              : options
                    .where(
                      (o) => o.toLowerCase().contains(filter.toLowerCase()),
                    )
                    .toList();
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle bar
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff1a3a5c),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xff1a3a5c),
                        size: 20,
                      ),
                      filled: true,
                      fillColor: const Color(0xfff9fafb),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.09),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xff1a3a5c),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (v) => setModal(() => filter = v),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                // Options list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No results found',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(
                              filtered[i],
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            onTap: () => Navigator.pop(ctx, filtered[i]),
                            dense: true,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
    if (!_formKey.currentState!.validate()) return;

    if (!_termsConsent || !_privacyConsent || !_hipaaConsent) {
      _setError('Accept Terms, Privacy Policy, and HIPAA consent requirements');
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
      mobile: _selectedDialCode.isEmpty || _mobileController.text.trim().isEmpty
          ? ''
          : '$_selectedDialCode${_mobileController.text.trim()}',
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
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

    // Mobile is mandatory, and it must carry a resolved dial code — previously
    // an unresolved code silently sent the raw digits with no country code
    // prefix at all, while the field still displayed a placeholder that
    // looked like a real selection.
    if (_selectedDialCode.isEmpty) {
      _setError('Could not resolve a dial code for your country. Re-select your country.');
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
      mobile: _mobileController.text.trim().isEmpty
          ? ''
          : '$_selectedDialCode${_mobileController.text.trim()}',
      countryCode: _selectedDialCode,
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
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
    // starts, where a fast double-tap could still fire this twice — this
    // handler never set _loading at all despite the button's onTap already
    // being gated on it, so that gate was a no-op for this specific action.
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await _authRepository.sendRegisterOtp(
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      mobile: _selectedDialCode.isEmpty || _mobileController.text.trim().isEmpty
          ? ''
          : '$_selectedDialCode${_mobileController.text.trim()}',
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
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

  /// The last message a country/state/city lookup put into [_error].
  ///
  /// The three location lookups share the form's single error slot with
  /// validation messages, and they used to set it on failure without ever
  /// clearing it on success — so an upstream "state not found" for one country
  /// stayed on screen even after picking a country and state that loaded fine.
  /// Remembering what we wrote lets a successful lookup clear its own error
  /// without wiping an unrelated validation message the user is still reading.
  String _lastLocationError = '';

  void _setLocationError(String msg) {
    _lastLocationError = msg;
    _setError(msg);
  }

  void _clearLocationError() {
    if (_error.isEmpty || _error != _lastLocationError) return;
    _lastLocationError = '';
    setState(() => _error = '');
  }

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
          _error = 'Google Sign-In was cancelled or timed out. Please try again.';
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
      setState(() {
        _showGoogleComplete = true;
        _googleAccessToken = result.accessToken;
        _googleName = result.googleName;
        _googleEmail = result.googleEmail;
      });
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
        setState(() {
          _showGoogleComplete = true;
          _googleAccessToken = result.accessToken;
          _googleName = result.googleName;
          _googleEmail = result.googleEmail;
        });
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

  Future<void> _completeGoogleRegistration() async {
    if (_loading) return;
    if (_mobileController.text.trim().isEmpty) {
      _setError('Enter mobile number');
      return;
    }

    final dobError = _getDobError(_dobController.text.trim());
    if (dobError.isNotEmpty) {
      _setError(dobError);
      return;
    }

    if (_selectedGender.isEmpty) {
      _setError('Select Gender');
      return;
    }

    if (_selectedCountry.isEmpty) {
      _setError('Select your country');
      return;
    }

    if (!_privacyConsent || !_hipaaConsent) {
      _setError('Accept Terms, Privacy Policy, and HIPAA consent requirements');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.completeGoogleRegistration(
      accessToken: _googleAccessToken,
      mobile: _mobileController.text.trim(),
      dob: _dobController.text.trim(),
      gender: _selectedGender,
      country: _selectedCountry,
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (!result.success || result.authResponse == null) return;
    try {
      await _authService.saveSession(result.authResponse!);
    } catch (_) {
      // Profile completion already succeeded server-side — only the local
      // session save failed, so surface a recoverable error instead of a
      // silent no-op.
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

  // ── Date picker ───────────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xff1a3a5c)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final iso =
          '${picked.year.toString().padLeft(4, '0')}'
          '-${picked.month.toString().padLeft(2, '0')}'
          '-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _dobController.text = iso);
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

          // ── Contact Information ─────────────────────────────────────────
          _section('Contact Information'),

          IntrinsicHeight(
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch, // forces equal height
              children: [
                // Dial code — searchable country picker, same idea as the web
                // app's PhoneInputField (defaultCountry "IN", searchable list).
                // Defaults to +91 instantly (see initState) rather than
                // waiting on the country-list fetch below.
                SizedBox(
                  width: 84,
                  child: GestureDetector(
                    onTap: _loadingCountries
                        ? null
                        : () async {
                            final picked = await _showSearchSheet(
                              'Select Country Code',
                              _countries,
                            );
                            if (picked != null && mounted) {
                              final countryMeta = _countryLookup[picked];
                              setState(() {
                                _applyDialCodeForCountry(countryMeta?.iso2);
                              });
                            }
                          },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xfff9fafb),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.09),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _selectedDialCode.isEmpty
                                  ? '+--'
                                  : _selectedDialCode,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _selectedDialCode.isEmpty
                                    ? Colors.grey[400]!
                                    : const Color(0xff1a3a5c),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          _loadingCountries
                              ? const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Color(0xff1a3a5c),
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_drop_down,
                                  size: 18,
                                  color: Color(0xff1a3a5c),
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Mobile Number',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      prefixIcon: const Icon(
                        Icons.phone_outlined,
                        size: 18,
                        color: Color(0xff1a3a5c),
                      ),
                      filled: true,
                      fillColor: const Color(0xfff9fafb),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.09),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.09),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xff1a3a5c),
                          width: 1.2,
                        ),
                      ),
                    ),
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return 'Enter mobile number';
                      final err = AuthValidators.mobileError(
                        '$_selectedDialCode$val',
                      );
                      return err.isEmpty ? null : err;
                    },
                  ),
                ),
              ],
            ),
          ),
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

          _ConsentTile(
            label: 'I agree to the ',
            links: const ['Terms', 'Privacy Policy'],
            checked: _termsConsent && _privacyConsent,
            onChanged: (v) => setState(() {
              _termsConsent = v;
              _privacyConsent = v;
            }),
          ),
          const SizedBox(height: 4),
          _ConsentTile(
            label: 'I agree to HIPAA Compliance & Health Data Privacy',
            links: const [],
            checked: _hipaaConsent,
            onChanged: (v) => setState(() => _hipaaConsent = v),
          ),

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

    final disabled = _loading || _googleLoading;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildGoogleCompletionScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff1a3a5c),
        elevation: 0,
        title: const Text('Complete your profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome ${_googleName.isNotEmpty ? _googleName : 'there'}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _googleEmail.isNotEmpty
                    ? 'We need a few more details to finish creating your account for $_googleEmail.'
                    : 'We need a few more details to finish creating your account.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
              ),
              const SizedBox(height: 24),
              if (_error.isNotEmpty) ...[
                _errorBox(_error),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                decoration: _dec(label: 'Mobile Number', icon: Icons.phone_outlined),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _dobController,
                readOnly: true,
                onTap: _pickDob,
                decoration: _dec(
                  label: 'Date of Birth',
                  icon: Icons.calendar_today_outlined,
                  suffix: const Icon(Icons.edit_calendar_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender.isEmpty ? null : _selectedGender,
                decoration: _dec(label: 'Gender', icon: Icons.wc_outlined),
                items: _genders
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedGender = value ?? ''),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedCountry.isEmpty ? null : _selectedCountry,
                decoration: _dec(label: 'Country', icon: Icons.public_outlined),
                items: _countries
                    .map((country) => DropdownMenuItem(value: country, child: Text(country)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedCountry = value ?? ''),
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _privacyConsent,
                onChanged: (value) => setState(() => _privacyConsent = value ?? false),
                title: const Text('I agree to the Privacy Policy'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _hipaaConsent,
                onChanged: (value) => setState(() => _hipaaConsent = value ?? false),
                title: const Text('I accept the HIPAA consent requirements'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _completeGoogleRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1a3a5c),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create Account'),
                ),
              ),
            ],
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
    if (_showGoogleComplete) {
      return _buildGoogleCompletionScreen();
    }

    return AuthScaffold(
      title: _currentStep == _stepForm ? 'Create Account' : 'Verify Email',
      subtitle: _currentStep == _stepForm
          ? 'Join Humancare Connect and take charge of your health'
          : 'Enter the OTP code',
      child: _currentStep == _stepForm ? _buildForm() : _buildOtpStep(),
    );
  }
}

// ─── Consent tile widget ──────────────────────────────────────────────────────
class _ConsentTile extends StatelessWidget {
  final String label;
  final List<String> links;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _ConsentTile({
    required this.label,
    required this.links,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: const Color(0xff1a3a5c),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: links.isEmpty
              ? Text(
                  label,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                )
              : Wrap(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    for (int i = 0; i < links.length; i++) ...[
                      Text(
                        links[i],
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xff2563eb),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (i < links.length - 1)
                        const Text(
                          ' & ',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                    ],
                    const Text(
                      ' & HIPAA Consent.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
