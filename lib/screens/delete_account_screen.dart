import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/auth_service.dart';

/// Lets a signed-in patient submit an account-deletion request.
///
/// Submitting this form sends the request to the backend, where it sits
/// pending in the Super Admin panel until an admin approves it — the
/// account is not deleted immediately. This satisfies Google Play's
/// account-deletion policy (which explicitly allows a request-based
/// process, not only instant in-app deletion).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, this.authService});

  final AuthService? authService;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const Color _danger = Color(0xFFC0392B);
  static const Color _dangerBg = Color(0xFFFCEDEC);
  static final Uri _supportEmailUri = Uri(
    scheme: 'mailto',
    path: 'support@humancareconnect.co',
    query: 'subject=Account%20Deletion%20Request',
  );

  late final AuthService _authService = widget.authService ?? AuthService();

  final _reasonCtrl = TextEditingController();
  bool _acknowledged = false;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_acknowledged || _submitting) return;

    setState(() => _submitting = true);

    final reason = _reasonCtrl.text.trim();

    final result = await _authService.requestAccountDeletion(reason: reason);

    if (!mounted) return;

    setState(() => _submitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isNotEmpty
                ? result.message
                : 'Unable to submit your request right now. Please try '
                      'again, or email support directly.',
          ),
        ),
      );
      return;
    }

    setState(() => _submitted = true);
  }

  Future<void> _emailSupport() async {
    final launched = await launchUrl(_supportEmailUri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open your email app right now.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Delete Account',
          style: AppType.body(size: 18, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: _submitted ? _buildSubmitted() : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _dangerBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: _danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Deleting your account is permanent. Once processed, you '
                  'will lose access to your appointment history, medical '
                  'records, and any saved details in this app.',
                  style: AppType.body(size: 13.5, height: 1.4)
                      .copyWith(color: _danger),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'What happens next',
          style: AppType.body(size: 14, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        _bullet(
          'Submitting this form sends a deletion request to our support '
          'team — it is not instant.',
        ),
        _bullet(
          'We will delete your personal data, except where we are '
          'required to retain records (e.g. medical or billing history) '
          'to comply with the law.',
        ),
        _bullet('You will receive a confirmation email once it is complete.'),
        const SizedBox(height: 24),
        Text(
          'Reason (optional)',
          style: AppType.body(size: 13, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonCtrl,
          maxLines: 4,
          maxLength: 500,
          style: AppType.body(size: 14).copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: "Let us know why you're leaving — it helps us improve.",
            hintStyle: AppType.body(size: 14).copyWith(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _acknowledged = !_acknowledged),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acknowledged,
                  activeColor: _danger,
                  onChanged: (value) =>
                      setState(() => _acknowledged = value ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'I understand this action is permanent and I want to '
                      'request deletion of my account and data.',
                      style: AppType.body(size: 13.5)
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _acknowledged && !_submitting ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              disabledBackgroundColor: _danger.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever_rounded),
            label: Text(
              _submitting ? 'Submitting...' : 'Submit Deletion Request',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _emailSupport,
            child: Text(
              'Prefer email? Contact support@humancareconnect.co',
              style: AppType.body(size: 12.5, weight: FontWeight.w700)
                  .copyWith(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitted() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Request submitted',
              textAlign: TextAlign.center,
              style: AppType.body(size: 18, weight: FontWeight.w800)
                  .copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              "We've received your account deletion request. Our support "
              "team will process it and email you a confirmation once your "
              "account and data have been deleted.",
              textAlign: TextAlign.center,
              style: AppType.body(size: 13.5, height: 1.4)
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppType.body(size: 13, height: 1.4)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
