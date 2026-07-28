import 'package:flutter/material.dart';

import '../config/app_design_system.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);

  static const List<_Faq> _faqs = [
    _Faq(
      'How do I view my medical records?',
      'Go to Account > My Records. All your past reports, prescriptions, '
          'and visit history are available there and can be downloaded '
          'as PDFs.',
    ),
    _Faq(
      'How do I reset or change my password?',
      'Go to Account > Change Password. You\'ll need to enter your current '
          'password once, followed by your new password.',
    ),
    _Faq(
      'How can I update my profile details?',
      'Go to Account > Edit Profile to update your name, contact number, '
          'address, and other personal details.',
    ),
    _Faq(
      'How do I report an issue or get help?',
      'Use the "Raise a Ticket" option under Account. Describe your issue '
          'and our support team will get back to you as soon as possible.',
    ),
    _Faq(
      'Is my data safe and private?',
      'Yes. Your medical and personal data is encrypted and only accessible '
          'to you and authorized healthcare providers.',
    ),
    _Faq(
      'How do I log out of my account?',
      'Go to Account and tap "Log Out" at the bottom of the screen. '
          'You\'ll be asked to confirm before you\'re signed out.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: Text(
          'FAQs',
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'Frequently Asked Questions',
              style: AppType.display(size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              'Quick answers to the things people ask us most.',
              style: AppType.body(size: 13.5)
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border, width: 1.2),
                boxShadow: AppShadows.subtle,
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: Colors.transparent,
                ),
                child: Column(
                  children: List.generate(_faqs.length, (index) {
                    final faq = _faqs[index];
                    final isLast = index == _faqs.length - 1;

                    return Column(
                      children: [
                        _FaqTile(faq: faq),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedAlignment: Alignment.topLeft,
      iconColor: AppColors.primary,
      collapsedIconColor: AppColors.textSecondary,
      title: Text(
        faq.question,
        style: AppType.body(size: 14.5, weight: FontWeight.w700)
            .copyWith(color: AppColors.textPrimary),
      ),
      children: [
        Text(
          faq.answer,
          style: AppType.body(size: 13.5, height: 1.4)
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}