import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String kConsentError =
    'Accept Terms, Privacy Policy, and HIPAA consent requirements';

const String _site = 'https://humancareconnect.co';

/// The web's three separate, required consents: Terms of Service, Privacy
/// Policy and HIPAA Consent. Only the last two are sent to the backend
/// (`privacyConsent`, `hipaaConsent`); the Terms box is client-side, exactly
/// as on the web.
class ConsentController extends ChangeNotifier {
  bool terms = false;
  bool privacy = false;
  bool hipaa = false;

  bool get allAccepted => terms && privacy && hipaa;

  void setTerms(bool v) {
    terms = v;
    notifyListeners();
  }

  void setPrivacy(bool v) {
    privacy = v;
    notifyListeners();
  }

  void setHipaa(bool v) {
    hipaa = v;
    notifyListeners();
  }

  void reset() {
    terms = privacy = hipaa = false;
    notifyListeners();
  }
}

class ConsentCheckboxes extends StatelessWidget {
  const ConsentCheckboxes({super.key, required this.controller});

  final ConsentController controller;

  static const Color _navy = Color(0xff1a3a5c);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            context,
            value: controller.terms,
            onChanged: controller.setTerms,
            lead: 'I agree to the ',
            link: 'Terms of Service',
            url: '$_site/terms-of-service',
          ),
          _row(
            context,
            value: controller.privacy,
            onChanged: controller.setPrivacy,
            lead: 'I agree to the ',
            link: 'Privacy Policy',
            url: '$_site/privacy-policy',
          ),
          _row(
            context,
            value: controller.hipaa,
            onChanged: controller.setHipaa,
            lead: 'I agree to the ',
            link: 'HIPAA Consent',
            url: '$_site/patient-informed-consent-form',
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
    required String lead,
    required String link,
    required String url,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: _navy,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(!value),
                  child: Text(
                    lead,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
                InkWell(
                  onTap: () => _open(context, url, link),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      link,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xff2563eb),
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String url, String name) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open the $name. Please try again.")),
      );
    }
  }
}
