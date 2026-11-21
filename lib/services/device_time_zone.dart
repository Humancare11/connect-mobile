import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's IANA time zone ("Asia/Kolkata"), the same kind of value the web
/// app sends (`Intl.DateTimeFormat().resolvedOptions().timeZone`). The backend
/// only accepts IANA names, not abbreviations like "IST".
///
/// Returns '' when it cannot be read (no platform plugin, an error, or no
/// answer within two seconds): callers leave the field out then, and never let
/// this lookup stop a ticket or a booking.
Future<String> deviceTimeZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone().timeout(
      const Duration(seconds: 2),
    );
    return info.identifier.trim();
  } catch (_) {
    return '';
  }
}
