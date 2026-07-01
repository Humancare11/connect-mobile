import 'package:flutter/material.dart';
import '../models/location_model.dart';
import '../models/register_model.dart';
import '../services/auth_repository.dart';
import '../services/auth_validators.dart';
import '../services/location_service.dart';
import '../widgets/auth_widgets.dart';
import 'main_screen.dart';

// ─── Password strength helper ─────────────────────────────────────────────────
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

const List<String> _genders = ['Male', 'Female', 'Other', 'Prefer Not to Say'];

String _normalizeLocationName(String value) {
  const diacritics = <String, String>{
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Ā': 'A', 'Ă': 'A', 'Ą': 'A', 'Ǎ': 'A',
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'ǎ': 'a',
    'Ç': 'C', 'Ć': 'C', 'Č': 'C', 'Ĉ': 'C', 'Ċ': 'C',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c', 'ċ': 'c',
    'Ð': 'D', 'Ď': 'D', 'Đ': 'D',
    'ð': 'd', 'ď': 'd', 'đ': 'd',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ē': 'E', 'Ĕ': 'E', 'Ė': 'E', 'Ę': 'E', 'Ě': 'E',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ĩ': 'I', 'Ī': 'I', 'Ĭ': 'I', 'Į': 'I', 'İ': 'I',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i',
    'Ñ': 'N', 'Ń': 'N', 'Ň': 'N', 'Ņ': 'N',
    'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ņ': 'n',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O', 'Ō': 'O', 'Ŏ': 'O', 'Ő': 'O',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o',
    'Ś': 'S', 'Š': 'S', 'Ş': 'S', 'Ŝ': 'S', 'Ș': 'S',
    'ś': 's', 'š': 's', 'ş': 's', 'ŝ': 's', 'ș': 's',
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ũ': 'U', 'Ū': 'U', 'Ŭ': 'U', 'Ů': 'U', 'Ű': 'U', 'Ų': 'U',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
    'Ý': 'Y', 'Ÿ': 'Y',
    'ý': 'y', 'ÿ': 'y',
    'Ž': 'Z', 'Ź': 'Z', 'Ż': 'Z',
    'ž': 'z', 'ź': 'z', 'ż': 'z',
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
  String _error = '';

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _dobController = TextEditingController();

  String _selectedGender = '';
  String _selectedCountry = '';
  String? _selectedState;
  String? _selectedCity;
  String _selectedDialCode = '';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsConsent = false;
  bool _privacyConsent = false;
  bool _hipaaConsent = false;

  // Location data — all loaded from API
  List<String> _countries = [];
  List<String> _states = [];
  List<String> _cities = [];
  Map<String, Country> _countryLookup = {};
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;

  // OTP
  final _otpController = TextEditingController();
  int _otpTimer = 0;

  final GlobalKey<FormFieldState<String>> _countryFieldKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _stateFieldKey = GlobalKey<FormFieldState<String>>();
  final GlobalKey<FormFieldState<String>> _cityFieldKey = GlobalKey<FormFieldState<String>>();

  final _authRepository = AuthRepository();
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();
    _fetchCountries();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    } else {
      _setError(result.message);
    }
    setState(() => _loadingCountries = false);
  }

  Future<void> _fetchStates(String country) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _selectedState = null;
      _cities = [];
      _selectedCity = null;
    });
    final result = await _locationService.getStates(country);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _states = (result.data ?? [])
            .map((s) => _normalizeLocationName(s.name))
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();
      });
    } else {
      _setError(result.message);
    }
    setState(() => _loadingStates = false);
  }

  Future<void> _fetchCities(String country, String state) async {
    setState(() {
      _loadingCities = true;
      _cities = [];
      _selectedCity = null;
    });
    final result = await _locationService.getCities(country, state);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _cities = (result.data ?? [])
            .map((city) => _normalizeLocationName(city))
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();
      });
    } else {
      _setError(result.message);
    }
    setState(() => _loadingCities = false);
  }

  Future<void> _updateDialCodeForSelectedCountry(String countryName, {String? iso2}) async {
    final result = await _locationService.getDialCode(countryName, iso2: iso2);
    if (!mounted) return;
    if (result.success && (result.data ?? '').isNotEmpty) {
      setState(() => _selectedDialCode = result.data!);
    } else {
      setState(() => _selectedDialCode = '');
    }
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
                  .where((o) => o.toLowerCase().contains(filter.toLowerCase()))
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
                  width: 40, height: 4,
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
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: Color(0xff1a3a5c), size: 20),
                      filled: true,
                      fillColor: const Color(0xfff9fafb),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.09)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xff1a3a5c), width: 1.5),
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
                            style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(
                              filtered[i],
                              style: const TextStyle(fontSize: 14, color: Colors.black87),
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

    if (!_termsConsent || !_privacyConsent || !_hipaaConsent) {
      _setError('Accept Terms, Privacy Policy, and HIPAA consent requirements');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    final result = await _authRepository.sendRegisterOtp(
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      dob: _dobController.text.trim(),
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
    final otp = _otpController.text.trim();
    if (otp.length < 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _setError('Enter the complete 6-digit OTP');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    final formData = RegisterFormData(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      mobile: _mobileController.text.trim().isEmpty
          ? ''
          : '$_selectedDialCode${_mobileController.text.trim()}',
      countryCode: _selectedDialCode,
      dob: _dobController.text.trim(),
      gender: _selectedGender,
      country: _selectedCountry,
      state: _selectedState ?? '',
      city: _selectedCity ?? '',
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
    final result = await _authRepository.sendRegisterOtp(
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      dob: _dobController.text.trim(),
      privacyConsent: _privacyConsent,
      hipaaConsent: _hipaaConsent,
    );
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

  // ── Searchable picker field (replaces DropdownButtonFormField) ────────────
  // Uses FormField so it integrates with Form validation.
  Widget _locationField({
    required Key fieldKey,
    required String label,
    required IconData icon,
    required String? selectedValue,
    required bool loading,
    required bool enabled,
    required String? Function(String?) validator,
    required Future<String?> Function() onTap,
  }) {
    return FormField<String>(
      key: fieldKey,
      initialValue: selectedValue,
      validator: validator,
      builder: (state) {
        // Keep form field value in sync when parent clears it via key rebuild.
        return GestureDetector(
          onTap: (enabled && !loading)
              ? () async {
                  final picked = await onTap();
                  state.didChange(picked ?? selectedValue);
                }
              : null,
          child: InputDecorator(
            decoration: _dec(
              label: label,
              icon: icon,
              suffix: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xff1a3a5c),
                        ),
                      ),
                    )
                  : Icon(
                      enabled ? Icons.arrow_drop_down : Icons.lock_outline,
                      color: enabled
                          ? const Color(0xff1a3a5c)
                          : Colors.grey[400],
                    ),
            ).copyWith(
              errorText: state.errorText,
              enabled: enabled,
            ),
            isEmpty: selectedValue == null || selectedValue.isEmpty,
            child: selectedValue != null && selectedValue.isNotEmpty
                ? Text(selectedValue, style: const TextStyle(fontSize: 14, color: Colors.black87))
                : null,
          ),
        );
      },
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
              if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(val)) return 'Name must contain only letters';
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
              Expanded(
                child: TextFormField(
                  controller: _dobController,
                  readOnly: true,
                  onTap: _pickDob,
                  decoration: _dec(
                    label: 'Date of Birth',
                    icon: Icons.calendar_today_outlined,
                    suffix: const Icon(Icons.edit_calendar_outlined, size: 18, color: Color(0xff1a3a5c)),
                  ),
                  validator: (v) {
                    final err = _getDobError(v ?? '');
                    return err.isEmpty ? null : err;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedGender.isEmpty ? null : _selectedGender,
                  decoration: _dec(label: 'Gender', icon: Icons.wc_outlined),
                  isExpanded: true,
                  items: _genders
                      .map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedGender = v ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Address Information ─────────────────────────────────────────
          _section('Address Information'),

          // Country — searchable picker, loaded from API
          _locationField(
            fieldKey: _countryFieldKey,
            label: _loadingCountries ? 'Loading countries...' : 'Country',
            icon: Icons.public_outlined,
            selectedValue: _selectedCountry.isEmpty ? null : _selectedCountry,
            loading: _loadingCountries,
            enabled: !_loadingCountries,
            validator: (v) => (v == null || v.isEmpty) ? 'Select your country' : null,
            onTap: () async {
              final picked = await _showSearchSheet('Select Country', _countries);
              if (picked != null && mounted) {
                final countryMeta = _countryLookup[picked];
                setState(() {
                  _selectedCountry = picked;
                  _selectedDialCode = '';
                  _selectedState = null;
                  _selectedCity = null;
                  _states = [];
                  _cities = [];
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _countryFieldKey.currentState?.didChange(picked);
                  _stateFieldKey.currentState?.didChange(null);
                  _cityFieldKey.currentState?.didChange(null);
                });
                await _fetchStates(picked);
                await _updateDialCodeForSelectedCountry(
                  picked,
                  iso2: countryMeta?.iso2,
                );
              }
              return picked;
            },
          ),
          const SizedBox(height: 14),

          // State + City row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // State picker
              Expanded(
                child: _locationField(
                  fieldKey: _stateFieldKey,
                  label: _selectedCountry.isEmpty
                      ? 'Select country first'
                      : (_loadingStates ? 'Loading states...' : 'State / Province'),
                  icon: Icons.location_on_outlined,
                  selectedValue: _selectedState,
                  loading: _loadingStates,
                  enabled: _selectedCountry.isNotEmpty && !_loadingStates && _states.isNotEmpty,
                  validator: (v) => (v == null || v.isEmpty) ? 'Select state' : null,
                  onTap: () async {
                    final picked = await _showSearchSheet('Select State', _states);
                    if (picked != null && mounted) {
                      setState(() {
                        _selectedState = picked;
                        _selectedCity = null;
                        _cities = [];
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _stateFieldKey.currentState?.didChange(picked);
                        _cityFieldKey.currentState?.didChange(null);
                      });
                      await _fetchCities(_selectedCountry, picked);
                    }
                    return picked;
                  },
                ),
              ),
              const SizedBox(width: 12),
              // City picker
              Expanded(
                child: _locationField(
                  fieldKey: _cityFieldKey,
                  label: _selectedState == null
                      ? 'Select state first'
                      : (_loadingCities ? 'Loading cities...' : 'City'),
                  icon: Icons.location_city_outlined,
                  selectedValue: _selectedCity,
                  loading: _loadingCities,
                  enabled: _selectedState != null && !_loadingCities && _cities.isNotEmpty,
                  validator: (v) => (v == null || v.isEmpty) ? 'Select city' : null,
                  onTap: () async {
                    final picked = await _showSearchSheet('Select City', _cities);
                    if (picked != null && mounted) {
                      setState(() => _selectedCity = picked);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _cityFieldKey.currentState?.didChange(picked);
                      });
                    }
                    return picked;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Contact Information ─────────────────────────────────────────
          _section('Contact Information'),

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
                    border: Border.all(color: Colors.black.withValues(alpha: 0.09)),
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
                    if ((v?.trim() ?? '').isEmpty) return null;
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

          // ── Security ───────────────────────────────────────────────────
          _section('Security'),

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
          _buildPasswordChecklist(),
          const SizedBox(height: 14),

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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Already have an account? ', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Sign In',
                  style: TextStyle(color: Color(0xff1a3a5c), fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
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
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
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
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.email_outlined, color: Color(0xff1a3a5c), size: 34),
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit security code to\n'),
                    TextSpan(
                      text: _emailController.text,
                      style: const TextStyle(color: Color(0xff2563eb), fontWeight: FontWeight.w700),
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
                        Text("Didn't receive it? ", style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        GestureDetector(
                          onTap: _loading ? null : _handleResendOtp,
                          child: const Text(
                            'Resend OTP',
                            style: TextStyle(color: Color(0xff2563eb), fontWeight: FontWeight.w700, fontSize: 13),
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
