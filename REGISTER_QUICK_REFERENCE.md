# Flutter Register Screen - Quick Reference Card

## 📁 File Locations

```
lib/
├── models/register_model.dart           ← RegisterRequest, RegisterFormData
├── services/
│   ├── token_storage_service.dart       ← Secure token storage
│   ├── auth_repository.dart             ← Business logic layer
│   ├── auth_service.dart                ✏️ UPDATED
│   ├── api_client.dart                  ✏️ UPDATED
│   └── auth_validators.dart             (existing)
└── screens/
    ├── register_screen.dart             ← Main UI (3-step form)
    └── login_screen.dart                ✏️ Add navigation link
```

## 🚀 Quick Start

```dart
// 1. Add to dependencies (pubspec.yaml)
flutter_secure_storage: ^9.0.0
intl: ^0.19.0

// 2. Run
flutter pub get

// 3. Navigate
Navigator.push(context, MaterialPageRoute(
  builder: (_) => const RegisterScreen(),
));

// 4. That's it! Rest is handled internally
```

## 🎯 Core Classes

### RegisterRequest
```dart
RegisterRequest(
  name: 'John Doe',
  email: 'john@example.com',
  password: 'SecurePass123!',
  mobile: '+1-555-0123',
  dob: '1990-01-15',
  gender: 'Male',
  country: 'United States',
  otp: '123456',
  privacyConsent: true,
  hipaaConsent: true,
)
```

### TokenStorageService
```dart
// Save token (encrypted)
await _tokenStorage.saveToken(token);

// Get token
final token = await _tokenStorage.getToken();

// Save user profile
await _tokenStorage.saveUserProfile(
  userId: '123',
  name: 'John',
  email: 'john@example.com',
  role: 'patient',
  mobile: '+1-555-0123',
  dob: '1990-01-15',
  gender: 'Male',
  country: 'United States',
);

// Get user profile
final profile = await _tokenStorage.getUserProfile();

// Check auth status
final isAuth = await _tokenStorage.isAuthenticated();

// Logout
await _tokenStorage.clearAll();
```

### AuthRepository
```dart
final repo = AuthRepository();

// Send OTP
final result = await repo.sendRegisterOtp('user@example.com');

// Register user
final regResult = await repo.register(registerRequest);

// Check if authenticated
final isAuth = await repo.isAuthenticated();

// Get user data
final profile = await repo.getUserProfile();

// Logout
await repo.clearSession();
```

## ✅ Validation Rules

| Field | Rule |
|-------|------|
| Email | Valid RFC 5322 format |
| Name | 3+ characters |
| Password | 8+ chars, upper, lower, number, symbol, not common |
| Confirm Password | Must match password |
| Mobile | 10+ chars, digits, dashes, plus allowed |
| DOB | YYYY-MM-DD, not future, >= 1900 |
| Gender | Required (dropdown) |
| Country | Required (dropdown) |
| Privacy Consent | Must be checked |
| HIPAA Consent | Must be checked |
| OTP | Exactly 6 digits |

## 🔐 Security

```
Tokens → Flutter Secure Storage (Encrypted)
User Data → SharedPreferences (Local, not encrypted)
Passwords → Never stored, only hashed by server
```

## 📱 Registration Flow

```
Step 0: Email OTP
├─ Enter email
├─ Click "Send OTP"
└─ OTP sent to email

Step 1: Registration Details
├─ Enter all user information
├─ Validate all fields
└─ Click "Continue to OTP"

Step 2: OTP Verification
├─ Enter 6-digit OTP from email
├─ Auto-submit on completion
└─ Navigate to MainScreen on success
```

## 🔌 API Endpoints

```
POST /api/auth/send-register-otp
Body: { "email": "user@example.com" }

POST /api/auth/register
Body: {
  "name": "...",
  "email": "...",
  "password": "...",
  "mobile": "...",
  "dob": "...",
  "gender": "...",
  "country": "...",
  "otp": "...",
  "privacyConsent": true,
  "hipaaConsent": true
}
```

## 💾 State Variables

```dart
int _currentStep = 0;           // 0=Email, 1=Form, 2=OTP
bool _loading = false;          // Async operation in progress
String _error = '';             // Error message to display

// Email step
bool _emailOtpSent = false;

// Form step
final _nameController = TextEditingController();
final _passwordController = TextEditingController();
final _confirmPasswordController = TextEditingController();
final _mobileController = TextEditingController();
final _dobController = TextEditingController();
String _selectedGender = '';
String _selectedCountry = '';
bool _obscurePassword = true;
bool _privacyConsent = false;
bool _hipaaConsent = false;

// OTP step
final _otpController = TextEditingController();
int _otpTimeoutSeconds = 60;
```

## 🎨 Design System

| Element | Color | Radius |
|---------|-------|--------|
| Primary | #1a3a5c (Dark Blue) | 16px |
| Secondary | #eaf2ff (Light Blue) | 22px |
| Background | #f9fafb (Light Gray) | - |
| Error | Colors.red | 12px |

## 🧪 Testing Quick Checks

```dart
// Check secure storage works
final token = await TokenStorageService().getToken();
assert(token != null);

// Check validation
assert(AuthValidators.isValidEmail('test@example.com'));
assert(!AuthValidators.isValidEmail('invalid'));

// Check model serialization
final req = RegisterRequest(...);
assert(req.toJson()['email'] != null);

// Check repository
final repo = AuthRepository();
assert(!await repo.isAuthenticated()); // Before login
```

## 📋 Navigation Patterns

```dart
// Navigate to register
Navigator.push(context, MaterialPageRoute(
  builder: (_) => const RegisterScreen(),
));

// Navigate with replacement (clear history)
Navigator.pushReplacement(context, MaterialPageRoute(
  builder: (_) => const MainScreen(),
));

// Navigate back
Navigator.pop(context);
```

## ⚠️ Common Pitfalls

| Issue | Solution |
|-------|----------|
| Token not persisted | Check flutter_secure_storage platform config |
| Password validation fails | Ensure uppercase, lowercase, number, symbol |
| OTP timeout not showing | Verify _otpTimeoutSeconds starts at 60 |
| Navigation doesn't work | Add mounted check before Navigator.push |
| Form doesn't validate | Ensure Form().validate() called |
| Controllers not disposed | Check dispose() method implementation |

## 🔍 Debugging Commands

```bash
# View logs
flutter logs

# Run with verbose
flutter run -v

# Check dependencies
flutter doctor -v

# Analyze code
flutter analyze

# Format code
dart format lib/

# Test widget
flutter test test/register_screen_test.dart
```

## 📞 Documentation Files

1. **REGISTER_SCREEN_DOCUMENTATION.md** - Full architecture docs
2. **REGISTER_INTEGRATION_GUIDE.md** - Step-by-step integration
3. **REGISTER_CODE_EXAMPLES.md** - 20 code examples
4. **REGISTER_IMPLEMENTATION_SUMMARY.md** - This file summary

## ✨ Features Checklist

- ✅ Multi-step registration form
- ✅ Email OTP verification
- ✅ Secure token storage (flutter_secure_storage)
- ✅ Input validation (email, password, DOB, etc.)
- ✅ Password strength requirements
- ✅ Loading states & error handling
- ✅ Responsive UI (mobile-first)
- ✅ Clean architecture (Repository pattern)
- ✅ Type-safe models
- ✅ Proper resource cleanup
- ✅ Accessibility features
- ✅ Production-ready code

## 🚨 Error Messages

| Scenario | Message |
|----------|---------|
| Invalid email | "Enter a valid email address" |
| Weak password | "Password must include uppercase, lowercase, number, symbol" |
| Passwords don't match | "Passwords do not match" |
| Invalid OTP | "Enter a valid 6-digit OTP" |
| Network error | "Cannot reach the server. Please check your internet connection" |
| API error | Returns server message |

## 📊 Performance Tips

- Use `mounted` check before setState
- Dispose controllers in dispose()
- Avoid rebuilding entire form on minor changes
- Use const constructors where possible
- Load countries from API (not hardcoded)
- Implement pagination for large lists

## 🔗 Integration Points

```dart
// LoginScreen → RegisterScreen
TextButton(
  onPressed: () => Navigator.push(context,
    MaterialPageRoute(builder: (_) => const RegisterScreen())),
  child: const Text('Sign Up'),
)

// RegisterScreen → MainScreen
Navigator.pushReplacement(context,
  MaterialPageRoute(builder: (_) => const MainScreen()))

// Any screen → User data
final profile = await AuthRepository().getUserProfile();

// Any screen → Logout
await AuthRepository().clearSession();
```

## 📈 Scalability

- ✅ Easy to add social auth (Google, Apple)
- ✅ Easy to add email verification link
- ✅ Easy to add multi-language support
- ✅ Easy to customize form fields
- ✅ Easy to add custom validation
- ✅ Easy to integrate with analytics

---

**Last Updated**: 2026-06-23  
**Status**: Production Ready ✅  
**Version**: 1.0.0

