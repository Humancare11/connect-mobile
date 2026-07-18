import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_result.dart';
import '../utils/json_helpers.dart';
import 'api_client.dart';
import 'token_storage_service.dart';

class TicketService {
  TicketService({ApiClient? apiClient, TokenStorageService? tokenStorage})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final ApiClient _apiClient;
  final TokenStorageService _tokenStorage;
  static const String _ticketCacheKeyPrefix = 'support_tickets_cache';

  Future<ApiResult<Map<String, dynamic>>> createTicket({
    required String title,
    required String description,
    required String category,
  }) async {
    final isDoctor = await _isDoctor();

    final payload = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      if (!isDoctor)
        'category': category.trim().isEmpty ? 'other' : category.trim(),
    };

    final result = await _apiClient.post(
      isDoctor ? '/tickets/create' : '/tickets/user/create',
      payload,
    );

    return ApiResult<Map<String, dynamic>>(
      success: result.success,
      message: result.message,
      data: _normalizeTicket(result.data ?? <String, dynamic>{}, payload),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<List<Map<String, dynamic>>>> fetchTickets() async {
    final isDoctor = await _isDoctor();
    final endpoints = isDoctor
        ? const [
            '/tickets',
            '/tickets/doctor',
            '/tickets/my-tickets',
            '/tickets/doctor/my-tickets',
            '/tickets/doctor/all',
            '/tickets/doctor/list',
          ]
        : const [
            '/tickets/user',
            '/tickets/user/my-tickets',
            '/tickets/user/all',
            '/tickets/user/list',
            '/tickets/user/tickets',
            '/tickets/my-tickets',
          ];

    ApiResult<Map<String, dynamic>>? lastFailure;

    for (final endpoint in endpoints) {
      final result = await _apiClient.get(endpoint);
      if (result.success) {
        return ApiResult<List<Map<String, dynamic>>>(
          success: true,
          message: result.message,
          data: _ticketListFrom(result.data ?? <String, dynamic>{}),
          raw: result.raw,
          statusCode: result.statusCode,
        );
      }

      lastFailure = result;
      if (_shouldTryNextTicketEndpoint(result)) {
        continue;
      } else {
        break;
      }
    }

    if (lastFailure != null && _isAuthFailure(lastFailure)) {
      // Expired/invalid auth was previously treated identically to
      // "endpoint not found" and silently rendered as an empty ticket list
      // (success:true, data:[]) — a user whose session expired saw "No
      // tickets found" with no indication they needed to log in again.
      return ApiResult<List<Map<String, dynamic>>>(
        success: false,
        message: 'Session expired. Please log in again.',
        raw: lastFailure.raw,
        statusCode: lastFailure.statusCode,
      );
    }

    if (lastFailure == null ||
        _shouldTreatMissingTicketListAsEmpty(lastFailure)) {
      return ApiResult<List<Map<String, dynamic>>>(
        success: true,
        message: '',
        data: const <Map<String, dynamic>>[],
        raw: lastFailure?.raw ?? const <String, dynamic>{},
        statusCode: lastFailure?.statusCode ?? 0,
      );
    }

    return ApiResult<List<Map<String, dynamic>>>(
      success: false,
      message: lastFailure?.message.isNotEmpty == true
          ? lastFailure!.message
          : 'Unable to load tickets.',
      raw: lastFailure?.raw ?? const <String, dynamic>{},
      statusCode: lastFailure?.statusCode ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> loadCachedTickets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _cacheKey());
    if (raw == null || raw.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Map<String, dynamic>>[];

      return decoded
          .whereType<Map>()
          .map((ticket) {
            return ticket.map((key, value) => MapEntry(key.toString(), value));
          })
          .toList();
    } on FormatException {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> saveCachedTickets(List<Map<String, dynamic>> tickets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _cacheKey(), jsonEncode(tickets));
  }

  Map<String, dynamic> _normalizeTicket(
    Map<String, dynamic> data,
    Map<String, dynamic> fallback,
  ) {
    final responseData = asMap(data['data']);
    final ticket = firstNonEmptyMap([
      data['ticket'],
      responseData['ticket'],
      responseData,
      data,
    ]);

    return {
      ...fallback,
      ...ticket,
      'category': ticket['category'] ?? fallback['category'] ?? 'other',
      'status': ticket['status'] ?? 'open',
      'createdAt': ticket['createdAt'] ?? DateTime.now().toIso8601String(),
    };
  }

  Future<bool> _isDoctor() async {
    final profile = await _tokenStorage.getUserProfile();
    return (profile['role'] ?? '').trim().toLowerCase() == 'doctor';
  }

  Future<String> _cacheKey() async {
    final profile = await _tokenStorage.getUserProfile();
    final userId = (profile['userId'] ?? '').trim();
    final email = (profile['email'] ?? '').trim().toLowerCase();
    final owner = userId.isNotEmpty ? userId : email;

    return owner.isEmpty
        ? _ticketCacheKeyPrefix
        : '${_ticketCacheKeyPrefix}_$owner';
  }
}

bool _isAuthFailure(ApiResult<Map<String, dynamic>> result) {
  return result.statusCode == 401 || result.statusCode == 403;
}

bool _shouldTryNextTicketEndpoint(ApiResult<Map<String, dynamic>> result) {
  // 401/403 means "wrong identity for this resource," not "wrong URL" — an
  // auth failure will happen identically on every remaining endpoint, and
  // trying them all just delays surfacing the real problem (an expired
  // session) to the user. Stop immediately instead.
  if (_isAuthFailure(result)) return false;
  return [404, 405].contains(result.statusCode) ||
      result.message.startsWith('Unexpected response from the server');
}

bool _shouldTreatMissingTicketListAsEmpty(
  ApiResult<Map<String, dynamic>> result,
) {
  return [404, 405].contains(result.statusCode) ||
      result.message.startsWith('Unexpected response from the server');
}

List<Map<String, dynamic>> _ticketListFrom(Map<String, dynamic> data) {
  final responseData = asMap(data['data']);
  final nestedData = asMap(responseData['data']);
  final candidates = [
    data['tickets'],
    data['ticket'],
    data['userTickets'],
    data['doctorTickets'],
    data['items'],
    data['results'],
    responseData['tickets'],
    responseData['ticket'],
    responseData['userTickets'],
    responseData['doctorTickets'],
    responseData['items'],
    responseData['results'],
    nestedData['tickets'],
    nestedData['ticket'],
    nestedData['userTickets'],
    nestedData['doctorTickets'],
    nestedData['items'],
    nestedData['results'],
    data['data'],
    responseData['data'],
  ];

  for (final candidate in candidates) {
    final tickets = _asMapList(candidate);
    if (tickets.isNotEmpty) return tickets;
  }

  return const <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  final map = asMap(value);
  if (_isTicketLike(map)) return [map];

  return const <Map<String, dynamic>>[];
}

bool _isTicketLike(Map<String, dynamic> map) {
  return map.containsKey('_id') ||
      map.containsKey('id') ||
      map.containsKey('title') ||
      map.containsKey('description') ||
      map.containsKey('status') ||
      map.containsKey('category');
}

