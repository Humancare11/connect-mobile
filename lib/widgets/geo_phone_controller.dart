import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_validators.dart';
import '../services/backend_location_service.dart';
import '../utils/dial_codes.dart';

enum LoadStatus { idle, loading, ready, error }

/// One entry in the dial-code picker.
class DialOption {
  const DialOption({
    required this.iso2,
    required this.name,
    required this.dial,
  });

  final String iso2;
  final String name;
  final String dial;

  String get label => '${flagEmoji(iso2)} $name ($dial)';
}

/// "IN" → 🇮🇳.
String flagEmoji(String iso2) {
  final code = iso2.trim().toUpperCase();
  if (code.length != 2) return '';
  return String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

/// Country, State, City and Phone for a form, with the same rules as the web
/// (Login.jsx / LocationSelects.jsx / PhoneInputField.jsx):
///
///  * Country and State come from the backend (`/api/locations/...`), the
///    list the backend validates against — never a third-party source.
///  * Country ↔ phone dial code sync, joined by ISO2 only (never by name or
///    dial digits: +1 is US *and* Canada, +7 Russia *and* Kazakhstan, ...).
///    Picking a country sets the dial code; picking a dial code sets the
///    country. Either way State and City are cleared when the country changes.
///  * State is required unless the country has none ("No states available").
///  * City is optional free text, max 100.
///  * India numbers: at most 10 digits, a leading 91 or 0 is stripped.
///
/// One instance per form; the sign-up, social-completion and profile screens
/// all use it so the rules live in exactly one place.
class GeoPhoneController extends ChangeNotifier {
  GeoPhoneController({
    BackendLocationService? locations,
    this.requireLocation = true,
    this.requireMobile = true,
    bool defaultToIndia = true,
  }) : _locations = locations ?? BackendLocationService() {
    if (defaultToIndia) {
      countryName = 'India';
      iso2 = 'IN';
    }
    numberFormatter = _PhoneDigitsFormatter(this);
    cityController.addListener(_onCityChanged);
  }

  /// Country required, and State required when the country has states.
  final bool requireLocation;

  /// Phone required. (On the profile screen it is only required once the user
  /// already has a number — it can be replaced but never removed.)
  final bool requireMobile;

  final BackendLocationService _locations;

  // Shared across instances for the app session: these lists never change
  // mid-session and every form would otherwise refetch them.
  static List<BackendCountry>? _countriesCache;
  static final Map<String, List<String>> _statesCache = {};

  @visibleForTesting
  static void clearCaches() {
    _countriesCache = null;
    _statesCache.clear();
  }

  // ── Country ──────────────────────────────────────────────────────────────
  List<BackendCountry> countries = const [];
  LoadStatus countriesStatus = LoadStatus.idle;
  String countryName = '';

  /// ISO2 of the resolved country; empty when no country is selected or the
  /// stored value isn't in the backend list (legacy free text).
  String iso2 = '';

  // ── State ────────────────────────────────────────────────────────────────
  List<String> states = const [];
  LoadStatus statesStatus = LoadStatus.idle;
  String state = '';
  int _statesRequest = 0;

  // ── City ─────────────────────────────────────────────────────────────────
  final TextEditingController cityController = TextEditingController();
  String get city => cityController.text.trim();

  // ── Phone ────────────────────────────────────────────────────────────────
  final TextEditingController numberController = TextEditingController();
  late final TextInputFormatter numberFormatter;
  String dialIso = 'IN';
  String dialCode = '+91';

  /// The number as it was stored on the server. A legacy number the user
  /// never touched is sent back untouched and not re-validated, so it can
  /// never block saving other fields.
  String originalMobile = '';

  /// True once the user has typed in the number or changed its country code
  /// (directly, or by changing Country).
  bool mobileEdited = false;

  bool _disposed = false;

  bool get hasCountry => countryName.trim().isNotEmpty;
  bool get isIndiaDial => dialCode == '+91';
  bool get noStatesAvailable =>
      statesStatus == LoadStatus.ready && states.isEmpty && iso2.isNotEmpty;

  /// Dial code + digits, e.g. "+919876543210"; empty when no digits typed.
  String get fullNumber {
    final digits = numberController.text.trim();
    return digits.isEmpty ? '' : '$dialCode$digits';
  }

  /// What to send as `mobile`: the original number if the user never touched
  /// it, otherwise [fullNumber].
  String get mobileForSubmit => (!mobileEdited && originalMobile.isNotEmpty)
      ? originalMobile
      : fullNumber;

  List<DialOption> get dialOptions {
    final options = <DialOption>[
      for (final c in countries)
        if (dialCodeForIso2(c.isoCode).isNotEmpty)
          DialOption(
            iso2: c.isoCode,
            name: c.name,
            dial: dialCodeForIso2(c.isoCode),
          ),
    ];
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> loadCountries({bool force = false}) async {
    if (!force && _countriesCache != null) {
      countries = _countriesCache!;
      countriesStatus = LoadStatus.ready;
      _resolveCountryFromList();
      _notify();
      return;
    }
    if (countriesStatus == LoadStatus.loading) return;
    countriesStatus = LoadStatus.loading;
    _notify();

    final result = await _locations.countries();
    if (_disposed) return;
    final list = result.data ?? const <BackendCountry>[];
    if (result.success && list.isNotEmpty) {
      final sorted = [...list]..sort((a, b) => a.name.compareTo(b.name));
      _countriesCache = sorted;
      countries = sorted;
      countriesStatus = LoadStatus.ready;
      _resolveCountryFromList();
    } else {
      countriesStatus = LoadStatus.error;
    }
    _notify();
  }

  Future<void> retryCountries() => loadCountries(force: true);

  Future<void> retryStates() {
    _statesCache.remove(iso2);
    return _loadStates();
  }

  Future<void> _loadStates() async {
    final iso = iso2;
    final request = ++_statesRequest;
    if (iso.isEmpty) {
      states = const [];
      statesStatus = LoadStatus.idle;
      _notify();
      return;
    }
    final cached = _statesCache[iso];
    if (cached != null) {
      states = cached;
      statesStatus = LoadStatus.ready;
      _notify();
      return;
    }
    states = const [];
    statesStatus = LoadStatus.loading;
    _notify();

    final result = await _locations.states(iso);
    // Ignore a response for a country the user has already moved away from.
    if (_disposed || request != _statesRequest) return;
    if (result.success) {
      final list = result.data ?? const <String>[];
      _statesCache[iso] = list;
      states = list;
      statesStatus = LoadStatus.ready;
    } else {
      states = const [];
      statesStatus = LoadStatus.error;
    }
    _notify();
  }

  /// Starts everything a form needs: the country list and, for a preselected
  /// country, its states.
  Future<void> init() async {
    await Future.wait([loadCountries(), _loadStates()]);
  }

  // ── Selection (the two-way sync lives here) ──────────────────────────────

  /// User picked a country. Sets the dial code from its ISO2 and clears
  /// State and City.
  void selectCountry(BackendCountry country) {
    if (country.isoCode == iso2 && country.name == countryName) return;
    countryName = country.name;
    iso2 = country.isoCode;
    state = '';
    cityController.text = '';
    final dial = dialCodeForIso2(country.isoCode);
    if (dial.isNotEmpty) {
      if (dial != dialCode) mobileEdited = true;
      dialIso = country.isoCode;
      dialCode = dial;
    }
    // A country with no dial entry (Antarctica, ...) leaves the code as is.
    _loadStates();
  }

  /// User cleared the country (profile only).
  void clearCountry() {
    countryName = '';
    iso2 = '';
    state = '';
    cityController.text = '';
    states = const [];
    statesStatus = LoadStatus.idle;
    _statesRequest++;
    _notify();
  }

  /// User picked a dial-code row. Sets the country by ISO2 and, if that
  /// changes the country, clears State and City.
  void selectDialIso(String iso) {
    final dial = dialCodeForIso2(iso);
    if (dial.isEmpty) return;
    dialIso = iso;
    dialCode = dial;
    mobileEdited = true;
    final match = _countryByIso(iso);
    if (match != null && match.isoCode != iso2) {
      countryName = match.name;
      iso2 = match.isoCode;
      state = '';
      cityController.text = '';
      _loadStates();
      return;
    }
    _notify();
  }

  void selectState(String name) {
    state = name;
    _notify();
  }

  void _onCityChanged() => _notify();

  // ── Loading an existing profile ──────────────────────────────────────────

  /// Fills the form from stored values *without* triggering any sync — a
  /// stored US country with a +91 number stays exactly that until the user
  /// changes something. Values the lists don't know (legacy ISO codes, free
  /// text) are kept as they are so saving never blanks them.
  void loadFromProfile({
    required String country,
    required String stateValue,
    required String cityValue,
    required String mobile,
  }) {
    countryName = country.trim();
    state = stateValue.trim();
    cityController.text = cityValue.trim();
    originalMobile = mobile.trim();
    mobileEdited = false;
    iso2 = '';
    if (countryName.isNotEmpty) {
      final match = _findCountry(countryName);
      if (match != null) {
        countryName = match.name;
        iso2 = match.isoCode;
      } else if (RegExp(r'^[A-Za-z]{2}$').hasMatch(countryName)) {
        // A legacy ISO code: usable for the states lookup right away; the
        // canonical name replaces it once the country list is in.
        iso2 = countryName.toUpperCase();
      }
    }
    final parsed = parseMobile(originalMobile, preferIso: iso2);
    if (parsed != null) {
      dialIso = parsed.iso2;
      dialCode = parsed.dial;
      numberController.text = parsed.digits;
    } else {
      dialIso = 'IN';
      dialCode = '+91';
      numberController.text = originalMobile.replaceAll(RegExp(r'\D'), '');
    }
    _loadStates();
  }

  // ── Validation (web messages) ────────────────────────────────────────────

  String? get countryError {
    if (!requireLocation) return null;
    return hasCountry ? null : 'Select your country';
  }

  String? get stateError {
    if (!requireLocation || !hasCountry || iso2.isEmpty) return null;
    switch (statesStatus) {
      case LoadStatus.loading:
        return 'Please wait for the states to load';
      case LoadStatus.error:
        return "Couldn't load states. Tap Retry and try again";
      case LoadStatus.ready:
        return states.isNotEmpty && state.trim().isEmpty
            ? 'Select your state / province'
            : null;
      case LoadStatus.idle:
        return null;
    }
  }

  String? get mobileError {
    final digits = numberController.text.trim();
    if (digits.isEmpty) {
      if (originalMobile.isNotEmpty) return 'Mobile number cannot be removed.';
      return requireMobile ? 'Enter mobile number' : null;
    }
    // A stored number the user never touched is not re-validated.
    if (!mobileEdited && originalMobile.isNotEmpty) return null;
    final error = AuthValidators.mobileError(fullNumber);
    return error.isEmpty ? null : error;
  }

  /// First problem, in on-screen order, or null.
  String? get firstError => countryError ?? stateError ?? mobileError;

  // ── Helpers ──────────────────────────────────────────────────────────────

  BackendCountry? _countryByIso(String iso) {
    for (final c in countries) {
      if (c.isoCode.toUpperCase() == iso.toUpperCase()) return c;
    }
    return null;
  }

  BackendCountry? _findCountry(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) return null;
    final list = countries.isNotEmpty
        ? countries
        : (_countriesCache ?? const []);
    for (final c in list) {
      if (c.name.toLowerCase() == q || c.isoCode.toLowerCase() == q) return c;
    }
    return null;
  }

  // Once the list is in, a stored legacy value ("IN", "india") becomes the
  // canonical entry; a value the list doesn't know stays as typed.
  void _resolveCountryFromList() {
    if (!hasCountry) return;
    final match = _findCountry(countryName);
    if (match == null) {
      iso2 = '';
      return;
    }
    final changed = match.isoCode != iso2;
    countryName = match.name;
    iso2 = match.isoCode;
    if (changed) _loadStates();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cityController.removeListener(_onCityChanged);
    cityController.dispose();
    numberController.dispose();
    super.dispose();
  }
}

class ParsedMobile {
  const ParsedMobile(this.iso2, this.dial, this.digits);
  final String iso2;
  final String dial;
  final String digits;
}

// Shared dial codes: when a stored number only says "+1" it is the most
// likely owner of that code that wins, unless the stored country says
// otherwise (see parseMobile's preferIso).
const List<String> _dialPriority = [
  'US',
  'RU',
  'GB',
  'AU',
  'NO',
  'FI',
  'FR',
  'NL',
  'GP',
  'RE',
  'CW',
  'MA',
];

/// Splits "+919876543210" into ISO2 / "+91" / "9876543210". The code is the
/// longest prefix that is a known dial code; when several countries share it,
/// [preferIso] (the user's stored country) wins, then a fixed priority list.
/// Returns null for anything that doesn't start with a known "+code".
ParsedMobile? parseMobile(String value, {String preferIso = ''}) {
  final cleaned = value.replaceAll(RegExp(r'[\s\-().]'), '');
  if (!cleaned.startsWith('+')) return null;
  final digits = cleaned.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;

  for (var len = math.min(5, digits.length - 1); len >= 1; len--) {
    final dial = '+${digits.substring(0, len)}';
    final owners = [
      for (final e in kDialCodesByIso2.entries)
        if (e.value == dial) e.key,
    ];
    if (owners.isEmpty) continue;
    owners.sort();
    final prefer = preferIso.toUpperCase();
    final iso = owners.contains(prefer)
        ? prefer
        : _dialPriority.firstWhere(owners.contains, orElse: () => owners.first);
    return ParsedMobile(iso, dial, digits.substring(len));
  }
  return null;
}

/// Keeps the number field to digits, with the web's India handling: a pasted
/// "+91 98765 43210" or "098765 43210" becomes the bare 10 digits, and an
/// Indian number is capped at 10. Everything else is capped at 15.
class _PhoneDigitsFormatter extends TextInputFormatter {
  _PhoneDigitsFormatter(this._controller);

  final GeoPhoneController _controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (_controller.isIndiaDial) {
      if (digits.length == 12 && digits.startsWith('91')) {
        digits = digits.substring(2);
      } else if (digits.length == 11 && digits.startsWith('0')) {
        digits = digits.substring(1);
      }
      digits = digits.substring(0, math.min(digits.length, 10));
    }
    digits = digits.substring(0, math.min(digits.length, 15));
    if (digits != oldValue.text) _controller.mobileEdited = true;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
