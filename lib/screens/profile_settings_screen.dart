import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import '../services/token_storage_service.dart';
import '../widgets/email_verification_dialog.dart';
import '../widgets/geo_field_style.dart';
import '../widgets/geo_phone_controller.dart';
import '../widgets/location_selects.dart';
import '../widgets/phone_field.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _authService = AuthService();
  final _tokenStorage = const TokenStorageService();

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);
  // Error banner accent (kept distinct from the brand colour on purpose).
  static const Color _errorBg = Color(0xFFFEF2F2);
  static const Color _errorBorder = Color(0xFFFCA5A5);
  static const Color _errorText = Color(0xFFDC2626);

  bool loadingProfile = true;
  bool saving = false;
  bool saved = false;
  // Tracks the background fetchCurrentProfile() call that confirms/refreshes
  // whatever was shown immediately from the local cache. Previously this had
  // no visible signal at all: if it failed, the screen silently kept
  // whatever was cached forever with no indication it might be stale.
  bool syncingProfile = false;
  String profileSyncError = '';

  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  String gender = "";
  DateTime? dob;
  String userId = '';
  String role = 'patient';
  String location = '';
  // "ip" while the saved location is only the backend's IP-based estimate
  // from sign-up (becomes "user" once the user saves their own).
  String locationSource = '';
  // True once the server copy of the profile has loaded. Until then the form
  // may hold an empty/stale cache, so a save must not blank optional fields.
  bool remoteLoaded = false;

  // Country / State / City / Phone — the same controller and widgets as
  // sign-up. Everything is optional here (a phone, once set, can be replaced
  // but not removed), so nothing blocks saving the other fields.
  final _formKey = GlobalKey<FormState>();
  final _geo = GeoPhoneController(
    requireLocation: false,
    requireMobile: false,
    defaultToIndia: false,
  );

  Map<String, String> originalData = {
    'userId': '',
    'name': '',
    'email': '',
    'role': 'patient',
    'mobile': '',
    'dob': '',
    'gender': '',
    'country': '',
    'state': '',
    'city': '',
    'location': '',
  };

  @override
  void initState() {
    super.initState();
    _geo.loadCountries();
    _loadUserProfile();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    _geo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final age = _getAge();

    if (loadingProfile) {
      return Scaffold(
        backgroundColor: _bgCanvas,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (profileSyncError.isNotEmpty) _profileSyncErrorBanner(),
            if (syncingProfile) _syncingProfileNotice(),
            _avatarCard(age),
            const SizedBox(height: 16),
            _formCard(),
          ],
        ),
      ),
    );
  }

  Widget _syncingProfileNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Syncing your latest details…',
            style: AppType.body(
              size: 12,
            ).copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _profileSyncErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _errorBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: _errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _errorText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              profileSyncError,
              style: AppType.body(
                size: 13,
                weight: FontWeight.w600,
              ).copyWith(color: _errorText),
            ),
          ),
          TextButton(
            onPressed: _loadUserProfile,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _avatarCard(int? age) {
    final initial = nameCtrl.text.trim().isNotEmpty
        ? nameCtrl.text.trim()[0].toUpperCase()
        : "U";

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppType.display(size: 34, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(nameCtrl.text, style: AppType.display(size: 18)),
          const SizedBox(height: 4),
          Text(
            emailCtrl.text,
            textAlign: TextAlign.center,
            style: AppType.body(
              size: 13,
            ).copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              role.trim().isNotEmpty ? role.toUpperCase() : 'PATIENT',
              style: AppType.body(
                size: 11,
                weight: FontWeight.w900,
              ).copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 18),
          if (userId.isNotEmpty) _metaRow("🆔", "Patient ID", userId),
          if (gender.isNotEmpty) _metaRow("👤", "Gender", gender),
          if (age != null) _metaRow("🎂", "Age", "$age years old"),
          if ((originalData['mobile'] ?? '').isNotEmpty)
            _metaRow("📞", "Mobile", originalData['mobile']!),
          if ((originalData['country'] ?? '').isNotEmpty)
            _metaRow("🌍", "Country", originalData['country']!),
        ],
      ),
    );
  }

  Widget _metaRow(String icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppType.body(
                    size: 10,
                    weight: FontWeight.w900,
                  ).copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppType.body(
                    size: 13.5,
                    weight: FontWeight.w700,
                  ).copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      decoration: _cardDecoration(),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Personal Information",
                          style: AppType.display(size: 18),
                        ),
                        Text(
                          "Update your details below and save",
                          style: AppType.body(
                            size: 13,
                          ).copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (saved)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  "✅ Profile updated successfully!",
                  style: AppType.body(
                    size: 14,
                    weight: FontWeight.w800,
                  ).copyWith(color: AppColors.primary),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _field(
                    label: "Full Name *",
                    icon: "👤",
                    controller: nameCtrl,
                    hint: "Your full name",
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: "Email Address *",
                    icon: "✉️",
                    controller: emailCtrl,
                    hint: "you@email.com",
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  PhoneField(controller: _geo, style: GeoFieldStyle.profile),
                  const SizedBox(height: 14),
                  _genderField(),
                  const SizedBox(height: 14),
                  _dobField(),
                  const SizedBox(height: 14),
                  _locationFields(),
                  const SizedBox(height: 22),
                  _actions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String icon,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: AppType.body(size: 14).copyWith(color: AppColors.textPrimary),
          onChanged: (_) => setState(() => saved = false),
          decoration: _inputDecoration(icon: icon, hint: hint),
        ),
      ],
    );
  }

  Widget _genderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label("Gender (optional)"),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: gender,
          style: AppType.body(size: 14).copyWith(color: AppColors.textPrimary),
          items: const [
            DropdownMenuItem(value: "", child: Text("Select gender")),
            DropdownMenuItem(value: "Male", child: Text("Male")),
            DropdownMenuItem(value: "Female", child: Text("Female")),
            DropdownMenuItem(value: "Other", child: Text("Other")),
          ],
          onChanged: (v) {
            setState(() {
              gender = v ?? "";
              saved = false;
            });
          },
          decoration: _inputDecoration(icon: "⚧", hint: "Select gender"),
        ),
      ],
    );
  }

  Widget _dobField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label("Date of Birth (optional)"),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: _pickDob,
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
                    dob == null
                        ? "Select date of birth"
                        : "${dob!.day}-${dob!.month}-${dob!.year}",
                    style: AppType.body(size: 14, weight: FontWeight.w600)
                        .copyWith(
                          color: dob == null
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                  ),
                ),
                if (dob != null)
                  InkWell(
                    onTap: () => setState(() {
                      dob = null;
                      saved = false;
                    }),
                    child: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Country → State / Province → City (same lists as the web profile) ──
  Widget _locationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shown while no country is saved (a sign-up through an old app
        // build, or someone who cleared it).
        ListenableBuilder(
          listenable: _geo,
          builder: (context, _) {
            if (_geo.hasCountry) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberTint,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📍', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Please add your location',
                          style: AppType.body(
                            size: 13,
                            weight: FontWeight.w800,
                          ).copyWith(color: AppColors.amberInk),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose your country, state and city, then tap Save Changes.',
                          style: AppType.body(
                            size: 12,
                          ).copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        LocationSelects(controller: _geo, style: GeoFieldStyle.profile),
        if (locationSource == 'ip') ...[
          const SizedBox(height: 8),
          Text(
            "📍 We estimated your location from your internet connection. "
            "Please confirm or correct it.",
            style: AppType.body(
              size: 12,
            ).copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text("Reset"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(
              saving
                  ? "Saving..."
                  : saved
                  ? "Saved!"
                  : "Save Changes",
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: AppType.body(
        size: 11,
        weight: FontWeight.w900,
      ).copyWith(color: AppColors.textSecondary),
    );
  }

  InputDecoration _inputDecoration({
    required String icon,
    required String hint,
  }) {
    return InputDecoration(
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Center(
          widthFactor: 1,
          child: Text(icon, style: const TextStyle(fontSize: 16)),
        ),
      ),
      hintText: hint,
      hintStyle: AppType.body(
        size: 14,
      ).copyWith(color: AppColors.textSecondary),
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
    );
  }

  void _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        dob = picked;
        saved = false;
      });
    }
  }

  void _reset() {
    setState(() {
      userId = originalData['userId'] ?? '';
      nameCtrl.text = originalData['name'] ?? '';
      emailCtrl.text = originalData['email'] ?? '';
      role = originalData['role'] ?? 'patient';
      gender = originalData['gender'] ?? '';
      location = originalData['location'] ?? '';
      dob = _parseDob(originalData['dob'] ?? '');
      saved = false;
    });
    _geo.loadFromProfile(
      country: originalData['country'] ?? '',
      stateValue: originalData['state'] ?? '',
      cityValue: originalData['city'] ?? '',
      mobile: originalData['mobile'] ?? '',
    );
  }

  void _save() async {
    final trimmedName = nameCtrl.text.trim();
    final trimmedEmail = emailCtrl.text.trim();

    if (trimmedName.isEmpty || trimmedEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Name and email are required")),
      );
      return;
    }

    if (!AuthValidators.isValidEmail(trimmedEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address')),
      );
      return;
    }

    // Changing the account email is gated behind an OTP sent to the user's
    // current, already-verified address. The verification dialog returns true
    // only once the correct code has been entered; a cancel leaves the form
    // untouched so the user can retry.
    final currentEmail = (originalData['email'] ?? '').trim();
    final emailChanged =
        trimmedEmail.toLowerCase() != currentEmail.toLowerCase();

    if (emailChanged) {
      if (currentEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not verify your current email. Please try again later.',
            ),
          ),
        );
        return;
      }

      final verified = await showEmailVerificationDialog(
        context: context,
        currentEmail: currentEmail,
        newEmail: trimmedEmail,
        authService: _authService,
      );

      if (!mounted || !verified) return;
    }

    // Phone: once set it can't be blanked, and a changed number must be valid.
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _geo.firstError ?? 'Please check the highlighted fields.',
          ),
        ),
      );
      return;
    }

    setState(() => saving = true);

    final updateResult = await _authService.updateProfile(
      userId: userId,
      name: trimmedName,
      email: trimmedEmail,
      role: role,
      mobile: _geo.mobileForSubmit,
      dob: _formatDob(dob),
      gender: gender,
      country: _geo.countryName.trim(),
      state: _geo.state.trim(),
      city: _geo.city,
      location: location,
      sendEmptyOptionals: remoteLoaded,
    );

    if (!mounted) return;

    if (!updateResult.success || updateResult.data == null) {
      setState(() {
        saving = false;
        saved = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updateResult.message.isNotEmpty
                ? updateResult.message
                : 'Unable to save profile to server.',
          ),
        ),
      );
      return;
    }

    final profile = updateResult.data!;
    await _tokenStorage.saveUserProfile(
      userId: profile['userId'] ?? userId,
      name: profile['name'] ?? trimmedName,
      email: profile['email'] ?? trimmedEmail,
      role: profile['role'] ?? role,
      mobile: profile['mobile'] ?? _geo.mobileForSubmit,
      dob: profile['dob'] ?? _formatDob(dob),
      gender: profile['gender'] ?? gender,
      country: profile['country'] ?? _geo.countryName.trim(),
      state: profile['state'] ?? _geo.state.trim(),
      city: profile['city'] ?? _geo.city,
      location: profile['location'] ?? location,
    );

    if (!mounted) return;

    _applyProfile(profile);

    setState(() {
      saving = false;
      saved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile updated successfully!")),
    );
  }

  Future<void> _loadUserProfile() async {
    final profile = await _tokenStorage.getUserProfile();

    if (!mounted) return;

    setState(() {
      _applyProfile(profile);
      loadingProfile = false;
      syncingProfile = true;
      profileSyncError = '';
    });

    final remoteResult = await _authService.fetchCurrentProfile(silent: true);

    if (!mounted) return;

    if (!remoteResult.success || remoteResult.data == null) {
      setState(() {
        syncingProfile = false;
        // Only worth surfacing if there was nothing cached to fall back on
        // — otherwise this fires on every load for a user who is simply
        // offline, which would be noisy rather than useful.
        profileSyncError = profile.values.every((v) => v.trim().isEmpty)
            ? 'Could not load your profile. Pull to refresh or try again.'
            : '';
      });
      return;
    }

    final remoteProfile = remoteResult.data!;
    await _tokenStorage.saveUserProfile(
      userId: remoteProfile['userId'] ?? userId,
      name: remoteProfile['name'] ?? nameCtrl.text,
      email: remoteProfile['email'] ?? emailCtrl.text,
      role: remoteProfile['role'] ?? role,
      mobile: remoteProfile['mobile'] ?? _geo.mobileForSubmit,
      dob: remoteProfile['dob'] ?? _formatDob(dob),
      gender: remoteProfile['gender'] ?? gender,
      country: remoteProfile['country'] ?? _geo.countryName,
      state: remoteProfile['state'] ?? _geo.state,
      city: remoteProfile['city'] ?? _geo.city,
      location: remoteProfile['location'] ?? location,
    );

    setState(() {
      _applyProfile(remoteProfile);
      remoteLoaded = true;
      syncingProfile = false;
      profileSyncError = '';
    });
  }

  void _applyProfile(Map<String, String> profile) {
    userId = profile['userId'] ?? '';
    nameCtrl.text = profile['name'] ?? '';
    emailCtrl.text = profile['email'] ?? '';
    role = (profile['role']?.trim().isNotEmpty ?? false)
        ? profile['role']!
        : 'patient';
    gender = profile['gender'] ?? '';
    location = profile['location'] ?? '';
    if (profile.containsKey('locationSource')) {
      locationSource = profile['locationSource'] ?? '';
    }
    dob = _parseDob(profile['dob'] ?? '');

    originalData = {
      'userId': userId,
      'name': nameCtrl.text,
      'email': emailCtrl.text,
      'role': role,
      'mobile': profile['mobile'] ?? '',
      'dob': _formatDob(dob),
      'gender': gender,
      'country': profile['country'] ?? '',
      'state': profile['state'] ?? '',
      'city': profile['city'] ?? '',
      'location': location,
    };
    _geo.loadFromProfile(
      country: originalData['country']!,
      stateValue: originalData['state']!,
      cityValue: originalData['city']!,
      mobile: originalData['mobile']!,
    );
  }

  DateTime? _parseDob(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) return parsed;

    final dateOnly = trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
    return DateTime.tryParse(dateOnly);
  }

  String _formatDob(DateTime? value) {
    if (value == null) return '';

    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  int? _getAge() {
    if (dob == null) return null;

    final today = DateTime.now();
    int age = today.year - dob!.year;

    if (today.month < dob!.month ||
        (today.month == dob!.month && today.day < dob!.day)) {
      age--;
    }

    return age;
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border, width: 1.2),
      boxShadow: AppShadows.subtle,
    );
  }
}
