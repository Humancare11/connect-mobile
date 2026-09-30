import 'package:flutter/material.dart';

import '../models/location_model.dart';
import '../services/location_service.dart';
import '../utils/dial_codes.dart';
import 'search_picker.dart';

/// Holds the dial code and national number behind a [MobilePhoneField].
class MobilePhoneController {
  MobilePhoneController({this.dialCode = '+91'});

  // Same default as the web app's PhoneInputField (defaultCountry "IN").
  String dialCode;
  final TextEditingController number = TextEditingController();

  /// Dial code + digits as sent to the backend, e.g. "+919876543210".
  String get fullNumber {
    final digits = number.text.trim();
    return digits.isEmpty ? '' : '$dialCode$digits';
  }

  void dispose() => number.dispose();
}

/// Dial-code picker + mobile number input, matching the registration form.
class MobilePhoneField extends StatefulWidget {
  const MobilePhoneField({
    super.key,
    required this.controller,
    this.hint = 'Mobile Number',
  });

  final MobilePhoneController controller;
  final String hint;

  @override
  State<MobilePhoneField> createState() => _MobilePhoneFieldState();
}

class _MobilePhoneFieldState extends State<MobilePhoneField> {
  static const Color _navy = Color(0xff1a3a5c);

  final LocationService _locationService = LocationService();
  List<Country> _countries = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    setState(() => _loading = true);
    final result = await _locationService.getCountries();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success) {
        _countries = (result.data ?? [])
            .where((c) => dialCodeForIso2(c.iso2).isNotEmpty)
            .toList();
      }
    });
  }

  Future<void> _pickDialCode() async {
    final labels = <String, Country>{
      for (final c in _countries) '${c.name} (${dialCodeForIso2(c.iso2)})': c,
    };
    final picked = await showSearchPicker(
      context,
      title: 'Select Country Code',
      options: labels.keys.toList(),
    );
    final country = picked == null ? null : labels[picked];
    if (country == null || !mounted) return;
    setState(() => widget.controller.dialCode = dialCodeForIso2(country.iso2));
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.09)),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          height: 52,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _loading || _countries.isEmpty ? null : _pickDialCode,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xfff9fafb),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.09)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      widget.controller.dialCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                  ),
                  _loading
                      ? const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        )
                      : const Icon(Icons.arrow_drop_down, size: 18, color: _navy),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: widget.controller.number,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: _navy),
              filled: true,
              fillColor: const Color(0xfff9fafb),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _navy, width: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
