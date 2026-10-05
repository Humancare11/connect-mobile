import 'package:flutter/material.dart';

import 'geo_field_style.dart';
import 'geo_phone_controller.dart';
import 'location_selects.dart';
import 'phone_field.dart';

/// Country, State, City and Phone in the web's order, as used on the sign-up
/// and social-completion screens.
///
/// Phones: everything stacked full-width — Country, State, City, then the
/// phone row. A State name like "Federated States of Micronesia" doesn't fit
/// half of a 360dp screen, and half-width pickers are too small a tap target.
/// Tablets (≥ [twoColumnFrom] wide) get the web's two columns instead:
/// Country | State, then City | Phone.
class GeoPhoneFields extends StatelessWidget {
  const GeoPhoneFields({
    super.key,
    required this.controller,
    this.style = GeoFieldStyle.auth,
    this.twoColumnFrom = 600,
  });

  final GeoPhoneController controller;
  final GeoFieldStyle style;
  final double twoColumnFrom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final country = CountryField(controller: controller, style: style);
        final state = StateField(controller: controller, style: style);
        final city = CityField(controller: controller, style: style);
        final phone = PhoneField(controller: controller, style: style);

        if (box.maxWidth >= twoColumnFrom) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: country),
                  const SizedBox(width: 16),
                  Expanded(child: state),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: city),
                  const SizedBox(width: 16),
                  Expanded(child: phone),
                ],
              ),
            ],
          );
        }
        return Column(
          children: [
            country,
            const SizedBox(height: 14),
            state,
            const SizedBox(height: 14),
            city,
            const SizedBox(height: 14),
            phone,
          ],
        );
      },
    );
  }
}
