import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/services/active_call_tracker.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/idle_session_timer.dart';
import 'package:humancare_connect/services/session_expired_service.dart';
import 'package:humancare_connect/services/session_logout.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The idle-timeout logout and the session-expired logout must use the same
/// flow as the manual logout (POST /auth/logout, FCM token deletion, clear
/// storage), and must never run while a video call is active.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = TokenStorageService();

  late List<http.Request> logoutCalls;
  late int fcmDeletes;

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access-token',
      'refresh_token': 'refresh-token',
      'user_id': 'abc',
      'user_role': 'user',
    });
    logoutCalls = [];
    fcmDeletes = 0;
    SessionLogout.shared = SessionLogout(
      httpClient: MockClient((request) async {
        logoutCalls.add(request);
        return http.Response('{"msg":"Logged out."}', 200);
      }),
      deleteFcmToken: () async => fcmDeletes++,
    );
    SessionExpiredService.instance.reset();
  });

  tearDown(() {
    IdleSessionTimer.instance.stop();
    while (ActiveCallTracker.instance.isActive) {
      ActiveCallTracker.instance.markInactive();
    }
    SessionExpiredService.instance.reset();
    SessionLogout.shared = SessionLogout();
  });

  void expectFullLogoutFlow() {
    expect(logoutCalls, hasLength(1));
    expect(logoutCalls.single.method, 'POST');
    expect(logoutCalls.single.url.path, '/api/auth/logout');
    expect(jsonDecode(logoutCalls.single.body), {
      'refreshToken': 'refresh-token',
    });
    expect(fcmDeletes, 1);
  }

  Future<void> expectStorageCleared() async {
    expect(await storage.getToken(), anyOf(isNull, isEmpty));
    expect(await storage.getRefreshToken(), anyOf(isNull, isEmpty));
  }

  test('background perform clears storage and still runs the server + FCM steps',
      () async {
    await SessionLogout.shared.perform(background: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expectFullLogoutFlow();
    await expectStorageCleared();
  });

  testWidgets('idle timeout runs the full logout flow', (tester) async {
    IdleSessionTimer.instance.start();

    await tester.pump(IdleSessionTimer.timeout + const Duration(minutes: 1));
    await tester.pump();

    expect(SessionExpiredService.instance.isExpired, isTrue);
    expectFullLogoutFlow();
    await expectStorageCleared();
  });

  testWidgets('idle timeout never logs out during a call, only after it ends',
      (tester) async {
    IdleSessionTimer.instance.start();
    ActiveCallTracker.instance.markActive();

    await tester.pump(IdleSessionTimer.callActiveTimeout + const Duration(minutes: 1));
    await tester.pump();

    expect(SessionExpiredService.instance.isExpired, isFalse);
    expect(logoutCalls, isEmpty);
    expect(await storage.getToken(), 'access-token');

    ActiveCallTracker.instance.markInactive();
    await tester.pump();
    await tester.pump();

    expect(SessionExpiredService.instance.isExpired, isTrue);
    expectFullLogoutFlow();
    await expectStorageCleared();
  });

  ApiClient deadSessionClient() => ApiClient(
    client: MockClient(
      (_) async => http.Response(jsonEncode({'msg': 'Unauthorized'}), 401),
    ),
    tokenStorage: storage,
  );

  test('a dead session (401 + failed refresh) runs the full logout flow', () async {
    final result = await deadSessionClient().get('/appointments/mine', null, true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(result.statusCode, 401);
    expect(SessionExpiredService.instance.isExpired, isTrue);
    expectFullLogoutFlow();
    await expectStorageCleared();
  });

  test('a dead session is not torn down during a call, only after it ends', () async {
    ActiveCallTracker.instance.markActive();

    await deadSessionClient().get('/appointments/mine', null, true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(SessionExpiredService.instance.isExpired, isFalse);
    expect(logoutCalls, isEmpty);
    expect(await storage.getToken(), 'access-token');

    ActiveCallTracker.instance.markInactive();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(SessionExpiredService.instance.isExpired, isTrue);
    expectFullLogoutFlow();
    await expectStorageCleared();
  });
}
