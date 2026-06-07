import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/login_screen.dart';
import 'home_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart' as dot;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final loginRequired = (dot.dotenv.env['LOGIN_REQUIRED'] ?? 'true').toLowerCase() == 'true';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Humancare Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: loginRequired ? const LoginScreen() : const HomePage(),
    );
  }
}
