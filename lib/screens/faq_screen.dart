import 'package:flutter/material.dart';

// Keep this in sync with account_screen.dart's palette so the two
// screens feel like one cohesive, premium experience.
class _Palette {
  static const Color darkBlue = Color(0xff0B2545);
  static const Color background = Color(0xffF5F7FB);
  static const Color card = Colors.white;
  static const Color subtitle = Color(0xff6B7686);
  static const Color divider = Color(0xffE7EBF2);
}

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

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
      backgroundColor: _Palette.background,
      appBar: AppBar(
        title: const Text(
          'FAQs',
          style: TextStyle(fontWeight: FontWeight.w800, color: _Palette.darkBlue),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _Palette.darkBlue,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xff1B1F27),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quick answers to the things people ask us most.',
              style: TextStyle(fontSize: 13.5, color: _Palette.subtitle),
            ),
            const SizedBox(height: 18),
            Container(
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
                            child: Divider(height: 1, thickness: 1, color: _Palette.divider),
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
      iconColor: _Palette.darkBlue,
      collapsedIconColor: _Palette.subtitle,
      title: Text(
        faq.question,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: Color(0xff1B1F27),
        ),
      ),
      children: [
        Text(
          faq.answer,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: _Palette.subtitle,
          ),
        ),
      ],
    );
  }
}