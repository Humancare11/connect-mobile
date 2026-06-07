import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import 'auth_widgets.dart';
import 'email_otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  String _dob = '';
  String _gender = '';
  String _country = '';
  bool _termsAccepted = false;
  bool _loading = false;
  String _error = '';

  Future<void> _selectDob() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDate: DateTime(2000),
    );

    if (selected == null) return;

    setState(() {
      _dob = selected.toIso8601String().substring(0, 10);
    });
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_termsAccepted) {
      setState(() {
        _error = 'Accept Terms, Privacy Policy, and HIPAA consent requirements';
      });
      return;
    }

    final passwordError = AuthValidators.passwordError(
      _passwordController.text,
    );
    if (passwordError.isNotEmpty) {
      setState(() {
        _error = passwordError;
      });
      return;
    }

    final dobError = AuthValidators.dobError(_dob);
    if (dobError.isNotEmpty) {
      setState(() {
        _error = dobError;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.sendRegisterOtp(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      dob: _dob,
      privacyConsent: _termsAccepted,
      hipaaConsent: _termsAccepted,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (!result.success) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailOtpVerificationScreen(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
          dob: _dob,
          gender: _gender,
          country: _country,
          password: _passwordController.text,
          privacyConsent: _termsAccepted,
          hipaaConsent: _termsAccepted,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create Account',
      subtitle: 'Join HumaniCare and take charge of your health',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim() ?? '').isEmpty ? 'Enter full name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return 'Enter your email address';
                if (!AuthValidators.isValidEmail(email)) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              readOnly: true,
              onTap: _selectDob,
              decoration: InputDecoration(
                labelText: 'Date of Birth',
                hintText: _dob.isEmpty ? 'Select Date of Birth' : _dob,
                border: const OutlineInputBorder(),
              ),
              validator: (_) {
                final error = AuthValidators.dobError(_dob);
                return error.isEmpty ? null : error;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender.isEmpty ? null : _gender,
              decoration: const InputDecoration(
                labelText: 'Gender',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _gender = value ?? ''),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Select Gender' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Country',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _country = value.trim(),
              validator: (value) =>
                  (value?.trim() ?? '').isEmpty ? 'Select your country' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value?.trim() ?? '').isEmpty ? 'Enter mobile number' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Create password',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final error = AuthValidators.passwordError(value ?? '');
                return error.isEmpty ? null : error;
              },
            ),
            const SizedBox(height: 6),
            const Text(
              AuthValidators.passwordRequirements,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            CheckboxListTile(
              value: _termsAccepted,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() => _termsAccepted = value ?? false);
              },
              title: const Text(
                'I agree to the Terms, Privacy Policy, and HIPAA consent requirements.',
                style: TextStyle(fontSize: 13),
              ),
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
              label: 'Create Account',
              loadingLabel: 'Creating...',
              loading: _loading,
              onPressed: _sendOtp,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
