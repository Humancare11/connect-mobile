import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/ticket_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A new ticket carries the raiser's IANA time zone (web: `userTimezone`), so
/// support can see the local time it was raised at.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void signInAs(String role) {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'user_role': role,
    });
  }

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    signInAs('user');
  });

  /// Runs createTicket and returns the path and JSON body of the request.
  Future<({String path, Map<String, dynamic> body})> create({
    Future<String> Function()? timeZone,
  }) async {
    late String path;
    late Map<String, dynamic> body;
    final service = TicketService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          path = request.url.path;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'message': 'Ticket submitted successfully.',
              'ticket': {'_id': 't1', 'title': 'Help', 'status': 'open'},
            }),
            201,
          );
        }),
        tokenStorage: const TokenStorageService(),
      ),
      tokenStorage: const TokenStorageService(),
      timeZoneProvider: timeZone,
    );

    final result = await service.createTicket(
      title: ' Help ',
      description: ' Reports not received ',
      category: 'billing',
    );
    expect(result.success, isTrue);
    return (path: path, body: body);
  }

  test('a patient ticket sends the device time zone', () async {
    final request = await create(timeZone: () async => 'Asia/Kolkata');

    expect(request.path, '/api/tickets/user/create');
    expect(request.body, {
      'title': 'Help',
      'description': 'Reports not received',
      'category': 'billing',
      'userTimezone': 'Asia/Kolkata',
    });
  });

  test('a doctor ticket sends it too, without a category', () async {
    signInAs('doctor');

    final request = await create(timeZone: () async => 'America/New_York');

    expect(request.path, '/api/tickets/create');
    expect(request.body, {
      'title': 'Help',
      'description': 'Reports not received',
      'userTimezone': 'America/New_York',
    });
  });

  test('the zone is trimmed; an empty one is left out', () async {
    expect(
      (await create(timeZone: () async => '  Europe/London ')).body['userTimezone'],
      'Europe/London',
    );
    expect(
      (await create(timeZone: () async => '')).body.containsKey('userTimezone'),
      isFalse,
    );
  });

  test('a failing time zone lookup does not stop the ticket', () async {
    final asyncFailure = await create(timeZone: () async => throw StateError('no plugin'));
    expect(asyncFailure.path, '/api/tickets/user/create');
    expect(asyncFailure.body.containsKey('userTimezone'), isFalse);
    expect(asyncFailure.body['title'], 'Help');

    final syncFailure = await create(timeZone: () => throw StateError('no plugin'));
    expect(syncFailure.body.containsKey('userTimezone'), isFalse);
  });

  test('without an injected provider the real lookup is used and never throws', () async {
    // No platform plugin in unit tests: the lookup fails and the ticket is
    // still created, just without a zone.
    final request = await create();

    expect(request.path, '/api/tickets/user/create');
    expect(request.body['title'], 'Help');
  });
}
