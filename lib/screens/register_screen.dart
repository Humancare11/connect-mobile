import 'package:flutter/material.dart';
import '../models/register_model.dart';
import '../services/auth_repository.dart';
import '../services/auth_validators.dart';
import '../widgets/auth_widgets.dart';
import 'main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const int _stepEmailOtp = 0;
  static const int _stepRegistration = 1;
  static const int _stepOtpVerification = 2;

  int _currentStep = _stepEmailOtp;
  bool _loading = false;
  String _error = '';

  // Email OTP Step
  final _emailController = TextEditingController();
  bool _emailOtpSent = false;

  // Registration Step
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _countryCodeController = TextEditingController();
  final _dobController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();
  String _selectedGender = '';
  String _selectedCountry = '';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _privacyConsent = false;
  bool _hipaaConsent = false;
  final _formKey = GlobalKey<FormState>();

  // OTP Verification Step
  final _otpController = TextEditingController();
  int _otpTimeoutSeconds = 60;
  late DateTime _otpSentTime;

  final _authRepository = AuthRepository();

  final List<String> _genderOptions = [
    'Male',
    'Female',
    'Other',
    'Prefer Not to Say',
  ];

  final List<String> _countryOptions = [
    'United States',
    'Canada',
    'United Kingdom',
    'Australia',
    'India',
    'Other',
  ];

  final List<String> _countryCodeOptions = [
    '+1',      // US, Canada
    '+44',     // UK
    '+61',     // Australia
    '+91',     // India
    '+86',     // China
    '+81',     // Japan
    '+33',     // France
    '+49',     // Germany
    '+39',     // Italy
    '+34',     // Spain
    '+31',     // Netherlands
    '+46',     // Sweden
    '+47',     // Norway
    '+45',     // Denmark
    '+43',     // Austria
  ];

  @override
  void initState() {
    super.initState();
    _countryCodeController.text = '+1';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _mobileController.dispose();
    _countryCodeController.dispose();
    _dobController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showError('Enter your email address');
      return;
    }

    if (!AuthValidators.isValidEmail(email)) {
      _showError('Enter a valid email address');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authRepository.sendRegisterOtp(email);

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (result.success) {
      _otpSentTime = DateTime.now();
      _otpTimeoutSeconds = 60;
      _startOtpTimer();

      setState(() {
        _emailOtpSent = true;
        _currentStep = _stepRegistration;
      });

      showAuthSnackBar(context, 'OTP sent to your email');
    }
  }

  void _startOtpTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _otpTimeoutSeconds > 0) {
        setState(() {
          _otpTimeoutSeconds--;
        });
        _startOtpTimer();
      }
    });
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_privacyConsent || !_hipaaConsent) {
      _showError('Please accept the privacy and HIPAA consents');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
      _currentStep = _stepOtpVerification;
    });
  }

  Future<void> _verifyOtpAndRegister() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showError('Enter a valid 6-digit OTP');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final formData = RegisterFormData(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      mobile: _mobileController.text.trim(),
      countryCode: _countryCodeController.text.trim(),
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

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (result.success) {
      showAuthSnackBar(context, 'Registration successful!');
      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } else {
      setState(() {
        _currentStep = _stepOtpVerification;
      });
    }
  }

  void _showError(String message) {
    setState(() {
      _error = message;
    });
  }

  void _goBackToEmail() {
    setState(() {
      _currentStep = _stepEmailOtp;
      _emailOtpSent = false;
      _error = '';
    });
  }

  void _goBackToRegistration() {
    setState(() {
      _currentStep = _stepRegistration;
      _loading = false;
      _error = '';
    });
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xfff9fafb),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xff1a3a5c), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildEmailOtpStep() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.email_outlined,
                  color: Color(0xff1a3a5c),
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  label: 'Email Address',
                  icon: Icons.mail_outline,
                ),
                validator: (value) {
                  if ((value?.trim() ?? '').isEmpty) {
                    return 'Enter your email address';
                  }
                  if (!AuthValidators.isValidEmail(value!)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              AuthButton(
                label: 'Send OTP',
                loadingLabel: 'Sending OTP...',
                loading: _loading,
                onPressed: _loading ? null : _sendOtp,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationStep() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Complete Registration',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Step 1 of 2',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _goBackToEmail,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Personal Information Section
                Text(
                  'Personal Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration(
                    label: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    if ((value?.trim() ?? '').isEmpty) {
                      return 'Enter your full name';
                    }
                    if ((value?.trim() ?? '').length < 3) {
                      return 'Name must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _dobController,
                  keyboardType: TextInputType.datetime,
                  decoration: _inputDecoration(
                    label: 'Date of Birth (YYYY-MM-DD)',
                    icon: Icons.calendar_today_outlined,
                  ),
                  validator: (value) {
                    final error = AuthValidators.dobError(value ?? '');
                    return error.isEmpty ? null : error;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedGender.isEmpty ? null : _selectedGender,
                  decoration: _inputDecoration(
                    label: 'Gender',
                    icon: Icons.wc_outlined,
                  ),
                  items: _genderOptions
                      .map(
                        (gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(gender),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedGender = value ?? '';
                    });
                  },
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Select your gender';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                // Address Information Section
                Text(
                  'Address Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedCountry.isEmpty ? null : _selectedCountry,
                  decoration: _inputDecoration(
                    label: 'Country',
                    icon: Icons.public_outlined,
                  ),
                  items: _countryOptions
                      .map(
                        (country) => DropdownMenuItem(
                          value: country,
                          child: Text(country),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCountry = value ?? '';
                    });
                  },
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Select your country';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _stateController,
                  decoration: _inputDecoration(
                    label: 'State / Province',
                    icon: Icons.location_on_outlined,
                  ),
                  validator: (value) {
                    final error = AuthValidators.stateError(value ?? '');
                    return error.isEmpty ? null : error;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cityController,
                  decoration: _inputDecoration(
                    label: 'City',
                    icon: Icons.location_city_outlined,
                  ),
                  validator: (value) {
                    final error = AuthValidators.cityError(value ?? '');
                    return error.isEmpty ? null : error;
                  },
                ),
                const SizedBox(height: 18),
                // Contact Information Section
                Text(
                  'Contact Information',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _countryCodeController.text.isEmpty
                            ? null
                            : _countryCodeController.text,
                        decoration: _inputDecoration(
                          label: 'Code',
                          icon: Icons.phone_outlined,
                        ),
                        items: _countryCodeOptions
                            .map(
                              (code) => DropdownMenuItem(
                                value: code,
                                child: Text(code),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _countryCodeController.text = value ?? '+1';
                          });
                        },
                        validator: (value) {
                          final error = AuthValidators.countryCodeError(value ?? '');
                          return error.isEmpty ? null : error;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(
                          label: 'Mobile Number',
                          icon: Icons.phone_outlined,
                        ),
                        validator: (value) {
                          if ((value?.trim() ?? '').isEmpty) {
                            return 'Enter your mobile number';
                          }
                          if (!RegExp(r'^[\d\-\+\s\(\)]{10,}$').hasMatch(value!)) {
                            return 'Enter a valid mobile number';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Security Section
                Text(
                  'Security',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDecoration(
                    label: 'Password',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    final error = AuthValidators.passwordError(value ?? '');
                    return error.isEmpty ? null : error;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  AuthValidators.passwordRequirements,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: _inputDecoration(
                    label: 'Confirm Password',
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if ((value?.trim() ?? '').isEmpty) {
                      return 'Confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                // Consent Section
                Text(
                  'Consent',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _privacyConsent,
                  onChanged: (value) {
                    setState(() {
                      _privacyConsent = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I agree to the Privacy Policy & Terms of Service',
                    style: TextStyle(fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: _hipaaConsent,
                  onChanged: (value) {
                    setState(() {
                      _hipaaConsent = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I agree to HIPAA Compliance & Health Data Privacy',
                    style: TextStyle(fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                AuthButton(
                  label: 'Verify with OTP',
                  loadingLabel: 'Validating...',
                  loading: _loading,
                  onPressed: _loading ? null : _submitRegistration,
                ),
              ],
            ),
          ),
        );
    }

  Widget _buildOtpVerificationStep() {
    final canResendOtp = _otpTimeoutSeconds == 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verify OTP',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Step 2 of 2',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _goBackToRegistration,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ],
              ),
              const Divider(height: 24),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xffeaf2ff),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Color(0xff1a3a5c),
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Verification code sent to ${_emailController.text}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              OtpTextField(
                controller: _otpController,
                onChanged: (value) {
                  if (value.length == 6) {
                    _verifyOtpAndRegister();
                  }
                },
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _loading ? null : _goBackToRegistration,
                    child: const Text('Change Email'),
                  ),
                  if (!canResendOtp)
                    Expanded(
                      child: Center(
                        child: Text(
                          'Resend in ${_otpTimeoutSeconds}s',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  _otpController.clear();
                                  _sendOtp();
                                },
                          child: const Text('Resend OTP'),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              AuthButton(
                label: 'Complete Registration',
                loadingLabel: 'Registering...',
                loading: _loading,
                onPressed: _loading ? null : _verifyOtpAndRegister,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Create Account';
    String subtitle = 'Join Humancare Connect';

    if (_currentStep == _stepRegistration) {
      title = 'Complete Registration';
      subtitle = 'Provide your details';
    } else if (_currentStep == _stepOtpVerification) {
      title = 'Verify Email';
      subtitle = 'Enter the OTP code';
    }

    return AuthScaffold(
      title: title,
      subtitle: subtitle,
      child: _currentStep == _stepEmailOtp
          ? _buildEmailOtpStep()
          : _currentStep == _stepRegistration
          ? _buildRegistrationStep()
          : _buildOtpVerificationStep(),
    );
  }
}
