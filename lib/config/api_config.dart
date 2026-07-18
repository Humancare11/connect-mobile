import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  const ApiConfig._();

  static const String _defaultUatApiUrl =
      'https://uat-api.humancareconnect.co/api';

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

    // Previously only exact-matched the bare apex domain
    // ("humancareconnect.co"), which — since that string can never itself
    // start with "uat." — made the second half of the check dead logic and
    // left this guard unable to catch a realistic production API subdomain
    // like "api.humancareconnect.co". Now matches the domain or any of its
    // subdomains, while still explicitly allowing UAT hosts through.
    final isHumancareDomain =
        host == 'humancareconnect.co' || host.endsWith('.humancareconnect.co');
    final isUatHost = host.startsWith('uat.') || host.startsWith('uat-');

    if (!allowProduction && isHumancareDomain && !isUatHost) {
      throw StateError(
        'Production API is disabled for this development build. '
        'Use https://uat-api.humancareconnect.co/api or set '
        'ALLOW_PRODUCTION_API=true intentionally.',
      );
    }

    if (!baseUrl.endsWith('/api')) {
      baseUrl = '$baseUrl/api';
    }

    return baseUrl;
  }
}
