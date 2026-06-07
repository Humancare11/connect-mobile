import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  const ApiConfig._();

  static String get baseUrl {
    final configuredBaseUrl = dotenv.env['API_BASE_URL'];

    if (configuredBaseUrl == null || configuredBaseUrl.trim().isEmpty) {
      throw StateError('API_BASE_URL is not configured in .env');
    }

    return configuredBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
  }
}
