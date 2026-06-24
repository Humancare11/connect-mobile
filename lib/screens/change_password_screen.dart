import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/auth_validators.dart';

class ChangePasswordScreen extends StatefulWidget { 
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _loading = false;

  final _authService = AuthService();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    final res = await _authService.changePassword(
      currentPassword: _currentCtrl.text.trim(),
      newPassword: _newCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message)));

    if (res.success) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Update your password',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a strong password you have not used before.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                decoration: _passwordDecoration(
                  'Current password',
                  _showCurrent,
                  () => setState(() => _showCurrent = !_showCurrent),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please enter your current password'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newCtrl,
                obscureText: !_showNew,
                decoration: _passwordDecoration(
                  'New password',
                  _showNew,
                  () => setState(() => _showNew = !_showNew),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please enter a new password';
                  }

                  final newPassword = v.trim();
                  if (newPassword == _currentCtrl.text.trim()) {
                    return 'New password must be different from current password';
                  }

                  final error = AuthValidators.passwordError(newPassword);
                  if (error.isNotEmpty) {
                    return error;
                  }

                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: !_showConfirm,
                decoration: _passwordDecoration(
                  'Confirm new password',
                  _showConfirm,
                  () => setState(() => _showConfirm = !_showConfirm),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (v != _newCtrl.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff1a3a5c),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Update Password',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _passwordDecoration(
    String label,
    bool visible,
    VoidCallback onToggle,
  ) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      suffixIcon: IconButton(
        icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        onPressed: onToggle,
      ),
    );
  }
}
