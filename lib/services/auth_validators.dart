class AuthValidators {
  static const passwordRequirements =
      '8+ chars with uppercase, lowercase, number, and symbol.';

  static const _commonPasswords = {
    'password',
    'password1',
    'password123',
    '12345678',
    '123456789',
    'qwerty123',
    'admin123',
    'admin1234',
    'welcome1',
    'welcome123',
    'letmein1',
    'iloveyou1',
    'humancare',
    'humancare123',
    'doctor123',
    'patient123',
  };

  static String passwordError(String value) {
    final password = value.trim();

    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    if (!RegExp('[A-Z]').hasMatch(password)) {
      return 'Password must include at least one uppercase letter.';
    }

    if (!RegExp('[a-z]').hasMatch(password)) {
      return 'Password must include at least one lowercase letter.';
    }

    if (!RegExp('[0-9]').hasMatch(password)) {
      return 'Password must include at least one number.';
    }

    if (!RegExp('[^A-Za-z0-9]').hasMatch(password)) {
      return 'Password must include at least one special character.';
    }

    if (_commonPasswords.contains(password.toLowerCase())) {
      return 'Password is too common. Choose a stronger password.';
    }

    return '';
  }

  static String dobError(String value) {
    final dob = value.trim();
    const minDate = '1900-01-01';

    if (dob.isEmpty) {
      return 'Select Date of Birth';
    }

    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob)) {
      return 'Enter a valid Date of Birth';
    }

    final parsed = DateTime.tryParse('${dob}T00:00:00');
    if (parsed == null) {
      return 'Enter a valid Date of Birth';
    }

    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (dob.compareTo(today) > 0) {
      return 'Date of Birth cannot be in the future';
    }

    if (dob.compareTo(minDate) < 0) {
      return 'Date of Birth must be in or after 1900';
    }

    return '';
  }

  static bool isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  static final RegExp _indiaMobile = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _genericE164Mobile = RegExp(r'^\+[1-9]\d{7,14}$');
  static const indiaMobileMessage =
      'Enter a valid 10-digit Indian mobile number starting with 6, 7, 8 or 9.';
  static const genericMobileMessage =
      'Enter a valid mobile number with country code.';

  /// Mirrors the web app's utils/phone.js getMobileError exactly (same rules,
  /// same messages). [value] must already carry the `+<country code>` prefix
  /// (e.g. "+919876543210" — dial code + national number concatenated).
  static String mobileError(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s\-().]'), '');
    if (cleaned.isEmpty) return 'Enter mobile number';
    if (cleaned.startsWith('+91')) {
      return _indiaMobile.hasMatch(cleaned.substring(3)) ? '' : indiaMobileMessage;
    }
    return _genericE164Mobile.hasMatch(cleaned) ? '' : genericMobileMessage;
  }

  static String countryCodeError(String value) {
    final code = value.trim();

    if (code.isEmpty) {
      return 'Select a country code';
    }

    if (!code.startsWith('+')) {
      return 'Country code must start with +';
    }

    if (!RegExp(r'^\+\d{1,3}$').hasMatch(code)) {
      return 'Enter a valid country code';
    }

    return '';
  }

  static String stateError(String value) {
    final state = value.trim();

    if (state.isEmpty) {
      return 'Enter your state or province';
    }

    if (state.length < 2) {
      return 'State must be at least 2 characters';
    }

    return '';
  }

  static String cityError(String value) {
    final city = value.trim();

    if (city.isEmpty) {
      return 'Enter your city';
    }

    if (city.length < 2) {
      return 'City must be at least 2 characters';
    }

    return '';
  }
}
