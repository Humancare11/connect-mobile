import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'config/api_config.dart';
import 'screens/login_screen.dart';
import 'screens/book_appointment_form_screen.dart';
import 'screens/book_appointment_payment_screen.dart';
import 'screens/book_appointment_confirmation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');
  final envFile = switch (appEnv) {
    'production' => '.env.production',
    'uat' => '.env.uat',
    _ => '.env',
  };
  await dotenv.load(fileName: envFile);
  debugPrint('[AppConfig] APP_ENV=$appEnv envFile=$envFile');
  debugPrint('[AppConfig] API_BASE_URL=${ApiConfig.baseUrl}');

  final stripeKey =
      dotenv.env['STRIPE_PUBLISHABLE_KEY'] ??
      dotenv.env['VITE_STRIPE_PUBLISHABLE_KEY'] ??
      '';
  if (stripeKey.trim().isNotEmpty && _supportsStripePaymentSheet) {
    Stripe.publishableKey = stripeKey.trim();
    Stripe.urlScheme = 'humancareconnect';
    Stripe.setReturnUrlSchemeOnAndroid = true;
    await Stripe.instance.applySettings();
    debugPrint(
      '[StripeConfig] publishableKey=${_redactPublishableKey(stripeKey.trim())} '
      'mode=${_stripeKeyMode(stripeKey.trim())} '
      'urlScheme=humancareconnect supportsPaymentSheet=true',
    );
  } else {
    debugPrint(
      '[StripeConfig] publishableKey=${stripeKey.trim().isEmpty ? "(missing)" : _redactPublishableKey(stripeKey.trim())} '
      'supportsPaymentSheet=$_supportsStripePaymentSheet',
    );
  }

  runApp(const MyApp());
}

bool get _supportsStripePaymentSheet {
  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String _redactPublishableKey(String value) {
  if (value.length <= 12) return value.isEmpty ? '(missing)' : '...';
  return '${value.substring(0, 7)}...${value.substring(value.length - 4)}';
}

String _stripeKeyMode(String value) {
  if (value.startsWith('pk_live_')) return 'live';
  if (value.startsWith('pk_test_')) return 'test';
  return 'unknown';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
      routes: {
        "/appointment-form": (context) => const AppointmentFormPage(),
        "/appointment-payment": (context) => const AppointmentPaymentPage(),
        "/appointment-confirmation": (context) =>
            const AppointmentConfirmationPage(),
      },
    );
  }
}
