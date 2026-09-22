import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/auth_repository.dart';
import '../services/idle_session_timer.dart';
import 'profile_settings_screen.dart';
import 'my_records_screen.dart';
import 'payment_history_screen.dart';
import 'raise_ticket_screen.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';
import 'faq_screen.dart';
import 'login_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.authRepository});

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);
  // Destructive (log out) accent — kept distinct from the brand colour.
  static const Color _danger = Color(0xFFC0392B);
  static const Color _dangerBg = Color(0xFFFCEDEC);

  static final Uri _privacyPolicyUri = Uri.parse(
    'https://humancareconnect.co/privacy-policy',
  );

  final AuthRepository? authRepository;

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final launched = await launchUrl(
      _privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the privacy policy right now.'),
        ),
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text(
          'Log out',
          style: AppType.body(size: 17, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to log out of your account?',
          style: AppType.body(size: 14).copyWith(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppType.body(size: 14)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final repository = authRepository ?? AuthRepository();

      try {
        await repository.clearSession();
        IdleSessionTimer.instance.stop();
      } catch (error, stackTrace) {
        debugPrint('Logout failed: $error');
        debugPrint('$stackTrace');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out right now. Please try again.'),
          ),
        );
        return;
      }

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
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

    final billingOptions = <_AccountOption>[
      _AccountOption(
        icon: Icons.receipt_long_outlined,
        title: 'Payment History',
        subtitle: 'View payments and download invoices',
        builder: (_) => const PaymentHistoryScreen(),
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
      _AccountOption(
        icon: Icons.privacy_tip_outlined,
        title: 'Privacy Policy',
        subtitle: 'How we handle your data',
        onTap: () => _openPrivacyPolicy(context),
      ),
    ];

    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: Text(
          'Account',
          style: AppType.body(size: 18, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const _SectionLabel('GENERAL'),
            const SizedBox(height: 10),
            _OptionGroup(options: accountOptions),

            const SizedBox(height: 24),
            const _SectionLabel('BILLING'),
            const SizedBox(height: 10),
            _OptionGroup(options: billingOptions),

            const SizedBox(height: 24),
            const _SectionLabel('SUPPORT'),
            const SizedBox(height: 10),
            _OptionGroup(options: supportOptions),

            const SizedBox(height: 24),
            const _SectionLabel('DANGER ZONE'),
            const SizedBox(height: 10),
            _DeleteAccountTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
              ),
            ),

            const SizedBox(height: 12),
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
        style: AppType.body(size: 12, weight: FontWeight.w700)
            .copyWith(color: AppColors.textSecondary, letterSpacing: 0.8),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.subtle,
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
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.border,
                  ),
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
          final onTap = option.onTap;
          if (onTap != null) {
            onTap();
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: option.builder!),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(option.icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: AppType.body(size: 15.5, weight: FontWeight.w700)
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.subtitle,
                      style: AppType.body(size: 12.5)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountTile extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteAccountTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AccountScreen._danger.withValues(alpha: 0.35)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.delete_forever_outlined,
                  color: AccountScreen._danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delete My Account',
                  style: AppType.body(size: 15.5, weight: FontWeight.w800)
                      .copyWith(color: AccountScreen._danger),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AccountScreen._danger.withValues(alpha: 0.6)),
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
      color: AccountScreen._dangerBg,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded,
                  color: AccountScreen._danger, size: 20),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: AppType.body(size: 15.5, weight: FontWeight.w800)
                    .copyWith(color: AccountScreen._danger),
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
  final WidgetBuilder? builder;
  final VoidCallback? onTap;

  const _AccountOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.builder,
    this.onTap,
  }) : assert(
         builder != null || onTap != null,
         'Provide either builder (in-app navigation) or onTap (e.g. an '
         'external link).',
       );
}