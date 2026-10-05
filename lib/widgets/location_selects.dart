import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geo_field_style.dart';
import 'geo_phone_controller.dart';
import 'search_picker.dart';

const String _notSet = 'Not set';

/// A tappable field that opens a searchable bottom sheet, with inline
/// validation like a text field. Used for Country and State.
class GeoPickerField extends StatelessWidget {
  const GeoPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.style,
    required this.icon,
    required this.emoji,
    required this.validator,
    this.onTap,
    this.trailing,
    this.below,
  });

  final String label;
  final String value;
  final String placeholder;
  final GeoFieldStyle style;
  final IconData icon;
  final String emoji;

  /// Null when the field can't be opened right now (loading, no options).
  final VoidCallback? onTap;
  final String? Function() validator;

  /// Replaces the dropdown arrow, e.g. a spinner while loading.
  final Widget? trailing;

  /// Shown under the box, e.g. a "Retry" button.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return style.withOutsideLabel(
      label,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Re-keyed on the value so an error from a failed submit clears the
          // moment the user picks something.
          FormField<String>(
            key: ValueKey('$label|$value|$placeholder'),
            validator: (_) => validator(),
            builder: (field) => Semantics(
              button: true,
              enabled: enabled,
              label: label,
              child: InkWell(
                borderRadius: style.radius,
                onTap: onTap,
                child: Opacity(
                  opacity: enabled || value.isNotEmpty ? 1 : 0.6,
                  child: InputDecorator(
                    isEmpty: false,
                    decoration: style.decoration(
                      label: style.isProfile ? null : label,
                      errorText: field.errorText,
                      prefixIcon: style.prefix(icon: icon, emoji: emoji),
                      suffixIcon:
                          trailing ??
                          const Icon(Icons.arrow_drop_down, size: 22),
                    ),
                    child: Text(
                      value.isEmpty ? placeholder : value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: value.isEmpty
                          ? style.placeholderStyle
                          : style.valueStyle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ?below,
        ],
      ),
    );
  }
}

class _RetryLink extends StatelessWidget {
  const _RetryLink({
    required this.text,
    required this.onPressed,
    required this.color,
  });

  final String text;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          minimumSize: const Size(48, 36),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

const Widget _spinner = Padding(
  padding: EdgeInsets.all(14),
  child: SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  ),
);

/// Country picker, from `/api/locations/countries`.
class CountryField extends StatelessWidget {
  const CountryField({
    super.key,
    required this.controller,
    this.style = GeoFieldStyle.auth,
  });

  final GeoPhoneController controller;
  final GeoFieldStyle style;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final status = c.countriesStatus;
        final loading = status == LoadStatus.loading;
        final failed = status == LoadStatus.error;
        // On the profile screen leaving Country blank is allowed, so the
        // sheet offers a "Not set" row first.
        final allowClear = !c.requireLocation;

        Future<void> open() async {
          final picked = await showSearchPicker(
            context,
            title: 'Select country',
            options: [
              if (allowClear) _notSet,
              ...c.countries.map((e) => e.name),
            ],
          );
          if (picked == null) return;
          if (picked == _notSet) {
            c.clearCountry();
            return;
          }
          for (final country in c.countries) {
            if (country.name == picked) {
              c.selectCountry(country);
              return;
            }
          }
        }

        return GeoPickerField(
          label: c.requireLocation ? 'Country' : 'Country (optional)',
          value: c.countryName,
          placeholder: loading
              ? 'Loading countries…'
              : failed
              ? 'Failed to load countries'
              : 'Select country',
          style: style,
          icon: Icons.public,
          emoji: '🌍',
          validator: () => c.countryError,
          trailing: loading ? _spinner : null,
          onTap: status == LoadStatus.ready && c.countries.isNotEmpty
              ? open
              : null,
          below: failed
              ? _RetryLink(
                  text: 'Retry',
                  color: style.accent,
                  onPressed: c.retryCountries,
                )
              : null,
        );
      },
    );
  }
}

/// State / Province picker, from `/api/locations/states/:country`. Disabled
/// with "No states available" (and not required) for a country that has none.
class StateField extends StatelessWidget {
  const StateField({
    super.key,
    required this.controller,
    this.style = GeoFieldStyle.auth,
  });

  final GeoPhoneController controller;
  final GeoFieldStyle style;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final status = c.statesStatus;
        final noCountry = !c.hasCountry || c.iso2.isEmpty;

        final String placeholder;
        if (noCountry) {
          placeholder = 'Select country first';
        } else if (status == LoadStatus.loading) {
          placeholder = 'Loading…';
        } else if (status == LoadStatus.error) {
          placeholder = 'Failed to load states';
        } else if (c.noStatesAvailable) {
          placeholder = 'No states available';
        } else {
          placeholder = 'Select state / province';
        }

        final canOpen =
            !noCountry && status == LoadStatus.ready && c.states.isNotEmpty;
        final allowClear = !c.requireLocation;

        Future<void> open() async {
          final picked = await showSearchPicker(
            context,
            title: 'Select state / province',
            options: [if (allowClear) _notSet, ...c.states],
          );
          if (picked == null) return;
          c.selectState(picked == _notSet ? '' : picked);
        }

        return GeoPickerField(
          label: c.requireLocation
              ? 'State / Province'
              : 'State / Province (optional)',
          value: c.state,
          placeholder: placeholder,
          style: style,
          icon: Icons.location_on_outlined,
          emoji: '📍',
          validator: () => c.stateError,
          trailing: status == LoadStatus.loading ? _spinner : null,
          onTap: canOpen ? open : null,
          below: status == LoadStatus.error && !noCountry
              ? _RetryLink(
                  text: 'Retry',
                  color: style.accent,
                  onPressed: c.retryStates,
                )
              : null,
        );
      },
    );
  }
}

/// City: a plain, optional text box (max 100), never a dropdown.
class CityField extends StatelessWidget {
  const CityField({
    super.key,
    required this.controller,
    this.style = GeoFieldStyle.auth,
  });

  final GeoPhoneController controller;
  final GeoFieldStyle style;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final label = c.requireLocation ? 'City' : 'City (optional)';
        return style.withOutsideLabel(
          label,
          TextFormField(
            controller: c.cityController,
            enabled: c.hasCountry,
            maxLength: 100,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: style.valueStyle,
            decoration: style.decoration(
              label: style.isProfile ? null : label,
              hint: style.isProfile ? 'City' : null,
              counterText: '',
              prefixIcon: style.prefix(
                icon: Icons.location_city_outlined,
                emoji: '🏙️',
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Country + State + City as used on the Edit Profile screen: Country and
/// State side by side on wide screens (stacked on phones), City below.
class LocationSelects extends StatelessWidget {
  const LocationSelects({
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
              city,
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
          ],
        );
      },
    );
  }
}
