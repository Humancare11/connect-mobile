// Date of birth and gender: what the app needs before a payment is started.
// The server enforces the same rules; these only decide what to show.
import '../services/auth_validators.dart';

const List<String> kGenderOptions = ['Male', 'Female', 'Other'];

/// True when the profile already has a usable date of birth and gender (the
/// "Complete your details" step is then skipped).
bool isPatientProfileComplete({
  required String dob,
  required String gender,
  DateTime? now,
}) =>
    AuthValidators.dobError(dob, now: now).isEmpty &&
    kGenderOptions.contains(gender.trim());

/// True for the server's refusal to start a payment for a profile with no date
/// of birth or gender: 422 with `code: "PROFILE_INCOMPLETE"`.
bool isProfileIncompleteResponse(int statusCode, Map<String, dynamic> body) =>
    statusCode == 422 && body['code'] == 'PROFILE_INCOMPLETE';
