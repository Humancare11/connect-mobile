import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/ticket_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'user_role': 'user',
    });
  });

  TicketService serviceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = MockClient(handler);
    return TicketService(
      apiClient: ApiClient(client: client, tokenStorage: const TokenStorageService()),
      tokenStorage: const TokenStorageService(),
    );
  }

  test('patient tickets are loaded from GET /tickets/user/my', () async {
    final paths = <String>[];
    final service = serviceFor((request) async {
      paths.add(request.url.path);
      return http.Response(
        jsonEncode([
          {'_id': 't1', 'title': 'Help', 'description': 'x', 'status': 'open'},
        ]),
        200,
      );
    });

    final result = await service.fetchTickets(silent: true);

    expect(paths, ['/api/tickets/user/my']);
    expect(result.success, isTrue);
    expect(result.data, hasLength(1));
  });

  test('404 is an error, not an empty ticket list', () async {
    final paths = <String>[];
    final service = serviceFor((request) async {
      paths.add(request.url.path);
      return http.Response(jsonEncode({'msg': 'Not found'}), 404);
    });

    final result = await service.fetchTickets(silent: true);

    expect(paths, ['/api/tickets/user/my'], reason: 'no guessed fallbacks');
    expect(result.success, isFalse);
    expect(result.statusCode, 404);
    expect(result.message, isNotEmpty);
  });
}
