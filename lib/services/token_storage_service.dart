import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for secure token storage
/// Uses flutter_secure_storage for sensitive data like tokens
/// Uses shared_preferences for non-sensitive user information on web only —
/// see the class doc on the profile keys below for why mobile differs.
class TokenStorageService {
  const TokenStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  // Secure storage keys
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _resetTokenKey = 'reset_token';

  // Profile keys. On mobile these now live in flutter_secure_storage
  // alongside the tokens above — this app is a health-record product (DOB,
  // gender, mobile, location), and plain SharedPreferences on Android is
  // unencrypted XML that also rides along in the default app-data backup.
  // Kept as plain SharedPreferences on web only, unchanged: flutter_secure_storage's
  // web backend has its own caveats (see package docs) that weren't part of
  // this pass, and web isn't in scope for the Play Store release this is for.
  //
  // Migration: `_readMigrating` below reads straight from secure storage
  // first and only falls back to (and then clears) the legacy SharedPreferences
  // copy for a key that hasn't been touched since this change shipped. That
  // makes migration lazy and per-field instead of a one-shot startup step,
  // so an existing logged-in user's session and profile survive the update
  // with no explicit migration flag to track or get out of sync.
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _userRoleKey = 'user_role';
  static const String _userMobileKey = 'user_mobile';
  static const String _userDobKey = 'user_dob';
  static const String _userGenderKey = 'user_gender';
  static const String _userCountryKey = 'user_country';
  static const String _userStateKey = 'user_state';
  static const String _userCityKey = 'user_city';
  static const String _userLocationKey = 'user_location';

  static const List<String> _profileKeys = [
    _userIdKey,
    _userNameKey,
    _userEmailKey,
    _userRoleKey,
    _userMobileKey,
    _userDobKey,
    _userGenderKey,
    _userCountryKey,
    _userStateKey,
    _userCityKey,
    _userLocationKey,
  ];

  // Token management
  Future<void> saveToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      return;
    }
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_refreshTokenKey, token);
      return;
    }
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenKey);
    }
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  Future<void> saveResetToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_resetTokenKey, token);
      return;
    }
    await _secureStorage.write(key: _resetTokenKey, value: token);
  }

  Future<String?> getResetToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_resetTokenKey);
    }
    return await _secureStorage.read(key: _resetTokenKey);
  }

  // User profile management
  Future<void> saveUserProfile({
    required String userId,
    required String name,
    required String email,
    required String role,
    required String mobile,
    required String dob,
    required String gender,
    required String country,
    String state = '',
    String city = '',
    String location = '',
  }) async {
    final values = <String, String>{
      _userIdKey: userId,
      _userNameKey: name,
      _userEmailKey: email,
      _userRoleKey: role,
      _userMobileKey: mobile,
      _userDobKey: dob,
      _userGenderKey: gender,
      _userCountryKey: country,
      _userStateKey: state,
      _userCityKey: city,
      _userLocationKey: location,
    };

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait(
        values.entries.map((e) => prefs.setString(e.key, e.value)),
      );
      return;
    }

    await Future.wait(
      values.entries.map(
        (e) => _secureStorage.write(key: e.key, value: e.value),
      ),
    );
    // A fresh save always lands in secure storage above; drop any stale
    // plaintext copy left over from before this field was migrated so it
    // doesn't linger indefinitely un-migrated.
    await _clearLegacyProfilePrefs();
  }

  Future<String?> getUserId() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userIdKey);
    }
    return _readMigrating(_userIdKey);
  }

  Future<String?> getUserEmail() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userEmailKey);
    }
    return _readMigrating(_userEmailKey);
  }

  Future<String?> getUserName() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userNameKey);
    }
    return _readMigrating(_userNameKey);
  }

  Future<Map<String, String>> getUserProfile() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return {
        'userId': prefs.getString(_userIdKey) ?? '',
        'name': prefs.getString(_userNameKey) ?? '',
        'email': prefs.getString(_userEmailKey) ?? '',
        'role': prefs.getString(_userRoleKey) ?? '',
        'mobile': prefs.getString(_userMobileKey) ?? '',
        'dob': prefs.getString(_userDobKey) ?? '',
        'gender': prefs.getString(_userGenderKey) ?? '',
        'country': prefs.getString(_userCountryKey) ?? '',
        'state': prefs.getString(_userStateKey) ?? '',
        'city': prefs.getString(_userCityKey) ?? '',
        'location': prefs.getString(_userLocationKey) ?? '',
      };
    }

    final values = await Future.wait(_profileKeys.map(_readMigrating));
    final byKey = Map.fromIterables(_profileKeys, values);

    return {
      'userId': byKey[_userIdKey] ?? '',
      'name': byKey[_userNameKey] ?? '',
      'email': byKey[_userEmailKey] ?? '',
      'role': byKey[_userRoleKey] ?? '',
      'mobile': byKey[_userMobileKey] ?? '',
      'dob': byKey[_userDobKey] ?? '',
      'gender': byKey[_userGenderKey] ?? '',
      'country': byKey[_userCountryKey] ?? '',
      'state': byKey[_userStateKey] ?? '',
      'city': byKey[_userCityKey] ?? '',
      'location': byKey[_userLocationKey] ?? '',
    };
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      await Future.wait([
        prefs.remove(_tokenKey),
        prefs.remove(_refreshTokenKey),
        prefs.remove(_resetTokenKey),
        ..._profileKeys.map(prefs.remove),
      ]);
      return;
    }

    await Future.wait([
      _secureStorage.delete(key: _tokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _resetTokenKey),
      ..._profileKeys.map((key) => _secureStorage.delete(key: key)),
      // Also wipe any legacy plaintext copy that hasn't been read (and
      // therefore migrated) yet — otherwise logging out would leave a
      // previous user's PII sitting in SharedPreferences on a shared device.
      ..._profileKeys.map(prefs.remove),
    ]);
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Reads [key] from secure storage; if it isn't there yet, falls back to
  /// the pre-migration SharedPreferences value (if any), copies it into
  /// secure storage, deletes the plaintext copy, and returns it. Mobile only
  /// — callers must guard with `kIsWeb` first.
  Future<String?> _readMigrating(String key) async {
    final secureValue = await _secureStorage.read(key: key);
    if (secureValue != null && secureValue.isNotEmpty) return secureValue;

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) return null;

    await _secureStorage.write(key: key, value: legacyValue);
    await prefs.remove(key);
    return legacyValue;
  }

  Future<void> _clearLegacyProfilePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(_profileKeys.map(prefs.remove));
  }
}
