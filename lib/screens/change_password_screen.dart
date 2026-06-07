import 'package:flutter/material.dart';
import '../services/api_client.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final api = ApiClient();
    final res = await api.post('/auth/change-password', {
      'oldPassword': _oldCtrl.text.trim(),
      'newPassword': _newCtrl.text.trim(),
    });
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
  }

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: _oldCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
              const SizedBox(height: 12),
              TextFormField(controller: _newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: _loading ? null : _change, child: const Text('Update Password')),
            ],
          ),
        ),
      ),
    );
  }
}
