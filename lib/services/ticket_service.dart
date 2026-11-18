import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_result.dart';
import '../utils/json_helpers.dart';
import 'api_client.dart';
import 'token_storage_service.dart';

class TicketService {
  TicketService({
    ApiClient? apiClient,
    TokenStorageService? tokenStorage,
    FlutterSecureStorage? secureStorage,
  }) : _apiClient = apiClient ?? ApiClient(),
       _tokenStorage = tokenStorage ?? const TokenStorageService(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final ApiClient _apiClient;
  final TokenStorageService _tokenStorage;
  // Ticket titles/descriptions can contain PHI (patients describing
  // symptoms), so this cache lives in flutter_secure_storage on mobile —
  // same reasoning as the profile fields in TokenStorageService. Kept as
  // plain SharedPreferences on web only, matching that same class's split.
  final FlutterSecureStorage _secureStorage;
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

  Future<ApiResult<List<Map<String, dynamic>>>> fetchTickets({
    bool silent = false,
  }) async {
    final isDoctor = await _isDoctor();
    // Same endpoints the web app uses: GET /api/tickets/user/my (patient) and
    // GET /api/tickets/my (doctor).
    final endpoint = isDoctor ? '/tickets/my' : '/tickets/user/my';

    final result = await _apiClient.get(endpoint, null, silent);

    if (result.success) {
      return ApiResult<List<Map<String, dynamic>>>(
        success: true,
        message: result.message,
        data: _ticketListFrom(result.data ?? <String, dynamic>{}),
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    // Every failure (including 404/405) is surfaced as an error — it must
    // never be rendered as "No tickets found".
    if (_isAuthFailure(result)) {
      return ApiResult<List<Map<String, dynamic>>>(
        success: false,
        message: 'Session expired. Please log in again.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<List<Map<String, dynamic>>>(
      success: false,
      message: result.message.isNotEmpty
          ? result.message
          : 'Unable to load tickets.',
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<List<Map<String, dynamic>>> loadCachedTickets() async {
    final key = await _cacheKey();
    final raw = kIsWeb
        ? (await SharedPreferences.getInstance()).getString(key)
        : await _readMigratingTicketCache(key);
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
    final key = await _cacheKey();
    final encoded = jsonEncode(tickets);
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, encoded);
      return;
    }
    await _secureStorage.write(key: key, value: encoded);
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

  // Lazily migrates a cache entry that was written to plaintext
  // SharedPreferences before this cache moved to secure storage — reads
  // secure storage first, and only on a miss falls back to (then clears)
  // the legacy plaintext copy. Mirrors TokenStorageService._readMigrating.
  Future<String?> _readMigratingTicketCache(String key) async {
    final secureValue = await _secureStorage.read(key: key);
    if (secureValue != null && secureValue.isNotEmpty) return secureValue;

    final prefs = await SharedPreferences.getInstance();
    final legacyValue = prefs.getString(key);
    if (legacyValue == null || legacyValue.isEmpty) return null;

    await _secureStorage.write(key: key, value: legacyValue);
    await prefs.remove(key);
    return legacyValue;
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

