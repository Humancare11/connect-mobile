import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import '../utils/patient_profile.dart';

/// "Complete your details": date of birth and gender, asked after login and
/// before payment when the profile lacks either (the website's step). It is
/// opened on top of the booking screen, so nothing chosen there is lost.
/// Pops `true` once saved; back pops without a result.
class CompleteDetailsScreen extends StatefulWidget {
  const CompleteDetailsScreen({
    super.key,
    this.initialDob = '',
    this.initialGender = '',
    this.authService,
  });

  /// What the profile already has; an unusable value is not pre-filled.
  final String initialDob;
  final String initialGender;

  /// Replaced in tests.
  final AuthService? authService;

  /// Opens the step. True when the details were saved.
  static Future<bool> open(
    BuildContext context, {
    String dob = '',
    String gender = '',
    AuthService? authService,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CompleteDetailsScreen(
          initialDob: dob,
          initialGender: gender,
          authService: authService,
        ),
      ),
    );
    return saved == true;
  }

  @override
  State<CompleteDetailsScreen> createState() => _CompleteDetailsScreenState();
}

class _CompleteDetailsScreenState extends State<CompleteDetailsScreen> {
  late final AuthService _authService = widget.authService ?? AuthService();

  String _dob = '';
  String _gender = '';
  String _dobError = '';
  String _genderError = '';
  String _saveError = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final dob = widget.initialDob.trim();
    final gender = widget.initialGender.trim();
    if (AuthValidators.dobError(dob).isEmpty) _dob = dob;
    if (kGenderOptions.contains(gender)) _gender = gender;
  }

  Future<void> _pickDob() async {
    final lastDate = DateTime.parse(AuthValidators.todayInIndia());
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dob) ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dob = picked.toIso8601String().substring(0, 10);
      _dobError = '';
    });
  }

  Future<void> _save() async {
    final dobError = AuthValidators.dobError(_dob);
    final genderError = kGenderOptions.contains(_gender)
        ? ''
        : 'Please select a gender.';
    setState(() {
      _dobError = dobError;
      _genderError = genderError;
      _saveError = '';
    });
    if (dobError.isNotEmpty || genderError.isNotEmpty) return;

    setState(() => _saving = true);
    final result = await _authService.savePatientDetails(
      dob: _dob,
      gender: _gender,
    );
    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _saveError = result.message.isNotEmpty
          ? result.message
          : 'Could not save your details. Please try again.';
    });
  }

  // "1990-05-01" shown as 1-5-1990, like the profile screen.
  String get _dobLabel {
    final date = DateTime.tryParse(_dob);
    if (date == null) return 'Select date of birth';
    return '${date.day}-${date.month}-${date.year}';
  }

  Widget _label(String text) => Text(
    text,
    style: AppType.body(
      size: 14,
      weight: FontWeight.w800,
    ).copyWith(color: AppColors.textPrimary),
  );

  Widget _error(String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: AppType.body(size: 13).copyWith(color: AppColors.coralInk),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Not while the save is on its way.
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Complete your details'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'We need this once, for your safety. '
                "Next time we won't ask again.",
                style: AppType.body(
                  size: 14,
                ).copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              _label('Date of Birth *'),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('details dob'),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: _saving ? null : _pickDob,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dobLabel,
                          style: AppType.body(size: 14, weight: FontWeight.w600)
                              .copyWith(
                                color: _dob.isEmpty
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
                        ),
                      ),
                      const Icon(Icons.calendar_today_outlined, size: 18),
                    ],
                  ),
                ),
              ),
              if (_dobError.isNotEmpty) _error(_dobError),
              const SizedBox(height: 20),
              _label('Gender *'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final option in kGenderOptions)
                    ChoiceChip(
                      label: Text(option),
                      selected: _gender == option,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _gender = option;
                              _genderError = '';
                            }),
                    ),
                ],
              ),
              if (_genderError.isNotEmpty) _error(_genderError),
              if (_saveError.isNotEmpty) _error(_saveError),
              const SizedBox(height: 28),
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Save & Continue to Payment →',
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
}
