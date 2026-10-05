import 'package:flutter/material.dart';

import '../models/apple_auth_result.dart';
import '../models/auth_response.dart';
import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/consent_checkboxes.dart';
import '../widgets/geo_field_style.dart';
import '../widgets/geo_phone_controller.dart';
import '../widgets/geo_phone_fields.dart';
import 'main_screen.dart';

/// Who is finishing sign-up. Exactly one of [googleAccessToken] /
/// [appleCredential] is set.
class SocialSignupSession {
  const SocialSignupSession({
    required this.name,
    required this.email,
    this.googleAccessToken = '',
    this.appleCredential,
  });

  final String name;
  final String email;
  final String googleAccessToken;
  final AppleCredentialData? appleCredential;

  bool get isApple => appleCredential != null;
}

/// The one "Complete your profile" screen for a brand-new Google or Apple
/// user, used from both the Register and the Login screen. Same fields and
/// rules as the web's Google completion step: name and email read-only, then
/// Country, State, City, Phone (with the Country ↔ code sync) and the three
/// consents.
class SocialSignupCompletionScreen extends StatefulWidget {
  const SocialSignupCompletionScreen({super.key, required this.session});

  final SocialSignupSession session;

  static Future<void> open(BuildContext context, SocialSignupSession session) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialSignupCompletionScreen(session: session),
      ),
    );
  }

  @override
  State<SocialSignupCompletionScreen> createState() =>
      _SocialSignupCompletionScreenState();
}

class _SocialSignupCompletionScreenState
    extends State<SocialSignupCompletionScreen> {
  static const Color _navy = Color(0xff1a3a5c);

  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _geo = GeoPhoneController();
  final _consents = ConsentController();
  // Apple only shares the name on the very first authorization; if we never
  // got it the user must type it.
  final _appleNameController = TextEditingController();

  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _geo.init();
  }

  @override
  void dispose() {
    _geo.dispose();
    _consents.dispose();
    _appleNameController.dispose();
    super.dispose();
  }

  bool get _needsName =>
      widget.session.isApple && widget.session.name.trim().isEmpty;

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();

    final name = _needsName
        ? _appleNameController.text.trim()
        : widget.session.name.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(
        () =>
            _error = _geo.firstError ?? 'Please check the highlighted fields.',
      );
      return;
    }
    if (!_consents.allAccepted) {
      setState(() => _error = kConsentError);
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final mobile = _geo.fullNumber;
    final country = _geo.countryName;
    final state = _geo.state;
    final city = _geo.city;

    final session = widget.session;
    final bool ok;
    final String message;
    final AuthResponse? authResponse;
    if (session.isApple) {
      final result = await _authService.completeAppleRegistration(
        credential: session.appleCredential!,
        name: name,
        email: session.email,
        mobile: mobile,
        country: country,
        state: state,
        city: city,
        privacyConsent: _consents.privacy,
        hipaaConsent: _consents.hipaa,
      );
      ok = result.success;
      message = result.message;
      authResponse = result.authResponse;
    } else {
      final result = await _authService.completeGoogleRegistration(
        accessToken: session.googleAccessToken,
        mobile: mobile,
        country: country,
        state: state,
        city: city,
        privacyConsent: _consents.privacy,
        hipaaConsent: _consents.hipaa,
      );
      ok = result.success;
      message = result.message;
      authResponse = result.authResponse;
    }
    if (!mounted) return;

    if (!ok || authResponse == null) {
      setState(() {
        _loading = false;
        _error = message.isNotEmpty ? message : 'Registration failed.';
      });
      return;
    }

    try {
      await _authService.saveSession(authResponse);
    } catch (_) {
      // The account already exists server-side; only the local session save
      // failed (e.g. secure storage unavailable).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Your account was created, but we could not sign you in automatically. Please log in.';
      });
      return;
    }
    if (!mounted) return;
    showAuthSnackBar(context, 'Registration Successful');
    // Clear Login/Register from the stack so Back can't return to them.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final isRelay = session.email.toLowerCase().endsWith(
      '@privaterelay.appleid.com',
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        elevation: 0,
        title: const Text(
          'Complete your profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome ${session.name.isNotEmpty ? session.name : 'there'}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.email.isNotEmpty
                      ? 'We need a few more details to finish creating your account for ${session.email}.'
                      : 'We need a few more details to finish creating your account.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (_error.isNotEmpty) ...[
                  _ErrorBox(message: _error),
                  const SizedBox(height: 16),
                ],
                if (_needsName) ...[
                  TextFormField(
                    controller: _appleNameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: GeoFieldStyle.auth.decoration(
                      label: 'Full name',
                      prefixIcon: GeoFieldStyle.auth.prefix(
                        icon: Icons.person_outline,
                        emoji: '👤',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  _ReadOnlyField(
                    label: 'Full Name',
                    value: session.name,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 14),
                ],
                _ReadOnlyField(
                  label: 'Email Address',
                  value: session.email,
                  icon: Icons.mail_outline,
                ),
                if (session.isApple && isRelay) ...[
                  const SizedBox(height: 10),
                  const Text(
                    "You chose to hide your email, so account emails will be sent through Apple's private relay address.",
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                GeoPhoneFields(controller: _geo),
                const SizedBox(height: 16),
                ConsentCheckboxes(controller: _consents),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label|$value'),
      initialValue: value,
      enabled: false,
      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
      decoration: GeoFieldStyle.auth.decoration(
        label: label,
        prefixIcon: GeoFieldStyle.auth.prefix(icon: icon, emoji: ''),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.red.shade700,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
