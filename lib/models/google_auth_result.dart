import 'auth_response.dart';

class GoogleAuthResult {
  const GoogleAuthResult({
    required this.success,
    required this.message,
    this.authResponse,
    this.isNewUser = false,
    this.googleName = '',
    this.googleEmail = '',
    this.accessToken = '',
  });

  final bool success;
  final String message;
  final AuthResponse? authResponse;
  final bool isNewUser;
  final String googleName;
  final String googleEmail;
  final String accessToken;
}
