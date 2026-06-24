  import 'package:flutter_secure_storage/flutter_secure_storage.dart';
  import 'package:shared_preferences/shared_preferences.dart';

  /// Service for secure token storage
  /// Uses flutter_secure_storage for sensitive data like tokens
  /// Uses shared_preferences for non-sensitive user information
  class TokenStorageService {
    const TokenStorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

    final FlutterSecureStorage _secureStorage;

    // Secure storage keys
    static const String _tokenKey = 'auth_token';
    static const String _refreshTokenKey = 'refresh_token';
    static const String _resetTokenKey = 'reset_token';

    // Shared preferences keys (for non-sensitive data)
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

    // Token management
    Future<void> saveToken(String token) async {
      await _secureStorage.write(key: _tokenKey, value: token);
    }

    Future<String?> getToken() async {
      return await _secureStorage.read(key: _tokenKey);
    }

    Future<void> saveRefreshToken(String token) async {
      await _secureStorage.write(key: _refreshTokenKey, value: token);
    }

    Future<String?> getRefreshToken() async {
      return await _secureStorage.read(key: _refreshTokenKey);
    }

    Future<void> saveResetToken(String token) async {
      await _secureStorage.write(key: _resetTokenKey, value: token);
    }

    Future<String?> getResetToken() async {
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
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_userIdKey, userId),
        prefs.setString(_userNameKey, name),
        prefs.setString(_userEmailKey, email),
        prefs.setString(_userRoleKey, role),
        prefs.setString(_userMobileKey, mobile),
        prefs.setString(_userDobKey, dob),
        prefs.setString(_userGenderKey, gender),
        prefs.setString(_userCountryKey, country),
        prefs.setString(_userStateKey, state),
        prefs.setString(_userCityKey, city),
        prefs.setString(_userLocationKey, location),
      ]);
    }

    Future<String?> getUserId() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userIdKey);
    }

    Future<String?> getUserEmail() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userEmailKey);
    }

    Future<String?> getUserName() async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_userNameKey);
    }

    Future<Map<String, String>> getUserProfile() async {
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

    Future<void> clearAll() async {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        _secureStorage.delete(key: _tokenKey),
        _secureStorage.delete(key: _refreshTokenKey),
        _secureStorage.delete(key: _resetTokenKey),
        prefs.remove(_userIdKey),
        prefs.remove(_userNameKey),
        prefs.remove(_userEmailKey),
        prefs.remove(_userRoleKey),
        prefs.remove(_userMobileKey),
        prefs.remove(_userDobKey),
        prefs.remove(_userGenderKey),
        prefs.remove(_userCountryKey),
        prefs.remove(_userStateKey),
        prefs.remove(_userCityKey),
        prefs.remove(_userLocationKey),
      ]);
    }

    Future<bool> isAuthenticated() async {
      final token = await getToken();
      return token != null && token.isNotEmpty;
    }
  }
