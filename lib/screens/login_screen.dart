import 'package:flutter/material.dart';

import '../home_page.dart';
import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import 'auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _googleLoading = false;
  String _error = '';

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _authService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _error = result.success ? '' : result.message;
    });

    if (!result.success || result.data == null) return;

    await _authService.saveSession(result.data!);
    if (!mounted) return;

    showAuthSnackBar(context, 'Login Successful');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  Future<void> _googleLogin() async {
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

    if (!result.success || result.data == null) return;

    await _authService.saveSession(result.data!);
    if (!mounted) return;

    showAuthSnackBar(context, 'Login Successful');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome Back',
      subtitle: 'Sign in to continue to Humancare Connect',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
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
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if ((value?.trim() ?? '').isEmpty) {
                  return 'Enter your password';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading || _googleLoading
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                child: const Text('Forgot Password?'),
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
              label: 'Sign In',
              loadingLabel: 'Signing in...',
              loading: _loading,
              onPressed: _googleLoading ? null : _login,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loading || _googleLoading ? null : _googleLogin,
              icon: _googleLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.g_mobiledata),
              label: Text(
                _googleLoading ? 'Connecting...' : 'Continue with Google',
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: _loading || _googleLoading
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      ),
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}
