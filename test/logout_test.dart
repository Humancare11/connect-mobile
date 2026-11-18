import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/services/auth_repository.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access-token',
      'refresh_token': 'refresh-token',
      'user_role': 'user',
    });
  });

  const storage = TokenStorageService();

  test('logout posts the refresh token, deletes the FCM token, clears storage',
      () async {
    http.Request? seen;
    var fcmDeleted = false;
    final repo = AuthRepository(
      httpClient: MockClient((request) async {
        seen = request;
        return http.Response('{"msg":"Logged out."}', 200);
      }),
      deleteFcmToken: () async => fcmDeleted = true,
    );

    await repo.clearSession();

    expect(seen?.method, 'POST');
    expect(seen?.url.toString(), 'https://example.test/api/auth/logout');
    expect(jsonDecode(seen!.body), {'refreshToken': 'refresh-token'});
    expect(fcmDeleted, isTrue);
    expect(await storage.getToken(), anyOf(isNull, isEmpty));
    expect(await storage.getRefreshToken(), anyOf(isNull, isEmpty));
  });

  test('local storage is cleared even if the server call and FCM delete fail',
      () async {
    final repo = AuthRepository(
      httpClient: MockClient((_) async => throw http.ClientException('offline')),
      deleteFcmToken: () async => throw StateError('fcm unavailable'),
    );

    await repo.clearSession();

    expect(await storage.getToken(), anyOf(isNull, isEmpty));
    expect(await storage.getRefreshToken(), anyOf(isNull, isEmpty));
  });

  testWidgets('a hanging server call is abandoned after 8 seconds',
      (tester) async {
    var done = false;
    final repo = AuthRepository(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      deleteFcmToken: () async {},
    );

    unawaited(repo.clearSession().then((_) => done = true));
    await tester.pump(const Duration(seconds: 7));
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(done, isTrue);
  });
}
