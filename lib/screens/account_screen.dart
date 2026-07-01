import 'package:flutter/material.dart';

import 'profile_settings_screen.dart';
import 'my_records_screen.dart';
import 'raise_ticket_screen.dart';
import 'change_password_screen.dart';
import 'faq_screen.dart';

// Central palette so the "premium dark blue" theme stays consistent
// everywhere. Tweak these two values to shift the whole screen's tone.
class _Palette {
  static const Color darkBlue = Color(0xff0B2545);
  static const Color darkBlueSoft = Color(0xff13355E);
  static const Color background = Color(0xffF5F7FB);
  static const Color card = Colors.white;
  static const Color iconBg = Color(0xffEAF0FA);
  static const Color subtitle = Color(0xff6B7686);
  static const Color divider = Color(0xffE7EBF2);
  static const Color danger = Color(0xffC0392B);
  static const Color dangerBg = Color(0xffFCEDEC);
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Are you sure you want to log out of your account?'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: _Palette.subtitle)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _Palette.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // TODO: hook this up to your actual auth / session logic.
      // e.g. AuthService.instance.logout();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountOptions = <_AccountOption>[
      _AccountOption(
        icon: Icons.folder_shared_outlined,
        title: 'My Records',
        subtitle: 'View your medical records',
        builder: (_) => const MyRecordsPage(),
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

    final supportOptions = <_AccountOption>[
      _AccountOption(
        icon: Icons.confirmation_number_outlined,
        title: 'Raise a Ticket',
        subtitle: 'Report an issue or ask for help',
        builder: (_) => const RaiseTicketPage(),
      ),
      _AccountOption(
        icon: Icons.help_outline,
        title: 'FAQs',
        subtitle: 'Answers to common questions',
        builder: (_) => const FaqScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: _Palette.background,
      appBar: AppBar(
        title: const Text(
          'Account',
          style: TextStyle(fontWeight: FontWeight.w800, color: _Palette.darkBlue),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _Palette.darkBlue,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _SectionLabel('GENERAL'),
            const SizedBox(height: 10),
            _OptionGroup(options: accountOptions),

            const SizedBox(height: 24),
            _SectionLabel('SUPPORT'),
            const SizedBox(height: 10),
            _OptionGroup(options: supportOptions),

            const SizedBox(height: 28),
            _LogoutTile(onTap: () => _confirmLogout(context)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: _Palette.subtitle,
        ),
      ),
    );
  }
}

/// Groups a list of options into a single premium-looking rounded card,
/// with thin dividers between rows instead of separate floating cards.
class _OptionGroup extends StatelessWidget {
  final List<_AccountOption> options;
  const _OptionGroup({required this.options});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _Palette.darkBlue.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: List.generate(options.length, (index) {
          final option = options[index];
          final isLast = index == options.length - 1;

          return Column(
            children: [
              _AccountTile(option: option),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, thickness: 1, color: _Palette.divider),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final _AccountOption option;
  const _AccountTile({required this.option});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: option.builder));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: _Palette.iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(option.icon, color: _Palette.darkBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff1B1F27),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.subtitle,
                      style: const TextStyle(fontSize: 12.5, color: _Palette.subtitle),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xffB7C0CE)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Palette.dangerBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: _Palette.danger, size: 20),
              SizedBox(width: 10),
              Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: _Palette.danger,
                ),
              ),
            ],
          ),
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