import '../models/api_result.dart';
import '../models/auth_response.dart';
import '../models/register_model.dart';
import 'auth_service.dart';
import 'token_storage_service.dart';

/// Repository pattern implementation for authentication
/// This abstracts the auth service and storage operations
/// Follows clean architecture principles
class AuthRepository {
  AuthRepository({AuthService? authService, TokenStorageService? tokenStorage})
    : _authService = authService ?? AuthService(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final AuthService _authService;
  final TokenStorageService _tokenStorage;

  /// Send OTP to email for registration.
  Future<ApiResult<void>> sendRegisterOtp({
    required String email,
    required String password,
    required String dob,
    required bool privacyConsent,
    required bool hipaaConsent,
  }) async {
    return _authService.sendRegisterOtp(
      email: email,
      password: password,
      dob: dob,
      privacyConsent: privacyConsent,
      hipaaConsent: hipaaConsent,
    );
  }

  /// Register a new user with OTP verification
  Future<ApiResult<AuthResponse>> register(RegisterRequest request) async {
    final result = await _authService.register(
      name: request.name,
      email: request.email,
      password: request.password,
      mobile: request.mobile,
      dob: request.dob,
      gender: request.gender,
      country: request.country,
      privacyConsent: request.privacyConsent,
      hipaaConsent: request.hipaaConsent,
      otp: request.otp,
    );

    if (result.success && result.data != null) {
      await _saveSession(result.data!);
    }

    return result;
  }

  /// Save user session after successful registration/login
  Future<void> _saveSession(AuthResponse authResponse) async {
    await _tokenStorage.saveToken(authResponse.token);
    if (authResponse.refreshToken.isNotEmpty) {
      await _tokenStorage.saveRefreshToken(authResponse.refreshToken);
    }
    await _tokenStorage.saveUserProfile(
      userId: authResponse.user.id,
      name: authResponse.user.name,
      email: authResponse.user.email,
      role: authResponse.user.role,
      mobile: authResponse.user.mobile,
      dob: authResponse.user.dob,
      gender: authResponse.user.gender,
      country: authResponse.user.country,
      state: authResponse.user.state,
      city: authResponse.user.city,
      location: authResponse.user.location,
    );
  }

  /// Get current authentication token
  Future<String?> getToken() async {
    return _tokenStorage.getToken();
  }

  /// Get current user profile
  Future<Map<String, String>> getUserProfile() async {
    return _tokenStorage.getUserProfile();
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return _tokenStorage.isAuthenticated();
  }

  /// Clear all stored data (logout)
  Future<void> clearSession() async {
    await _tokenStorage.clearAll();
  }
}
