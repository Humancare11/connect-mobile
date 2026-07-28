import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
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

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);

  Future<void> _submit() async {
    if (_loading) return;
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
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'Update your password',
                style: AppType.display(size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a strong password you have not used before.',
                style: AppType.body(size: 14)
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _currentCtrl,
                obscureText: !_showCurrent,
                style: AppType.body(size: 14)
                    .copyWith(color: AppColors.textPrimary),
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
                style: AppType.body(size: 14)
                    .copyWith(color: AppColors.textPrimary),
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
                style: AppType.body(size: 14)
                    .copyWith(color: AppColors.textPrimary),
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
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
                      : Text(
                          'Update Password',
                          style: AppType.body(size: 15, weight: FontWeight.w800)
                              .copyWith(color: Colors.white),
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
      labelStyle: AppType.body(size: 14)
          .copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          visible ? Icons.visibility_off : Icons.visibility,
          color: AppColors.textSecondary,
        ),
        onPressed: onToggle,
      ),
    );
  }
}