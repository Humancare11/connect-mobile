import 'package:flutter/material.dart';

import 'geo_field_style.dart';
import 'geo_phone_controller.dart';
import 'search_picker.dart';

/// Dial-code picker + number input, bound to a [GeoPhoneController] so the
/// code stays in sync with Country (by ISO2). Defaults to India / +91.
///
/// The picker lists every country once ("🇺🇸 United States (+1)",
/// "🇨🇦 Canada (+1)"), so shared codes stay unambiguous.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.style = GeoFieldStyle.auth,
    this.label = 'Mobile Number',
  });

  final GeoPhoneController controller;
  final GeoFieldStyle style;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final options = c.dialOptions;
        final canPick =
            c.countriesStatus == LoadStatus.ready && options.isNotEmpty;
        final loading = c.countriesStatus == LoadStatus.loading;

        Future<void> pick() async {
          final labels = {for (final o in options) o.label: o.iso2};
          final picked = await showSearchPicker(
            context,
            title: 'Select country code',
            options: labels.keys.toList(),
          );
          final iso = picked == null ? null : labels[picked];
          if (iso != null) c.selectDialIso(iso);
        }

        final dialBox = Semantics(
          button: true,
          enabled: canPick,
          label: 'Country code ${c.dialCode}',
          child: InkWell(
            borderRadius: style.radius,
            onTap: canPick ? pick : null,
            child: Container(
              width: 112,
              height: style.fieldHeight,
              decoration: BoxDecoration(
                color: style.isProfile ? null : const Color(0xfff9fafb),
                borderRadius: style.radius,
                border: Border.all(
                  color: style.isProfile
                      ? const Color(0xFFE5E7EB)
                      : Colors.black.withValues(alpha: 0.09),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '${flagEmoji(c.dialIso)} ${c.dialCode}'.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.valueStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: style.accent,
                      ),
                    ),
                  ),
                  loading
                      ? const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        )
                      : Icon(
                          Icons.arrow_drop_down,
                          size: 20,
                          color: style.accent,
                        ),
                ],
              ),
            ),
          ),
        );

        final number = TextFormField(
          controller: c.numberController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [c.numberFormatter],
          style: style.valueStyle,
          validator: (_) => c.mobileError,
          decoration: style
              .decoration(
                hint: 'Mobile Number',
                prefixIcon: style.prefix(
                  icon: Icons.phone_outlined,
                  emoji: '📞',
                ),
              )
              .copyWith(
                // Same height as the dial-code box beside it.
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                isDense: true,
              ),
        );

        return style.withOutsideLabel(
          label,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              dialBox,
              const SizedBox(width: 10),
              Expanded(child: number),
            ],
          ),
        );
      },
    );
  }
}
