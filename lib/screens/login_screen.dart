import 'package:flutter/material.dart';
import 'main_screen.dart';
import 'register_screen.dart';
import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import '../widgets/auth_widgets.dart';

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
  bool _obscurePassword = true;
  String _error = '';

  // Brand tokens
  static const Color _primary = Color(0xFF052269);
  static const Color _primaryDeep = Color(0xFF1A3A8A);
  static const Color _surface = Color(0xFFF9FAFC);
  static const Color _textDark = Color(0xFF0A0E27);
  static const Color _textMuted = Color(0xFF6B7280);

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
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
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
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // ─── Background gradient ─────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 320,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEAF0FB), Colors.white],
                    ),
                  ),
                ),
              ),
            ),

            // ─── Decorative orbs ─────────────────────────────────
            Positioned(
              top: -50,
              right: -50,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primary.withOpacity(0.06),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 100,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primary.withOpacity(0.04),
                  ),
                ),
              ),
            ),

            // ─── Content ─────────────────────────────────────────
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  _buildLogo(),
                  const SizedBox(height: 36),
                  _buildWelcomeText(),
                  const SizedBox(height: 28),
                  _buildLoginCard(),
                  const SizedBox(height: 24),
                  _buildSignUpLink(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LOGO ──────────────────────────────────────────────────────
  Widget _buildLogo() {
    return Column(children: [Image.asset('assets/Logo.png', width: 150)]);
  }

  // ─── WELCOME ───────────────────────────────────────────────────
  Widget _buildWelcomeText() {
    return Column(
      children: const [
        Text(
          'Welcome Back',
          style: TextStyle(
            fontFamily: 'Satoshi',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _textDark,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Sign in to continue your healthcare journey',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Satoshi',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _textMuted,
          ),
        ),
      ],
    );
  }

  // ─── CARD ──────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label('Email Address'),
            const SizedBox(height: 8),
            _emailField(),
            const SizedBox(height: 18),
            _label('Password'),
            const SizedBox(height: 8),
            _passwordField(),
            const SizedBox(height: 12),
            _forgotPassword(),
            if (_error.isNotEmpty) ...[const SizedBox(height: 16), _errorBox()],
            const SizedBox(height: 22),
            _signInButton(),
            const SizedBox(height: 22),
            _divider(),
            const SizedBox(height: 18),
            _googleButton(),
          ],
        ),
      ),
    );
  }

  // ─── FORM PIECES ───────────────────────────────────────────────
  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'Satoshi',
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF374151),
      letterSpacing: 0.1,
    ),
  );

  Widget _emailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: const TextStyle(
        fontFamily: 'Satoshi',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _textDark,
      ),
      decoration: _inputDecoration(
        hint: 'you@example.com',
        icon: Icons.mail_outline_rounded,
      ),
      validator: (value) {
        final email = value?.trim() ?? '';
        if (email.isEmpty) return 'Enter your email address';
        if (!AuthValidators.isValidEmail(email)) {
          return 'Enter a valid email address';
        }
        return null;
      },
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(
        fontFamily: 'Satoshi',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _textDark,
      ),
      decoration: _inputDecoration(
        hint: 'Enter your password',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: _textMuted,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) {
        if ((value?.trim() ?? '').isEmpty) return 'Enter your password';
        return null;
      },
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'Satoshi',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Color(0xFF9CA3AF),
      ),
      prefixIcon: Icon(icon, color: _textMuted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
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
      errorStyle: const TextStyle(
        fontFamily: 'Satoshi',
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _forgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: () {
          // TODO: hook up forgot password screen
        },
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            'Forgot Password?',
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error,
              style: const TextStyle(
                fontFamily: 'Satoshi',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── BUTTONS ───────────────────────────────────────────────────
  Widget _signInButton() {
    final disabled = _loading || _googleLoading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: disabled
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : const [_primary, _primaryDeep],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled
                ? []
                : [
                    BoxShadow(
                      color: _primary.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled ? null : _login,
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Sign In',
                          style: TextStyle(
                            fontFamily: 'Satoshi',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: [
        Expanded(
          child: Container(height: 1, color: Colors.black.withOpacity(0.08)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR CONTINUE WITH',
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black.withOpacity(0.4),
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Container(height: 1, color: Colors.black.withOpacity(0.08)),
        ),
      ],
    );
  }

  Widget _googleButton() {
    final disabled = _loading || _googleLoading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : _googleLogin,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _googleLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _googleLogo(),
                const SizedBox(width: 12),
                Text(
                  _googleLoading ? 'Connecting...' : 'Continue with Google',
                  style: const TextStyle(
                    fontFamily: 'Satoshi',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleLogo() {
    // Multi-color "G" using ShaderMask — no asset needed
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF4285F4), // Google blue
          Color(0xFF34A853), // green
          Color(0xFFFBBC05), // yellow
          Color(0xFFEA4335), // red
        ],
      ).createShader(bounds),
      child: const Text(
        'G',
        style: TextStyle(
          fontFamily: 'Satoshi',
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }

  // ─── SIGN UP LINK ──────────────────────────────────────────────
  Widget _buildSignUpLink() {
    final disabled = _loading || _googleLoading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(
            fontFamily: 'Satoshi',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black.withOpacity(0.6),
          ),
        ),
        GestureDetector(
          onTap: disabled
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
          child: const Text(
            'Sign Up',
            style: TextStyle(
              fontFamily: 'Satoshi',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _primary,
            ),
          ),
        ),
      ],
    );
  }
}
