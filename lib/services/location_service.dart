import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../models/location_model.dart';

/// Fetches country/state/city data from the public countriesnow.space API.
///
/// Two things this has to work around, both of which surfaced as
/// "Unexpected response from location service (301)" during registration:
///
///   1. `dart:io` only auto-follows a redirect on POST when the status is 303
///      (see `isRedirect` in the SDK's http_impl.dart). The states and cities
///      endpoints are POSTs, so a 301 from the upstream CDN came straight back
///      to the caller with an HTML body that failed to decode. Redirects are
///      therefore followed here by hand.
///   2. The upstream is a free public API and fails intermittently, so a
///      single transient blip blocked the registration form. Transient
///      failures are retried with a short backoff.
class LocationService {
  LocationService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://countriesnow.space/api/v0.1/countries';

  /// Ceiling on a single attempt, and on all attempts put together. Retrying
  /// only helps if the user is still there to see the result, so the budget is
  /// what bounds the spinner — without it three attempts at the old 20s
  /// timeout could have left a dropdown spinning for over a minute.
  static const _attemptTimeout = Duration(seconds: 10);
  static const _totalBudget = Duration(seconds: 25);

  /// Delays before the 2nd and 3rd attempts. Short, because a human is
  /// waiting on a dropdown mid-form.
  static const List<Duration> _retryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  /// Redirect hops to follow before giving up and reporting the 3xx.
  static const int _maxRedirects = 3;

  static const Map<String, String> _getHeaders = {'Accept': 'application/json'};
  static const Map<String, String> _postHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  final http.Client _client;

  Future<ApiResult<List<Country>>> getCountries() async {
    return _fetch('/positions', parse: (decoded) {
      final raw = decoded['data'];
      final countries = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => Country.fromJson(_stringKeyed(e)))
                .where((c) => c.name.isNotEmpty)
                .toList()
          : <Country>[];
      countries.sort((a, b) => a.name.compareTo(b.name));
      return countries;
    });
  }

  Future<ApiResult<List<StateItem>>> getStates(String country) async {
    return _fetch(
      '/states',
      body: {'country': country},
      parse: (decoded) {
        final data = decoded['data'];
        final rawStates = data is Map ? data['states'] : null;
        return rawStates is List
            ? rawStates
                  .whereType<Map>()
                  .map((e) => StateItem.fromJson(_stringKeyed(e)))
                  .where((s) => s.name.isNotEmpty)
                  .toList()
            : <StateItem>[];
      },
    );
  }

  Future<ApiResult<List<String>>> getCities(String country, String state) async {
    return _fetch(
      '/state/cities',
      body: {'country': country, 'state': state},
      parse: (decoded) {
        final raw = decoded['data'];
        return raw is List
            ? raw
                  .map((e) => e?.toString() ?? '')
                  .where((s) => s.isNotEmpty)
                  .toList()
            : <String>[];
      },
    );
  }

  // ── Request pipeline ───────────────────────────────────────────────────────

  /// Runs a request and maps it onto an [ApiResult], so the three endpoints
  /// share one copy of the decode/error handling.
  Future<ApiResult<T>> _fetch<T>(
    String path, {
    Map<String, dynamic>? body,
    required T Function(Map<String, dynamic> decoded) parse,
  }) async {
    try {
      final response = await _send(path, body: body);

      final decoded = _decode(response);
      if (decoded == null) {
        return ApiResult(
          success: false,
          message: _unexpectedMessage(response),
          statusCode: response.statusCode,
        );
      }
      if (_hasError(decoded)) {
        return ApiResult(
          success: false,
          message: _errorMessage(decoded),
          statusCode: response.statusCode,
        );
      }

      return ApiResult(
        success: true,
        message: 'OK',
        data: parse(decoded),
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult(success: false, message: _friendlyError(error));
    }
  }

  /// Sends the request, retrying transient failures. Returns the last response
  /// when every attempt came back with a retriable status, so the caller can
  /// still report a real status code instead of a generic error.
  Future<http.Response> _send(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');

    final elapsed = Stopwatch()..start();
    http.Response? lastResponse;
    Object? lastError;

    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      if (attempt > 0) {
        final delay = _retryDelays[attempt - 1];
        // Don't start a wait we cannot afford to follow with a real attempt.
        if (elapsed.elapsed + delay >= _totalBudget) break;
        await Future<void>.delayed(delay);
      }

      final remaining = _totalBudget - elapsed.elapsed;
      if (remaining <= Duration.zero) break;
      final timeout = remaining < _attemptTimeout ? remaining : _attemptTimeout;

      try {
        final response = await _sendFollowingRedirects(uri, body, timeout);
        if (!_isTransientStatus(response.statusCode)) return response;
        lastResponse = response;
        lastError = null;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }

    if (lastResponse != null) return lastResponse;
    if (lastError != null) throw lastError;
    throw TimeoutException('Location request exceeded its time budget.');
  }

  /// Follows redirects by re-issuing the request against the `Location` header.
  ///
  /// On 301/302/303 the follow-up is sent as a GET with no body, per RFC 9110
  /// §15.4 and long-standing browser behaviour. That is not a detail we can
  /// skip: countriesnow.space has migrated its POST endpoints to query-string
  /// GETs and answers `POST /countries/states` with
  /// `301 → /countries/states/q?country=India`. Re-POSTing to that target
  /// returns another 301 with `/q?country=India` appended a second time, so
  /// preserving the method loops until the hop budget runs out. Following as a
  /// GET returns 200 with the data.
  ///
  /// 307/308 keep the method and body, which is the whole point of those two.
  Future<http.Response> _sendFollowingRedirects(
    Uri uri,
    Map<String, dynamic>? body,
    Duration timeout,
  ) async {
    var target = uri;
    var payload = body; // null means: send as GET
    late http.Response response;

    for (var hop = 0; hop <= _maxRedirects; hop++) {
      response = payload == null
          ? await _client.get(target, headers: _getHeaders).timeout(timeout)
          : await _client
                .post(target, headers: _postHeaders, body: jsonEncode(payload))
                .timeout(timeout);

      final location = response.headers['location']?.trim() ?? '';
      if (!_isFollowableRedirect(response.statusCode) || location.isEmpty) {
        return response;
      }

      // `resolve` handles both absolute URLs and site-relative paths.
      target = target.resolve(location);

      if (!_preservesMethod(response.statusCode)) payload = null;
    }

    // Hop budget spent — hand the 3xx back so it is reported, not looped on.
    return response;
  }

  static bool _isFollowableRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently || // 301
      statusCode == HttpStatus.found || // 302
      statusCode == HttpStatus.seeOther || // 303
      statusCode == HttpStatus.temporaryRedirect || // 307
      statusCode == HttpStatus.permanentRedirect; // 308

  static bool _preservesMethod(int statusCode) =>
      statusCode == HttpStatus.temporaryRedirect || // 307
      statusCode == HttpStatus.permanentRedirect; // 308

  /// Statuses worth a second attempt: upstream throttling and gateway errors.
  /// 4xx other than 429 means the request itself is wrong, so retrying it just
  /// makes the user wait longer for the same answer.
  static bool _isTransientStatus(int statusCode) =>
      statusCode == HttpStatus.requestTimeout || // 408
      statusCode == HttpStatus.tooManyRequests || // 429
      statusCode >= HttpStatus.internalServerError; // 5xx

  // ── Decoding ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _stringKeyed(Map value) =>
      value.map((key, value) => MapEntry(key.toString(), value));

  Map<String, dynamic>? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? _stringKeyed(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  bool _hasError(Map<String, dynamic> decoded) => decoded['error'] == true;

  String _errorMessage(Map<String, dynamic> decoded) {
    final msg = decoded['msg']?.toString().trim() ?? '';
    return msg.isNotEmpty ? msg : 'Request failed.';
  }

  String _unexpectedMessage(http.Response response) =>
      'Unexpected response from location service (${response.statusCode}).';

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The location service took too long to respond. Please try again.';
    }
    if (error is SocketException) {
      return 'Cannot reach the location service. Please check your internet connection.';
    }
    if (error is HandshakeException || error is TlsException) {
      return 'Secure connection to the location service failed.';
    }
    if (error is http.ClientException) {
      return 'Unable to connect to the location service.';
    }
    return 'Something went wrong while fetching location data.';
  }
}
