import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/models/deletion_request_status.dart';
import 'package:humancare_connect/screens/delete_account_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/auth_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeletionRequestStatus _pending() => DeletionRequestStatus(
  status: 'pending',
  requestedAt: DateTime(2026, 11, 7),
);

class _FakeAuthService extends AuthService {
  _FakeAuthService(this.status);

  DeletionRequestStatus status;
  int statusCalls = 0;
  int cancelCalls = 0;
  ApiResult<DeletionRequestStatus>? cancelResult;
  ApiResult<void>? requestResult;

  @override
  Future<ApiResult<DeletionRequestStatus>> fetchDeletionStatus({
    bool silent = true,
  }) async {
    statusCalls++;
    return ApiResult(success: true, message: '', data: status, statusCode: 200);
  }

  @override
  Future<ApiResult<DeletionRequestStatus>> cancelAccountDeletion() async {
    cancelCalls++;
    return cancelResult ??
        const ApiResult(
          success: true,
          message: 'Account deletion request cancelled.',
          data: DeletionRequestStatus.none,
          statusCode: 200,
        );
  }

  @override
  Future<ApiResult<void>> requestAccountDeletion({String reason = ''}) async {
    return requestResult ??
        const ApiResult<void>(success: true, message: 'ok', statusCode: 201);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeletionRequestStatus.fromResponse', () {
    test('reads the user object', () {
      final s = DeletionRequestStatus.fromResponse({
        'user': {
          'deletionRequestStatus': 'pending',
          'deletionRequestedAt': '2026-11-07T10:00:00.000Z',
        },
      });
      expect(s.isPending, isTrue);
      expect(s.requestedAt, isNotNull);
    });

    test('defaults to none', () {
      final s = DeletionRequestStatus.fromResponse({'user': {}});
      expect(s.status, 'none');
      expect(s.isPending, isFalse);
      expect(s.requestedAt, isNull);
    });

    test('rejected', () {
      expect(
        DeletionRequestStatus.fromResponse({
          'user': {'deletionRequestStatus': 'rejected'},
        }).isRejected,
        isTrue,
      );
    });
  });

  group('AuthService deletion endpoints', () {
    setUp(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
    });

    AuthService serviceFor(
      Future<http.Response> Function(http.Request) handler,
    ) => AuthService(
      apiClient: ApiClient(
        client: MockClient(handler),
        tokenStorage: const TokenStorageService(),
      ),
    );

    test('fetchDeletionStatus reads /auth/me', () async {
      final paths = <String>[];
      final service = serviceFor((request) async {
        paths.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({
            'user': {
              'deletionRequestStatus': 'pending',
              'deletionRequestedAt': '2026-11-07T10:00:00.000Z',
            },
          }),
          200,
        );
      });

      final result = await service.fetchDeletionStatus();

      expect(paths, ['GET /api/auth/me']);
      expect(result.data!.isPending, isTrue);
    });

    test('cancelAccountDeletion posts to the cancel endpoint', () async {
      final calls = <String>[];
      final service = serviceFor((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          jsonEncode({
            'msg': 'Account deletion request cancelled.',
            'user': {'deletionRequestStatus': 'none'},
          }),
          200,
        );
      });

      final result = await service.cancelAccountDeletion();

      expect(calls, ['POST /api/auth/account-delete-request/cancel']);
      expect(result.success, isTrue);
      expect(result.data!.status, 'none');
    });

    test('cancel with nothing pending is a 400 failure', () async {
      final service = serviceFor(
        (_) async => http.Response(
          jsonEncode({'msg': 'There is no pending account deletion request to cancel.'}),
          400,
        ),
      );

      final result = await service.cancelAccountDeletion();

      expect(result.success, isFalse);
      expect(result.statusCode, 400);
    });
  });

  group('DeleteAccountScreen', () {
    Future<void> pump(WidgetTester tester, _FakeAuthService service) async {
      // Tall surface so the whole (lazily built) form is on screen.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: DeleteAccountScreen(authService: service)),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('none: shows the request form', (tester) async {
      await pump(tester, _FakeAuthService(DeletionRequestStatus.none));

      expect(find.text('Submit Deletion Request'), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
    });

    testWidgets('pending: shows the pending card with the date and cancel',
        (tester) async {
      await pump(tester, _FakeAuthService(_pending()));

      expect(find.textContaining('Deletion requested on November 7, 2026'),
          findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('Submit Deletion Request'), findsNothing);
    });

    testWidgets('rejected: notice and "again" button', (tester) async {
      await pump(
        tester,
        _FakeAuthService(const DeletionRequestStatus(status: 'rejected')),
      );

      expect(find.textContaining('previous deletion request was declined'),
          findsOneWidget);
      expect(find.text('Request Account Deletion Again'), findsOneWidget);
    });

    testWidgets('cancel returns to the form immediately (no dialog)',
        (tester) async {
      final service = _FakeAuthService(_pending());
      await pump(tester, service);

      await tester.tap(find.text('Cancel request'));
      await tester.pump();
      await tester.pump();

      expect(service.cancelCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Submit Deletion Request'), findsOneWidget);
    });

    testWidgets('cancel 400 refreshes the real state and shows the message',
        (tester) async {
      final service = _FakeAuthService(_pending())
        ..cancelResult = const ApiResult(
          success: false,
          message: 'There is no pending account deletion request to cancel.',
          statusCode: 400,
        );
      await pump(tester, service);
      service.status = DeletionRequestStatus.none; // an admin already decided

      await tester.tap(find.text('Cancel request'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(service.statusCalls, greaterThanOrEqualTo(2));
      expect(find.text('Submit Deletion Request'), findsOneWidget);
    });

    testWidgets('cancel network error shows an inline message',
        (tester) async {
      final service = _FakeAuthService(_pending())
        ..cancelResult = const ApiResult(
          success: false,
          message: 'Network error',
          statusCode: 0,
        );
      await pump(tester, service);

      await tester.tap(find.text('Cancel request'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining("couldn't reach the server"), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
    });
  });
}
