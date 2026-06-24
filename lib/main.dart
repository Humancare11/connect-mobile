import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/login_screen.dart';
import 'screens/book_appointment_form_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'uat');
  final envFile = appEnv == 'production' ? '.env.production' : '.env.uat';
  await dotenv.load(fileName: envFile);
  runApp(const MyApp());
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
      },
    );
  }
}
