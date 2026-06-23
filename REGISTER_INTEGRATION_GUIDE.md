## Quick Start Integration Guide

### Step 1: Install Dependencies

After adding `flutter_secure_storage` and `intl` to `pubspec.yaml`, run:

```bash
flutter pub get
```

### Step 2: Configure Platform-Specific Settings

#### iOS Configuration
Add to `ios/Podfile`:
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

Add to `ios/Runner/Info.plist`:
```xml
<key>UISupportsDocumentBrowserViewController</key>
<true/>
<key>UIMainStoryboardFile</key>
<string>Main</string>
```

#### Android Configuration
Add to `android/app/build.gradle`:
```gradle
android {
    compileSdkVersion 34
    targetSdkVersion 34
    
    defaultConfig {
        targetSdkVersion 34
    }
}
```

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### Step 3: Import Screens in main.dart

```dart
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
```

### Step 4: Add Navigation from Login Screen

Open `lib/screens/login_screen.dart` and add a sign-up link:

```dart
// In _LoginScreenState.build() after sign-in button

const SizedBox(height: 16),

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    const Text("Don't have an account? "),
    GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
        );
      },
      child: const Text(
        'Sign Up',
        style: TextStyle(
          color: Color(0xff1a3a5c),
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  ],
),
```

### Step 5: Update API Configuration

Verify `lib/config/api_config.dart` has correct API base URL:

```dart
class ApiConfig {
  static const String baseUrl = 'https://your-api-domain.com/api';
  // or use environment variable
  // static const String baseUrl = String.fromEnvironment('API_BASE_URL');
}
```

### Step 6: Test the Flow

Run the app:
```bash
flutter run
```

**Test Scenario:**
1. Navigate to Register Screen
2. Enter valid email → Send OTP
3. Enter registration details
4. Enter OTP from email
5. Verify navigation to MainScreen

### Step 7: Check Token Storage

#### Verify iOS Keychain Storage
```swift
// In Xcode, Debug → Breakpoints → Exception Breakpoint
// Add "Keychain Items" in Xcode Console
```

#### Verify Android Keystore Storage
```bash
adb shell
# Check EncryptedSharedPreferences
sqlite3 /data/data/com.example.hello_app/shared_prefs/flutter_secure_storage.xml
```

### File Structure

After implementation, your project structure should look like:

```
lib/
├── config/
│   ├── api_config.dart
│   └── app_design_system.dart
├── models/
│   ├── api_result.dart
│   ├── auth_response.dart
│   └── register_model.dart          ✨ NEW
├── services/
│   ├── api_client.dart              ✏️ UPDATED
│   ├── auth_service.dart            ✏️ UPDATED
│   ├── auth_repository.dart         ✨ NEW
│   ├── auth_validators.dart
│   ├── token_storage_service.dart   ✨ NEW
│   └── book_appointments_service.dart
├── screens/
│   ├── login_screen.dart            ✏️ UPDATED (add navigation)
│   ├── register_screen.dart         ✨ NEW
│   ├── main_screen.dart
│   └── ...other screens
├── widgets/
│   ├── auth_widgets.dart
│   └── ...other widgets
└── main.dart
```

### Verification Checklist

- [ ] `pubspec.yaml` includes `flutter_secure_storage: ^9.0.0`
- [ ] `pubspec.yaml` includes `intl: ^0.19.0`
- [ ] `flutter pub get` runs successfully
- [ ] No import errors in register_screen.dart
- [ ] No import errors in auth_repository.dart
- [ ] No import errors in token_storage_service.dart
- [ ] API_BASE_URL is correctly configured
- [ ] iOS build settings updated
- [ ] Android build settings updated
- [ ] RegisterScreen navigable from LoginScreen
- [ ] Registration completes successfully
- [ ] Token stored in secure storage
- [ ] Navigation to MainScreen works

### Testing with Mock Data

For development/testing without real API:

```dart
// In register_screen.dart, override _authRepository

// Replace:
final _authRepository = const AuthRepository();

// With:
final _authRepository = _createMockRepository();

AuthRepository _createMockRepository() {
  // Mock implementation for testing
  return AuthRepository();
}
```

### Debugging Tips

**Enable verbose logging:**
```bash
flutter run -v
```

**Add breakpoints in register_screen.dart:**
- After `_sendOtp()` completes
- Before navigation to MainScreen
- In error handlers

**Check token storage:**
```dart
// Add this in build method temporarily
final token = await _authRepository.getToken();
print('Current token: $token');
```

**Test network requests:**
```dart
// In lib/config/api_config.dart
const String baseUrl = 'https://httpbin.org/post';  // Test endpoint
```

### Common Issues & Solutions

**Issue: Build fails with gradle error**
```bash
# Solution: Clean build
flutter clean
flutter pub get
flutter pub get android
```

**Issue: Secure storage returns null**
```dart
// Solution: Check permissions
// iOS: Check Info.plist
// Android: Check AndroidManifest.xml
```

**Issue: OTP not received in email**
- Verify email address is correct
- Check spam folder
- Verify API endpoint logs for errors

**Issue: Navigation doesn't happen**
- Check mounted status
- Add error logging
- Verify MainScreen exists and no errors

### Next Steps

1. **Add logging:** Implement Firebase Crashlytics
2. **Add analytics:** Track registration funnel
3. **Add retry logic:** Handle transient network errors
4. **Add rate limiting:** Prevent OTP spam
5. **Add CAPTCHA:** Additional security
6. **Add email verification link:** As OTP fallback
7. **Add social registration:** Google/Apple sign-in
8. **Add biometric auth:** For app unlock

### Support & Troubleshooting

For issues:
1. Check the logs: `flutter logs`
2. Review API responses in Network tab
3. Verify all dependencies installed
4. Check platform-specific configuration
5. Test with debug APK/IPA

