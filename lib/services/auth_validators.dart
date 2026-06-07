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
}
