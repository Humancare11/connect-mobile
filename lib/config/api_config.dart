import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  const ApiConfig._();

  static const String _defaultUatApiUrl = 'https://uat.humancareconnect.co/api';

  static String get baseUrl {
    final configuredBaseUrl =
        dotenv.env['API_BASE_URL'] ??
        dotenv.env['VITE_API_URL'] ??
        dotenv.env['BACKEND_URL'] ??
        _defaultUatApiUrl;

    var baseUrl = configuredBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (baseUrl.isEmpty) {
      baseUrl = _defaultUatApiUrl;
    }

    final uri = Uri.parse(baseUrl);
    final host = uri.host.toLowerCase();
    final allowProduction =
        dotenv.env['ALLOW_PRODUCTION_API']?.trim().toLowerCase() == 'true';

    if (!allowProduction &&
        host == 'humancareconnect.co' &&
        !host.startsWith('uat.')) {
      throw StateError(
        'Production API is disabled for this development build. '
        'Use https://uat.humancareconnect.co/api or set '
        'ALLOW_PRODUCTION_API=true intentionally.',
      );
    }

    if (!baseUrl.endsWith('/api')) {
      baseUrl = '$baseUrl/api';
    }

    return baseUrl;
  }
}
