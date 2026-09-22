import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'config/api_config.dart';
import 'config/app_design_system.dart';
import 'screens/auth_gate_screen.dart';
import 'screens/book_appointment_form_screen.dart';
import 'screens/book_appointment_payment_screen.dart';
import 'screens/book_appointment_confirmation_screen.dart';
import 'services/idle_session_timer.dart';
import 'services/notification_service.dart';
import 'widgets/connectivity_gate.dart';
import 'widgets/idle_activity_listener.dart';
import 'widgets/loading_overlay.dart';
import 'widgets/session_expired_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One bundled `.env`, loaded by every build. Local development and release
  // builds all target the production backend — there is no environment switch.
  //
  // Independent of each other — loading them in parallel instead of one
  // after the other shaves a full await off the time to first frame.
  await Future.wait([
    dotenv.load(fileName: '.env'),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  ]);

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

  // Deferred until after the first frame is on screen. initialize() ends in
  // requestPermission(), which blocks on the OS notification-permission
  // dialog — running it before runApp() held the splash screen frozen
  // behind that dialog until the user responded, which read as the app
  // stalling/reloading rather than starting up. flushPendingNavigation()
  // is re-run on completion because a cold start from a tapped notification
  // sets its pending payload here, after MyApp's builder already ran once
  // with nothing to flush.
  unawaited(
    NotificationService.instance.initialize().then((_) {
      NotificationService.instance.flushPendingNavigation();
    }),
  );
}

bool get _supportsStripePaymentSheet {
  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String _redactPublishableKey(String value) {
  if (value.length <= 12) {
    return value.isEmpty ? '(missing)' : '...';
  }

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
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      // Screens that set no explicit fontFamily inherit Inter from here.
      // Headings opt into Plus Jakarta Sans via AppType.display.
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: AppFonts.body,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          surface: AppColors.surface,
        ),
      ),
      home: const AuthGateScreen(),
      routes: {
        "/appointment-form": (context) => const AppointmentFormPage(),
        "/appointment-payment": (context) => const AppointmentPaymentPage(),
        "/appointment-confirmation": (context) =>
            const AppointmentConfirmationPage(),
      },
      onGenerateRoute: NotificationService.instance.onGenerateRoute,
      navigatorObservers: [IdleActivityNavigatorObserver()],
      builder: (context, child) {
        NotificationService.instance.flushPendingNavigation();
        // IdleActivityListener wraps outermost (translucent — never
        // intercepts a gesture) so it observes taps/scrolls everywhere,
        // including on the gates' own overlays. SessionExpiredGate then
        // wraps ahead of ConnectivityGate so a dead session takes visual
        // priority over a transient "No Internet" flicker — in practice
        // the two barely overlap, since a 401 response can only arrive
        // once a request has actually reached the server.
        return IdleActivityListener(
          child: SessionExpiredGate(
            child: ConnectivityGate(
              child: LoadingOverlay(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
