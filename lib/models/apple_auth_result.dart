import 'auth_response.dart';

/// What Sign in with Apple handed back for one attempt. Kept so a brand-new
/// user's profile-completion step can re-send the same proof to the backend.
class AppleCredentialData {
  const AppleCredentialData({
    required this.identityToken,
    required this.authorizationCode,
    required this.nonce,
  });

  /// Apple-signed JWT the backend must verify.
  final String identityToken;

  /// Short-lived, single-use code the backend can exchange for a refresh
  /// token (needed to revoke the Apple grant on account deletion).
  final String authorizationCode;

  /// The *raw* nonce; Apple received its SHA-256 and embedded that in the
  /// identity token.
  final String nonce;
}

class AppleAuthResult {
  const AppleAuthResult({
    required this.success,
    required this.message,
    this.authResponse,
    this.isNewUser = false,
    this.cancelled = false,
    this.name = '',
    this.email = '',
    this.credential,
  });

  final bool success;
  final String message;
  final AuthResponse? authResponse;
  final bool isNewUser;

  /// The user dismissed the Apple sheet — not an error worth showing.
  final bool cancelled;

  /// Apple only provides the name on the user's very first authorization for
  /// this app, so it is captured here and carried through registration. May
  /// be empty (returning Apple user whose account was never completed).
  final String name;

  /// May be an `@privaterelay.appleid.com` address if the user chose
  /// "Hide My Email".
  final String email;
  final AppleCredentialData? credential;
}
