/// Models for user registration flow
class RegisterRequest {
  RegisterRequest({
    required this.name,
    required this.email,
    required this.password,
    required this.mobile,
    required this.countryCode,
    required this.dob,
    required this.gender,
    required this.country,
    required this.state,
    required this.city,
    required this.otp,
    this.privacyConsent = false,
    this.hipaaConsent = false,
  });

  final String name;
  final String email;
  final String password;
  final String mobile;
  final String countryCode;
  final String dob;
  final String gender;
  final String country;
  final String state;
  final String city;
  final String otp;
  final bool privacyConsent;
  final bool hipaaConsent;

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'password': password,
    'mobile': mobile,
    'countryCode': countryCode,
    'dob': dob,
    'gender': gender,
    'country': country,
    'state': state,
    'city': city,
    'otp': otp,
    'privacyConsent': privacyConsent,
    'hipaaConsent': hipaaConsent,
  };
}

class SendOtpRequest {
  SendOtpRequest({required this.email});

  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

class RegisterFormData {
  RegisterFormData({
    required this.name,
    required this.email,
    required this.password,
    required this.mobile,
    required this.countryCode,
    required this.dob,
    required this.gender,
    required this.country,
    required this.state,
    required this.city,
    required this.privacyConsent,
    required this.hipaaConsent,
  });

  final String name;
  final String email;
  final String password;
  final String mobile;
  final String countryCode;
  final String dob;
  final String gender;
  final String country;
  final String state;
  final String city;
  final bool privacyConsent;
  final bool hipaaConsent;

  RegisterRequest toRegisterRequest(String otp) => RegisterRequest(
    name: name,
    email: email,
    password: password,
    mobile: mobile,
    countryCode: countryCode,
    dob: dob,
    gender: gender,
    country: country,
    state: state,
    city: city,
    otp: otp,
    privacyConsent: privacyConsent,
    hipaaConsent: hipaaConsent,
  );
}
