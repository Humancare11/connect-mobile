import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  const ApiConfig._();

  // Fallback only — the bundled `.env` always defines the URL. Every build
  // (local development included) targets the production backend.
  static const String _defaultApiUrl = 'https://humancareconnect.co/api';

  static String get baseUrl {
    final configuredBaseUrl =
        dotenv.env['API_BASE_URL'] ??
        dotenv.env['VITE_API_URL'] ??
        dotenv.env['BACKEND_URL'] ??
        _defaultApiUrl;

    var baseUrl = configuredBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (baseUrl.isEmpty) {
      baseUrl = _defaultApiUrl;
    }

    if (!baseUrl.endsWith('/api')) {
      baseUrl = '$baseUrl/api';
    }

    return baseUrl;
  }
}
