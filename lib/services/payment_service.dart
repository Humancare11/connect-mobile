import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/api_result.dart';
import 'api_client.dart';

class StripeIntent {
  const StripeIntent({
    required this.clientSecret,
    required this.amountCents,
    required this.currency,
    required this.livemode,
    this.id = '',
  });

  final String clientSecret;
  final int amountCents;
  final String currency;
  final bool? livemode;
  final String id;

  String get paymentIntentId {
    if (id.trim().isNotEmpty) return id.trim();

    final marker = clientSecret.indexOf('_secret_');
    if (marker <= 0) return '';
    return clientSecret.substring(0, marker);
  }
}

class PaymentService {
  PaymentService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<ApiResult<StripeIntent>> createStripeIntentByAmount(
    num amountUsd,
  ) async {
    final amountCents = (amountUsd * 100).round();
    debugPrint(
      '[PaymentService] create-intent request '
      'amountUsd=$amountUsd amountCents=$amountCents currency=usd',
    );

    final result = await _apiClient.post('/payments/create-intent-by-amount', {
      'amountUsd': amountUsd,
    });
    debugPrint(
      '[PaymentService] create-intent status=${result.statusCode} '
      'success=${result.success} message="${result.message}"',
    );
    debugPrint(
      '[PaymentService] create-intent raw=${jsonEncode(_redactSecrets(result.raw))}',
    );

    if (!result.success) {
      return ApiResult<StripeIntent>(
        success: false,
        message: result.message,
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    final data = result.data ?? <String, dynamic>{};
    final responseData = _asMap(data['data']);
    final nestedData = _asMap(responseData['data']);
    final intentData = _firstNonEmptyMap([
      data['paymentIntent'],
      data['intent'],
      responseData['paymentIntent'],
      responseData['intent'],
      nestedData['paymentIntent'],
      nestedData['intent'],
    ]);
    final clientSecret = _firstNonEmptyString([
      data['clientSecret'],
      data['client_secret'],
      data['paymentIntentClientSecret'],
      data['payment_intent_client_secret'],
      responseData['clientSecret'],
      responseData['client_secret'],
      responseData['paymentIntentClientSecret'],
      responseData['payment_intent_client_secret'],
      nestedData['clientSecret'],
      nestedData['client_secret'],
      nestedData['paymentIntentClientSecret'],
      nestedData['payment_intent_client_secret'],
      intentData['clientSecret'],
      intentData['client_secret'],
      _findFirstStringByKeys(data, const {
        'clientSecret',
        'client_secret',
        'paymentIntentClientSecret',
        'payment_intent_client_secret',
      }),
    ]);
    final paymentIntentId = _firstNonEmptyString([
      data['paymentIntentId'],
      data['payment_intent_id'],
      data['id'],
      responseData['paymentIntentId'],
      responseData['payment_intent_id'],
      responseData['id'],
      nestedData['paymentIntentId'],
      nestedData['payment_intent_id'],
      nestedData['id'],
      intentData['id'],
      _findFirstStringByKeys(data, const {
        'paymentIntentId',
        'payment_intent_id',
      }),
    ]);
    final parsedAmountCents = _firstNonZeroInt([
      data['amountCents'],
      data['amount_cents'],
      data['amount'],
      responseData['amountCents'],
      responseData['amount_cents'],
      responseData['amount'],
      nestedData['amountCents'],
      nestedData['amount_cents'],
      nestedData['amount'],
      intentData['amountCents'],
      intentData['amount_cents'],
      intentData['amount'],
    ]);
    final currency = _firstNonEmptyString([
      data['currency'],
      responseData['currency'],
      nestedData['currency'],
      intentData['currency'],
      _findFirstStringByKeys(data, const {'currency'}),
      'usd',
    ]).toLowerCase();
    final livemode = _firstBoolOrNull([
      data['livemode'],
      data['liveMode'],
      responseData['livemode'],
      responseData['liveMode'],
      nestedData['livemode'],
      nestedData['liveMode'],
      intentData['livemode'],
      intentData['liveMode'],
    ]);
    debugPrint(
      '[PaymentService] parsed clientSecret=${_redactClientSecret(clientSecret)} '
      'paymentIntentId=${paymentIntentId.isEmpty ? "(missing)" : paymentIntentId} '
      'amountCents=$parsedAmountCents currency=$currency livemode=$livemode',
    );

    if (clientSecret.isEmpty) {
      return ApiResult<StripeIntent>(
        success: false,
        message: 'Payment setup failed. Missing Stripe client secret.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    if (!clientSecret.contains('_secret_')) {
      return ApiResult<StripeIntent>(
        success: false,
        message: 'Payment setup failed. Invalid Stripe client secret.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<StripeIntent>(
      success: true,
      message: result.message,
      data: StripeIntent(
        clientSecret: clientSecret,
        amountCents: parsedAmountCents,
        currency: currency,
        livemode: livemode,
        id: paymentIntentId,
      ),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<Map<String, dynamic>>> createPaidAppointment(
    Map<String, dynamic> payload,
  ) {
    return _apiClient.post('/appointments', payload);
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _firstNonZeroInt(List<dynamic> values) {
    for (final value in values) {
      final parsed = _asInt(value);
      if (parsed > 0) return parsed;
    }

    return 0;
  }

  bool? _firstBoolOrNull(List<dynamic> values) {
    for (final value in values) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase() ?? '';
      if (text == 'true') return true;
      if (text == 'false') return false;
    }

    return null;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return <String, dynamic>{};
}

Map<String, dynamic> _firstNonEmptyMap(List<dynamic> values) {
  for (final value in values) {
    final map = _asMap(value);
    if (map.isNotEmpty) return map;
  }

  return <String, dynamic>{};
}

String _firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }

  return '';
}

String _findFirstStringByKeys(dynamic value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (keys.contains(key)) {
        final entryValue = entry.value;
        if (entryValue is String || entryValue is num || entryValue is bool) {
          final text = entryValue.toString().trim();
          if (text.isNotEmpty) return text;
        }
      }

      final nested = _findFirstStringByKeys(entry.value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (value is List) {
    for (final item in value) {
      final nested = _findFirstStringByKeys(item, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  return '';
}

String _redactClientSecret(String value) {
  if (value.isEmpty) return '(missing)';
  final marker = value.indexOf('_secret_');
  if (marker > 0) return '${value.substring(0, marker)}_secret_...';
  if (value.length <= 12) return '...';
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

dynamic _redactSecrets(dynamic value) {
  if (value is Map) {
    return value.map((key, mapValue) {
      final normalizedKey = key.toString().toLowerCase();
      if (normalizedKey.contains('clientsecret') ||
          normalizedKey.contains('client_secret')) {
        return MapEntry(
          key.toString(),
          _redactClientSecret(mapValue.toString()),
        );
      }

      return MapEntry(key.toString(), _redactSecrets(mapValue));
    });
  }

  if (value is List) {
    return value.map(_redactSecrets).toList();
  }

  return value;
}
