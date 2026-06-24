import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/auth_validators.dart';
import '../services/token_storage_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _authService = AuthService();
  final _tokenStorage = const TokenStorageService();

  bool loadingProfile = true;
  bool saving = false;
  bool saved = false;

  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final mobileCtrl = TextEditingController();
  final countryCtrl = TextEditingController();

  String gender = "";
  DateTime? dob;
  String userId = '';
  String role = 'patient';
  String state = '';
  String city = '';
  String location = '';

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
    _loadUserProfile();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    mobileCtrl.dispose();
    countryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final age = _getAge();

    if (loadingProfile) {
      return const Scaffold(
        backgroundColor: Color(0xfff6f8fb),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [_avatarCard(age), const SizedBox(height: 16), _formCard()],
        ),
      ),
    );
  }

  Widget _avatarCard(int? age) {
    final initial = nameCtrl.text.trim().isNotEmpty
        ? nameCtrl.text.trim()[0].toUpperCase()
        : "U";

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _glassBox(),
      child: Column(
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xffeaf2ff),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xffbfdbfe)),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xff1d4ed8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            nameCtrl.text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            emailCtrl.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xffeaf2ff),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              role.trim().isNotEmpty ? role.toUpperCase() : 'PATIENT',
              style: const TextStyle(
                color: Color(0xff1d4ed8),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (userId.isNotEmpty) _metaRow("🆔", "Patient ID", userId),
          if (gender.isNotEmpty) _metaRow("👤", "Gender", gender),
          if (age != null) _metaRow("🎂", "Age", "$age years old"),
          if (mobileCtrl.text.isNotEmpty)
            _metaRow("📞", "Mobile", mobileCtrl.text),
          if (countryCtrl.text.isNotEmpty)
            _metaRow("🌍", "Country", countryCtrl.text),
        ],
      ),
    );
  }

  Widget _metaRow(String icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white),
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
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
      decoration: _glassBox(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: const [
                CircleAvatar(
                  backgroundColor: Color(0xffeaf2ff),
                  child: Icon(Icons.person_outline, color: Color(0xff1d4ed8)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Personal Information",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        "Update your details below and save",
                        style: TextStyle(color: Colors.black54),
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
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "✅ Profile updated successfully!",
                style: TextStyle(
                  color: Color(0xff1d4ed8),
                  fontWeight: FontWeight.w800,
                ),
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
                _field(
                  label: "Mobile Number",
                  icon: "📞",
                  controller: mobileCtrl,
                  hint: "+91 98765 43210",
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                _genderField(),
                const SizedBox(height: 14),
                _dobField(),
                const SizedBox(height: 14),
                _field(
                  label: "Country",
                  icon: "🌍",
                  controller: countryCtrl,
                  hint: "e.g. India, USA",
                ),
                const SizedBox(height: 22),
                _actions(),
              ],
            ),
          ),
        ],
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
        _label("Gender"),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: gender.isEmpty ? null : gender,
          items: const [
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
        _label("Date of Birth"),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickDob,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              dob == null
                  ? "Select date of birth"
                  : "${dob!.day}-${dob!.month}-${dob!.year}",
              style: TextStyle(
                color: dob == null ? Colors.black45 : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
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
              backgroundColor: const Color(0xff1d4ed8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
      style: const TextStyle(
        color: Colors.black54,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
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
      filled: true,
      fillColor: Colors.white.withOpacity(0.65),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xff1d4ed8), width: 1.5),
      ),
    );
  }

  void _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
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
      mobileCtrl.text = originalData['mobile'] ?? '';
      gender = originalData['gender'] ?? '';
      countryCtrl.text = originalData['country'] ?? '';
      state = originalData['state'] ?? '';
      city = originalData['city'] ?? '';
      location = originalData['location'] ?? '';
      dob = _parseDob(originalData['dob'] ?? '');
      saved = false;
    });
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

    setState(() => saving = true);

    final updateResult = await _authService.updateProfile(
      userId: userId,
      name: trimmedName,
      email: trimmedEmail,
      role: role,
      mobile: mobileCtrl.text.trim(),
      dob: _formatDob(dob),
      gender: gender,
      country: countryCtrl.text.trim(),
      state: state,
      city: city,
      location: location,
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
      mobile: profile['mobile'] ?? mobileCtrl.text.trim(),
      dob: profile['dob'] ?? _formatDob(dob),
      gender: profile['gender'] ?? gender,
      country: profile['country'] ?? countryCtrl.text.trim(),
      state: profile['state'] ?? state,
      city: profile['city'] ?? city,
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
    });

    final remoteResult = await _authService.fetchCurrentProfile();

    if (!mounted || !remoteResult.success || remoteResult.data == null) return;

    final remoteProfile = remoteResult.data!;
    await _tokenStorage.saveUserProfile(
      userId: remoteProfile['userId'] ?? userId,
      name: remoteProfile['name'] ?? nameCtrl.text,
      email: remoteProfile['email'] ?? emailCtrl.text,
      role: remoteProfile['role'] ?? role,
      mobile: remoteProfile['mobile'] ?? mobileCtrl.text,
      dob: remoteProfile['dob'] ?? _formatDob(dob),
      gender: remoteProfile['gender'] ?? gender,
      country: remoteProfile['country'] ?? countryCtrl.text,
      state: remoteProfile['state'] ?? state,
      city: remoteProfile['city'] ?? city,
      location: remoteProfile['location'] ?? location,
    );

    setState(() {
      _applyProfile(remoteProfile);
    });
  }

  void _applyProfile(Map<String, String> profile) {
    userId = profile['userId'] ?? '';
    nameCtrl.text = profile['name'] ?? '';
    emailCtrl.text = profile['email'] ?? '';
    role = (profile['role']?.trim().isNotEmpty ?? false)
        ? profile['role']!
        : 'patient';
    mobileCtrl.text = profile['mobile'] ?? '';
    gender = profile['gender'] ?? '';
    countryCtrl.text = profile['country'] ?? '';
    state = profile['state'] ?? '';
    city = profile['city'] ?? '';
    location = profile['location'] ?? '';
    dob = _parseDob(profile['dob'] ?? '');

    originalData = {
      'userId': userId,
      'name': nameCtrl.text,
      'email': emailCtrl.text,
      'role': role,
      'mobile': mobileCtrl.text,
      'dob': _formatDob(dob),
      'gender': gender,
      'country': countryCtrl.text,
      'state': state,
      'city': city,
      'location': location,
    };
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

  BoxDecoration _glassBox() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.75),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.withOpacity(0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
