# Flutter Register Screen - Architecture & Flow Diagrams

## 🏗️ Clean Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     UI LAYER (Screens)                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │           RegisterScreen (StatefulWidget)              │ │
│  │  ├─ buildEmailOtpStep()      (Step 0)                 │ │
│  │  ├─ buildRegistrationStep()   (Step 1)                │ │
│  │  └─ buildOtpVerificationStep() (Step 2)               │ │
│  └─────────────────────────────────────────────────────────┘ │
│              ↓                            ↓                    │
│   ┌──────────────────┐        ┌──────────────────┐            │
│   │ Form Validation  │        │ Error Handling   │            │
│   │ (validators)     │        │ (error display)  │            │
│   └──────────────────┘        └──────────────────┘            │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│                  BUSINESS LOGIC LAYER                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              AuthRepository                            │ │
│  │  ├─ sendRegisterOtp(email)                            │ │
│  │  ├─ register(RegisterRequest)                         │ │
│  │  ├─ getToken()                                        │ │
│  │  ├─ getUserProfile()                                  │ │
│  │  ├─ isAuthenticated()                                 │ │
│  │  └─ clearSession()                                    │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
           ↓                              ↓
┌──────────────────────┐    ┌──────────────────────────────┐
│  SERVICE LAYER       │    │  SERVICE LAYER               │
│                      │    │                              │
│  AuthService         │    │  TokenStorageService         │
│  ├─ login()          │    │  ├─ saveToken()             │
│  ├─ register()       │    │  ├─ getToken()              │
│  ├─ sendOtp()        │    │  ├─ saveUserProfile()       │
│  ├─ saveSession()    │    │  ├─ getUserProfile()        │
│  └─ googleLogin()    │    │  ├─ isAuthenticated()       │
│                      │    │  └─ clearAll()              │
└──────────────────────┘    └──────────────────────────────┘
           ↓                              ↓
┌──────────────────────┐    ┌──────────────────────────────┐
│  API LAYER           │    │  STORAGE LAYER               │
│                      │    │                              │
│  ApiClient           │    │  Flutter Secure Storage      │
│  ├─ post()           │    │  ├─ Auth tokens (encrypted) │
│  └─ get()            │    │                              │
│                      │    │  SharedPreferences           │
│                      │    │  └─ User profile (local)    │
└──────────────────────┘    └──────────────────────────────┘
           ↓                              ↓
┌──────────────────────────────────────────────────────────────┐
│              DATA MODELS (Type-safe)                          │
│  ├─ RegisterRequest      (API request)                        │
│  ├─ RegisterFormData     (Form state)                         │
│  ├─ AuthResponse         (API response)                       │
│  ├─ UserModel            (User data)                          │
│  └─ ApiResult<T>         (Generic result wrapper)             │
└──────────────────────────────────────────────────────────────┘
```

## 📱 Registration Flow Diagram

```
START
  │
  ▼
┌─────────────────────────────┐
│  Step 0: Email OTP          │
│  ├─ Enter email             │
│  ├─ Validate email          │
│  └─ Send OTP                │
└─────────────────────────────┘
  │
  ├─ Success ──────────────────┐
  │                            │
  │ Error → Show error msg    │
  │         ↑                  │
  │         └─ Retry          │
  │                            │
  ▼                            │
┌─────────────────────────────┐│
│  Step 1: Registration Form  ││
│  ├─ Enter name              ││
│  ├─ Enter password          ││
│  ├─ Enter mobile            ││
│  ├─ Enter DOB               ││
│  ├─ Select gender           ││
│  ├─ Select country          ││
│  ├─ Check consents          ││
│  ├─ Validate all fields     ││
│  └─ Continue to OTP         ││
└─────────────────────────────┘│
  │                            │
  ├─ Success ──────────────────┤
  │                            │
  │ Error → Show error msg    │
  │         Back to step 0    │
  │                            │
  ▼                            │
┌─────────────────────────────┐│
│  Step 2: OTP Verification   ││
│  ├─ Enter 6-digit OTP       ││
│  ├─ Validate OTP format     ││
│  ├─ Submit registration     ││
│  └─ Save session            ││
└─────────────────────────────┘│
  │                            │
  ├─ Success ──────────────────┤
  │                            │
  │ Error → Show error msg    │
  │         Back to step 1    │
  │                            │
  ▼                            │
┌─────────────────────────────┐│
│  Navigation                 ││
│  └─ MainScreen (Dashboard)  ││
└─────────────────────────────┘│
  │                            │
  ▼ (Always happens)           │
┌─────────────────────────────┐│
│  Token Storage              ││
│  ├─ Save auth token         ││
│  ├─ Save user profile       ││
│  └─ Mark as authenticated   ││
└─────────────────────────────┘│
  │                            │
  END ◄────────────────────────┘
```

## 🔐 Token Storage Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Token Storage Service                       │
│                                                         │
│  ┌──────────────────────┐    ┌──────────────────────┐  │
│  │ Flutter Secure       │    │ Shared Preferences   │  │
│  │ Storage              │    │                      │  │
│  │ (Encrypted)          │    │ (Local storage)      │  │
│  ├──────────────────────┤    ├──────────────────────┤  │
│  │ • Auth token         │    │ • User ID            │  │
│  │ • Refresh token      │    │ • User name          │  │
│  │ • Reset token        │    │ • User email         │  │
│  └──────────────────────┘    │ • User role          │  │
│         ▲                     │ • User mobile        │  │
│         │                     │ • User DOB           │  │
│    Platform-specific           │ • User gender        │  │
│    encryption:                 │ • User country       │  │
│    • iOS: Keychain             └──────────────────────┘  │
│    • Android: Keystore                                  │
└─────────────────────────────────────────────────────────┘
        ▲
        │
        └─────────────────────────────────────┐
                                              │
                                              ▼
                                   ┌─────────────────┐
                                   │  API Request    │
                                   │                 │
                                   │ Authorization:  │
                                   │ Bearer <token>  │
                                   └─────────────────┘
```

## 🔄 Data Flow Diagram

```
┌──────────────────┐
│  RegisterScreen  │
│  (UI)            │
└──────────────────┘
       │
       ├─ Enter email, click "Send OTP"
       │
       ▼
┌──────────────────────┐
│  AuthRepository      │
│  .sendRegisterOtp()  │
└──────────────────────┘
       │
       ▼
┌──────────────────────┐
│  AuthService         │
│  .sendRegisterOtp()  │
└──────────────────────┘
       │
       ▼
┌──────────────────────┐
│  ApiClient           │
│  .post() →           │
│  POST /api/auth/     │
│      send-register-otp
└──────────────────────┘
       │
       ▼
    ┌──────┐
    │ API  │
    └──────┘
       │
       ├─ If success: OTP sent
       │
       ▼
┌──────────────────────┐
│  Success Response    │
│  ├─ success: true    │
│  └─ message: "OTP sent"
└──────────────────────┘
       │
       ▼
┌──────────────────────┐
│  RegisterScreen      │
│  setState()          │
│  Step 1 Form         │
└──────────────────────┘
```

## 🧩 Component Interaction Diagram

```
                          ┌─────────────────┐
                          │ RegisterScreen  │
                          └────────┬────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
            ┌────────────┐  ┌────────────┐  ┌──────────┐
            │ Form State │  │ Validators │  │ Widgets  │
            │ Management │  │            │  │          │
            └────────────┘  └────────────┘  └──────────┘
                    │
                    ▼
        ┌────────────────────────┐
        │  AuthRepository        │
        │  (Business Logic)      │
        └────────┬───────────────┘
                 │
        ┌────────┴────────┐
        │                 │
        ▼                 ▼
    ┌──────────┐      ┌──────────────────┐
    │AuthService    │TokenStorageService│
    └──────────┘    └──────────────────┘
        │                 │
        ▼                 ▼
    ┌──────────┐      ┌─────────────┐
    │ApiClient │      │SharedPref/  │
    │          │      │FlutterSecure│
    └──────────┘      └─────────────┘
        │
        ▼
    ┌──────────┐
    │   API    │
    │ Endpoint │
    └──────────┘
```

## 📊 State Management Flow

```
┌────────────────────────────────────────────────────────┐
│              RegisterScreen State                       │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Step Management                                  │ │
│  │ ├─ _currentStep: 0 (Email) → 1 (Form) → 2 (OTP)│ │
│  │ └─ _emailOtpSent: true/false                    │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Form State                                       │ │
│  │ ├─ _nameController                              │ │
│  │ ├─ _passwordController                          │ │
│  │ ├─ _mobileController                            │ │
│  │ ├─ _dobController                               │ │
│  │ ├─ _selectedGender                              │ │
│  │ ├─ _selectedCountry                             │ │
│  │ ├─ _privacyConsent                              │ │
│  │ └─ _hipaaConsent                                │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ UI State                                         │ │
│  │ ├─ _loading: true/false (during async ops)      │ │
│  │ ├─ _error: error message or empty string        │ │
│  │ ├─ _obscurePassword: true/false                 │ │
│  │ ├─ _obscureConfirmPassword: true/false          │ │
│  │ └─ _otpTimeoutSeconds: 0-60                     │ │
│  └──────────────────────────────────────────────────┘ │
│                                                        │
│  ┌──────────────────────────────────────────────────┐ │
│  │ OTP State                                        │ │
│  │ ├─ _otpController                               │ │
│  │ ├─ _otpSentTime: DateTime                       │ │
│  │ └─ _otpTimeoutSeconds: int (60 → 0)            │ │
│  └──────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

## 🔐 Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Security Layers                       │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Layer 1: Input Validation                        │  │
│  │ ├─ Email format validation (RFC 5322)            │  │
│  │ ├─ Password strength requirements                │  │
│  │ ├─ Mobile number format                          │  │
│  │ ├─ DOB format and age validation                 │  │
│  │ └─ OTP format (6 digits)                         │  │
│  └──────────────────────────────────────────────────┘  │
│                        │                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Layer 2: Transport Security                      │  │
│  │ ├─ HTTPS/TLS for all requests                    │  │
│  │ ├─ Certificate pinning (recommended)             │  │
│  │ └─ 30-second timeout for requests                │  │
│  └──────────────────────────────────────────────────┘  │
│                        │                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Layer 3: Token Storage Security                  │  │
│  │ ├─ Flutter Secure Storage (encrypted)            │  │
│  │ │  ├─ iOS: Keychain                             │  │
│  │ │  └─ Android: Keystore                         │  │
│  │ └─ Never in SharedPreferences                    │  │
│  └──────────────────────────────────────────────────┘  │
│                        │                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Layer 4: Session Management                      │  │
│  │ ├─ Automatic token attachment                    │  │
│  │ ├─ Token refresh on expiry                       │  │
│  │ ├─ Secure logout (token cleared)                 │  │
│  │ └─ Atomic save/clear operations                  │  │
│  └──────────────────────────────────────────────────┘  │
│                        │                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Layer 5: Error Handling                          │  │
│  │ ├─ No sensitive data in error messages           │  │
│  │ ├─ Logging for debugging only                    │  │
│  │ └─ User-friendly error display                   │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 🎯 API Request/Response Flow

```
┌──────────────────────────────────────┐
│   Step 1: Send OTP                   │
│                                      │
│ Client Request:                      │
│ POST /api/auth/send-register-otp     │
│ {                                    │
│   "email": "user@example.com"        │
│ }                                    │
│                                      │
│ Server Response (Success):           │
│ {                                    │
│   "success": true,                   │
│   "message": "OTP sent"              │
│ }                                    │
└──────────────────────────────────────┘
              ▼
        User enters OTP
              ▼
┌──────────────────────────────────────┐
│   Step 2: Register User              │
│                                      │
│ Client Request:                      │
│ POST /api/auth/register              │
│ {                                    │
│   "name": "John Doe",                │
│   "email": "user@example.com",       │
│   "password": "SecurePass123!",      │
│   "mobile": "+1-555-0123",           │
│   "dob": "1990-01-15",               │
│   "gender": "Male",                  │
│   "country": "United States",        │
│   "otp": "123456",                   │
│   "privacyConsent": true,            │
│   "hipaaConsent": true               │
│ }                                    │
│                                      │
│ Server Response (Success):           │
│ {                                    │
│   "success": true,                   │
│   "token": "eyJhbGc...",             │
│   "user": {                          │
│     "id": "123",                     │
│     "name": "John Doe",              │
│     "email": "user@example.com",     │
│     "role": "patient",               │
│     "mobile": "+1-555-0123",         │
│     "dob": "1990-01-15",             │
│     "gender": "Male",                │
│     "country": "United States"       │
│   }                                  │
│ }                                    │
└──────────────────────────────────────┘
              ▼
   Token saved in secure storage
              ▼
   User profile saved locally
              ▼
   Navigate to MainScreen (Dashboard)
```

---

These diagrams provide a complete visual representation of the architecture, flows, and interactions within the Flutter Register Screen implementation.

