import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  bool _loading = false;

  final _auth = AuthService();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final api = ApiClient();
    final res = await api.post('/auth/update-profile', {
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'mobile': _mobileCtrl.text.trim(),
    });
    setState(() => _loading = false);
    final msg = res.message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              TextFormField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextFormField(controller: _mobileCtrl, decoration: const InputDecoration(labelText: 'Mobile')),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _loading ? null : _save, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}
