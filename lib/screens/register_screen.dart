import 'package:flutter/material.dart';
import '../models/register_model.dart';
import '../services/auth_repository.dart';
import '../services/auth_validators.dart';
import '../widgets/auth_widgets.dart';
import 'main_screen.dart';

// ─── Password strength helper (mirrors web getPasswordError) ─────────────────
const _commonPasswords = {
  'password', 'password1', 'password123', '12345678', '123456789',
  'qwerty123', 'admin123', 'admin1234', 'welcome1', 'welcome123',
  'letmein1', 'iloveyou1', 'humancare', 'humancare123', 'doctor123',
  'patient123',
};

String _getPasswordError(String value) {
  if (value.length < 8) return 'Password must be at least 8 characters.';
  if (!RegExp(r'[A-Z]').hasMatch(value))
    return 'Password must include at least one uppercase letter.';
  if (!RegExp(r'[a-z]').hasMatch(value))
    return 'Password must include at least one lowercase letter.';
  if (!RegExp(r'[0-9]').hasMatch(value))
    return 'Password must include at least one number.';
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value))
    return 'Password must include at least one special character.';
  if (_commonPasswords.contains(value.toLowerCase()))
    return 'Password is too common. Choose a stronger password.';
  return '';
}

String _getDobError(String dob) {
  if (dob.isEmpty) return 'Select Date of Birth';
  final parsed = DateTime.tryParse(dob);
  if (parsed == null) return 'Enter a valid Date of Birth';
  if (parsed.isAfter(DateTime.now())) return 'Date of Birth cannot be in the future';
  if (parsed.isBefore(DateTime(1900))) return 'Date of Birth must be in or after 1900';
  return '';
}

// ─── Countries list (matches web) ────────────────────────────────────────────
const List<String> _countries = [
  'Afghanistan', 'Albania', 'Algeria', 'Argentina', 'Australia', 'Austria',
  'Azerbaijan', 'Bahrain', 'Bangladesh', 'Belgium', 'Bolivia', 'Brazil',
  'Canada', 'Chile', 'China', 'Colombia', 'Croatia', 'Czech Republic',
  'Denmark', 'Ecuador', 'Egypt', 'Ethiopia', 'Finland', 'France', 'Germany',
  'Ghana', 'Greece', 'Guatemala', 'Hungary', 'India', 'Indonesia', 'Iran',
  'Iraq', 'Ireland', 'Israel', 'Italy', 'Japan', 'Jordan', 'Kazakhstan',
  'Kenya', 'Kuwait', 'Lebanon', 'Libya', 'Malaysia', 'Mexico', 'Morocco',
  'Myanmar', 'Nepal', 'Netherlands', 'New Zealand', 'Nigeria', 'Norway',
  'Oman', 'Pakistan', 'Peru', 'Philippines', 'Poland', 'Portugal', 'Qatar',
  'Romania', 'Russia', 'Saudi Arabia', 'Serbia', 'Singapore', 'South Africa',
  'South Korea', 'Spain', 'Sri Lanka', 'Sudan', 'Sweden', 'Switzerland',
  'Syria', 'Taiwan', 'Tanzania', 'Thailand', 'Tunisia', 'Turkey', 'Uganda',
  'Ukraine', 'United Arab Emirates', 'United Kingdom', 'United States',
  'Uruguay', 'Uzbekistan', 'Venezuela', 'Vietnam', 'Yemen', 'Zambia', 'Zimbabwe',
];

const List<String> _genders = ['Male', 'Female', 'Other', 'Prefer Not to Say'];

// ─── Country code map ─────────────────────────────────────────────────────────
const Map<String, String> _countryDialCodes = {
  'Afghanistan': '+93', 'Albania': '+355', 'Algeria': '+213',
  'Argentina': '+54', 'Australia': '+61', 'Austria': '+43',
  'Azerbaijan': '+994', 'Bahrain': '+973', 'Bangladesh': '+880',
  'Belgium': '+32', 'Bolivia': '+591', 'Brazil': '+55',
  'Canada': '+1', 'Chile': '+56', 'China': '+86',
  'Colombia': '+57', 'Croatia': '+385', 'Czech Republic': '+420',
  'Denmark': '+45', 'Ecuador': '+593', 'Egypt': '+20',
  'Ethiopia': '+251', 'Finland': '+358', 'France': '+33',
  'Germany': '+49', 'Ghana': '+233', 'Greece': '+30',
  'Guatemala': '+502', 'Hungary': '+36', 'India': '+91',
  'Indonesia': '+62', 'Iran': '+98', 'Iraq': '+964',
  'Ireland': '+353', 'Israel': '+972', 'Italy': '+39',
  'Japan': '+81', 'Jordan': '+962', 'Kazakhstan': '+7',
  'Kenya': '+254', 'Kuwait': '+965', 'Lebanon': '+961',
  'Libya': '+218', 'Malaysia': '+60', 'Mexico': '+52',
  'Morocco': '+212', 'Myanmar': '+95', 'Nepal': '+977',
  'Netherlands': '+31', 'New Zealand': '+64', 'Nigeria': '+234',
  'Norway': '+47', 'Oman': '+968', 'Pakistan': '+92',
  'Peru': '+51', 'Philippines': '+63', 'Poland': '+48',
  'Portugal': '+351', 'Qatar': '+974', 'Romania': '+40',
  'Russia': '+7', 'Saudi Arabia': '+966', 'Serbia': '+381',
  'Singapore': '+65', 'South Africa': '+27', 'South Korea': '+82',
  'Spain': '+34', 'Sri Lanka': '+94', 'Sudan': '+249',
  'Sweden': '+46', 'Switzerland': '+41', 'Syria': '+963',
  'Taiwan': '+886', 'Tanzania': '+255', 'Thailand': '+66',
  'Tunisia': '+216', 'Turkey': '+90', 'Uganda': '+256',
  'Ukraine': '+380', 'United Arab Emirates': '+971',
  'United Kingdom': '+44', 'United States': '+1',
  'Uruguay': '+598', 'Uzbekistan': '+998', 'Venezuela': '+58',
  'Vietnam': '+84', 'Yemen': '+967', 'Zambia': '+260', 'Zimbabwe': '+263',
};

// ─────────────────────────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Steps: 0 = registration form, 1 = OTP verification
  static const int _stepForm = 0;
  static const int _stepOtp = 1;

  int _currentStep = _stepForm;
  bool _loading = false;
  String _error = '';

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _dobController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();

  String _selectedGender = '';
  String _selectedCountry = '';
  String _selectedDialCode = '+1';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsConsent = false;
  bool _privacyConsent = false;
  bool _hipaaConsent = false;

  // OTP
  final _otpController = TextEditingController();
  int _otpTimer = 0;

  final _authRepository = AuthRepository();

  // Password error (live, mirrors web hc-pw-requirements--error)
  String get _passwordLiveError =>
      _passwordController.text.isEmpty ? '' : _getPasswordError(_passwordController.text);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _mobileController.dispose();
    _dobController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────
  void _startTimer() {
    setState(() => _otpTimer = 60);
    _tickTimer();
  }

  void _tickTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _otpTimer > 0) {
        setState(() => _otpTimer--);
        _tickTimer();
      }
    });
  }

  // ── Submit registration → send OTP ────────────────────────────────────────
  Future<void> _handleRegisterSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // Consent check (matches web logic)
    if (!_termsConsent || !_privacyConsent || !_hipaaConsent) {
      _setError('Accept Terms, Privacy Policy, and HIPAA consent requirements');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    final result = await _authRepository.sendRegisterOtp(_emailController.text.trim());

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
    final otp = _otpController.text.trim();
    if (otp.length < 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _setError('Enter the complete 6-digit OTP');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    final formData = RegisterFormData(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      mobile: '$_selectedDialCode${_mobileController.text.trim()}',
      countryCode: _selectedDialCode,
      dob: _dobController.text.trim(),
      gender: _selectedGender,
      country: _selectedCountry,
      state: _stateController.text.trim(),
      city: _cityController.text.trim(),
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
    );

    final request = formData.toRegisterRequest(otp);
    final result = await _authRepository.register(request);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success) {
      showAuthSnackBar(context, 'Registration successful!');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      _setError(result.message);
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────
  Future<void> _handleResendOtp() async {
    setState(() => _error = '');
    final result = await _authRepository.sendRegisterOtp(_emailController.text.trim());
    if (!mounted) return;
    if (result.success) {
      _startTimer();
      showAuthSnackBar(context, 'OTP resent');
    } else {
      _setError(result.message);
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

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
      final iso = '${picked.year.toString().padLeft(4, '0')}'
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
        borderSide: BorderSide(color: Colors.black.withOpacity(0.09)),
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
      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Password strength checklist ──────────────────────────────────────────
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
      (RegExp(r'[^A-Za-z0-9]').hasMatch(pw), 'One special character (!@#\$...)'),
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

  // STEP 1 — Registration form
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

            // ── Personal Information ──────────────────────────────────────
            _section('Personal Information'),

            // Full Name — only letters + spaces (matches web replace logic)
            TextFormField(
              controller: _nameController,
              decoration: _dec(label: 'Full Name', icon: Icons.person_outline),
              inputFormatters: [
                // Allow only letters and spaces
              ],
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
              decoration: _dec(label: 'Email Address', icon: Icons.mail_outline),
              validator: (v) {
                if ((v?.trim() ?? '').isEmpty) return 'Enter your email address';
                if (!AuthValidators.isValidEmail(v!)) return 'Enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // DOB + Gender row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date of Birth — tap to open date picker
                Expanded(
                  child: TextFormField(
                    controller: _dobController,
                    readOnly: true,
                    onTap: _pickDob,
                    decoration: _dec(
                      label: 'Date of Birth',
                      icon: Icons.calendar_today_outlined,
                      suffix: const Icon(Icons.edit_calendar_outlined,
                          size: 18, color: Color(0xff1a3a5c)),
                    ),
                    validator: (v) {
                      final err = _getDobError(v ?? '');
                      return err.isEmpty ? null : err;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Gender
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedGender.isEmpty ? null : _selectedGender,
                    decoration: _dec(label: 'Gender', icon: Icons.wc_outlined),
                    isExpanded: true,
                    items: _genders
                        .map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 14))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedGender = v ?? ''),
                    validator: (v) => (v ?? '').isEmpty ? 'Select Gender' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Address Information ───────────────────────────────────────
            _section('Address Information'),

            // Country
            DropdownButtonFormField<String>(
              value: _selectedCountry.isEmpty ? null : _selectedCountry,
              decoration: _dec(label: 'Country', icon: Icons.public_outlined),
              isExpanded: true,
              items: _countries
                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedCountry = v ?? '';
                  _selectedDialCode = _countryDialCodes[_selectedCountry] ?? '+1';
                });
              },
              validator: (v) => (v ?? '').isEmpty ? 'Select your country' : null,
            ),
            const SizedBox(height: 14),

            // State + City row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _stateController,
                    decoration: _dec(
                      label: _selectedCountry.isEmpty ? 'Select country first' : 'State / Province',
                      icon: Icons.location_on_outlined,
                    ),
                    enabled: _selectedCountry.isNotEmpty,
                    validator: (v) {
                      if (_selectedCountry.isEmpty) return null;
                      if ((v?.trim() ?? '').isEmpty) return 'Enter state / province';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cityController,
                    decoration: _dec(
                      label: _stateController.text.isEmpty ? 'Select state first' : 'City',
                      icon: Icons.location_city_outlined,
                    ),
                    enabled: _stateController.text.isNotEmpty,
                    validator: (v) {
                      if (_stateController.text.isEmpty) return null;
                      if ((v?.trim() ?? '').isEmpty) return 'Enter your city';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Contact Information ───────────────────────────────────────
            _section('Contact Information'),

            // Dial code + Mobile number row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dial code (auto-updates from country selection)
                SizedBox(
                  width: 100,
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xfff9fafb),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.09)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _selectedDialCode,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff1a3a5c),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    decoration: _dec(label: 'Mobile Number', icon: Icons.phone_outlined),
                    validator: (v) {
                      if ((v?.trim() ?? '').isEmpty) return 'Enter mobile number';
                      if (!RegExp(r'^[\d\-\+\s\(\)]{7,}$').hasMatch(v!)) {
                        return 'Enter a valid mobile number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Security ─────────────────────────────────────────────────
            _section('Security'),

            // Password with live error (mirrors web hc-pw-requirements)
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: _dec(
                label: 'Password',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                final err = _getPasswordError(v ?? '');
                return err.isEmpty ? null : err;
              },
            ),
            const SizedBox(height: 8),
            // Live password checklist
            _buildPasswordChecklist(),
            const SizedBox(height: 14),

            // Confirm password
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              decoration: _dec(
                label: 'Confirm Password',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
              validator: (v) {
                if ((v?.trim() ?? '').isEmpty) return 'Confirm your password';
                if (v != _passwordController.text) return 'Passwords do not match';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── Consent (matches web single-checkbox logic) ───────────────
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

            // Submit
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _handleRegisterSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1a3a5c),
                  disabledBackgroundColor: const Color(0xff1a3a5c).withOpacity(0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Sign Up',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),

            const SizedBox(height: 20),
            // Already have account
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Already have an account? ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — OTP Verification (matches web register-otp view)
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
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              // Back button row
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() { _currentStep = _stepForm; _error = ''; }),
                    icon: const Icon(Icons.arrow_back, color: Color(0xff1a3a5c)),
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

              // Email icon
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.email_outlined, color: Color(0xff1a3a5c), size: 34),
              ),
              const SizedBox(height: 16),

              // Subtitle matches web: "We sent a 6-digit security code to <email>"
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit security code to\n'),
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

              // 6-box OTP input
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

              // Resend row (matches web otpTimer logic)
              _otpTimer > 0
                  ? Text(
                      'Resend in ${_otpTimer}s',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Didn't receive it? ", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _handleOtpSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1a3a5c),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text(
                          'Verify & Create Account',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
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
          width: 24, height: 24,
          child: Checkbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: const Color(0xff1a3a5c),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: links.isEmpty
              ? Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87))
              : Wrap(
                  children: [
                    Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
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
                        const Text(' & ', style: TextStyle(fontSize: 13, color: Colors.black87)),
                    ],
                    const Text(' & HIPAA Consent.', style: TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ),
        ),
      ],
    );
  }
}