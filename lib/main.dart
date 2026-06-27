import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'screens/login_screen.dart';
import 'screens/book_appointment_form_screen.dart';
import 'screens/book_appointment_payment_screen.dart';
import 'screens/book_appointment_confirmation_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'uat');
  final envFile = appEnv == 'production' ? '.env.production' : '.env.uat';
  await dotenv.load(fileName: envFile);

  final stripeKey =
      dotenv.env['STRIPE_PUBLISHABLE_KEY'] ??
      dotenv.env['VITE_STRIPE_PUBLISHABLE_KEY'] ??
      '';
  if (stripeKey.trim().isNotEmpty && _supportsStripePaymentSheet) {
    Stripe.publishableKey = stripeKey.trim();
    Stripe.urlScheme = 'humancareconnect';
    Stripe.setReturnUrlSchemeOnAndroid = true;
    await Stripe.instance.applySettings();
  }

  runApp(const MyApp());
}

bool get _supportsStripePaymentSheet {
  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
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
