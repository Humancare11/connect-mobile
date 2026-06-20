import 'package:flutter/material.dart';

import 'profile_settings_screen.dart';
import 'my_records_screen.dart';
import 'raise_ticket_screen.dart';
import 'change_password_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final options = <_AccountOption>[
      _AccountOption(
        icon: Icons.folder_shared_outlined,
        title: 'My Records',
        subtitle: 'View your medical records',
        builder: (_) => const MyRecordsPage(),
      ),
      _AccountOption(
        icon: Icons.confirmation_number_outlined,
        title: 'Raise a Ticket',
        subtitle: 'Report an issue or ask for help',
        builder: (_) => const RaiseTicketPage(),
      ),
      _AccountOption(
        icon: Icons.edit_outlined,
        title: 'Edit Profile',
        subtitle: 'Update your personal details',
        builder: (_) => const EditProfilePage(),
      ),
      _AccountOption(
        icon: Icons.lock_outline,
        title: 'Change Password',
        subtitle: 'Update your account password',
        builder: (_) => const ChangePasswordScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: options.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final option = options[index];

            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: option.builder),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xffeef2f7),
                        child: Icon(option.icon, color: const Color(0xff1a3a5c)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.subtitle,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black38),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AccountOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  const _AccountOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}
