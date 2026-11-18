import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/screens/raise_ticket_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/ticket_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:humancare_connect/widgets/ticket_thread_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _ticket({
  String id = 't1',
  String status = 'open',
  List<Map<String, dynamic>>? messages,
  String? closedAt,
}) => {
  '_id': id,
  'ref': 'TCK-ABC123',
  'title': 'Reports not received',
  'description': 'I have not received my report',
  'category': 'technical',
  'status': status,
  'createdAt': '2026-11-07T10:00:00.000Z',
  'closedAt': ?closedAt,
  'messages':
      messages ??
      [
        {
          '_id': 'm1',
          'sender': 'user',
          'text': 'I have not received my report',
          'createdAt': '2026-11-07T10:00:00.000Z',
        },
        {
          '_id': 'm2',
          'sender': 'admin',
          'text': 'We are looking into it',
          'createdAt': '2026-11-07T11:00:00.000Z',
        },
      ],
};

class _FakeTicketService extends TicketService {
  _FakeTicketService(this.tickets);

  List<Map<String, dynamic>> tickets;
  ApiResult<Map<String, dynamic>>? replyResult;
  final replies = <String>[];
  int fetches = 0;

  @override
  Future<ApiResult<List<Map<String, dynamic>>>> fetchTickets({
    bool silent = false,
  }) async {
    fetches++;
    return ApiResult(success: true, message: '', data: tickets, statusCode: 200);
  }

  @override
  Future<ApiResult<Map<String, dynamic>>> replyToTicket({
    required String ticketId,
    required String text,
  }) async {
    replies.add(text);
    return replyResult ??
        ApiResult(
          success: true,
          message: 'Reply sent.',
          data: _ticket(
            id: ticketId,
            messages: [
              ..._ticket()['messages'] as List<Map<String, dynamic>>,
              {
                'sender': 'user',
                'text': text,
                'createdAt': '2026-11-07T12:00:00.000Z',
              },
            ],
          ),
          statusCode: 201,
        );
  }

  @override
  Future<List<Map<String, dynamic>>> loadCachedTickets() async => const [];

  @override
  Future<void> saveCachedTickets(List<Map<String, dynamic>> tickets) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TicketMessage.listFrom', () {
    test('parses sender, text and time', () {
      final list = TicketMessage.listFrom(_ticket()['messages']);
      expect(list, hasLength(2));
      expect(list.first.isMine, isTrue);
      expect(list.last.isMine, isFalse);
      expect(list.last.createdAt, isNotNull);
    });

    test('falls back to the description when there are no messages', () {
      final list = TicketMessage.listFrom(
        null,
        fallbackText: 'Old ticket text',
        fallbackAt: '2026-11-07T10:00:00.000Z',
      );
      expect(list, hasLength(1));
      expect(list.single.text, 'Old ticket text');
      expect(list.single.isMine, isTrue);
    });
  });

  group('TicketService.replyToTicket', () {
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
    ) => TicketService(
      apiClient: ApiClient(
        client: MockClient(handler),
        tokenStorage: const TokenStorageService(),
      ),
      tokenStorage: const TokenStorageService(),
    );

    test('posts {text} to /tickets/user/:id/reply and returns the ticket',
        () async {
      http.Request? seen;
      final service = serviceFor((request) async {
        seen = request;
        return http.Response(
          jsonEncode({'message': 'Reply sent.', 'ticket': _ticket()}),
          201,
        );
      });

      final result = await service.replyToTicket(
        ticketId: 't1',
        text: '  hello  ',
      );

      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/tickets/user/t1/reply');
      expect(jsonDecode(seen!.body), {'text': 'hello'});
      expect(result.success, isTrue);
      expect(result.data!['ref'], 'TCK-ABC123');
    });

    test('409 (ticket closed) is a failure with status 409', () async {
      final service = serviceFor(
        (_) async => http.Response(
          jsonEncode({'message': 'This ticket is resolved.'}),
          409,
        ),
      );

      final result = await service.replyToTicket(ticketId: 't1', text: 'hi');

      expect(result.success, isFalse);
      expect(result.statusCode, 409);
    });
  });

  group('TicketThreadView', () {
    Future<void> pumpThread(
      WidgetTester tester, {
      required bool closed,
      required Future<String?> Function(String) onSend,
    }) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TicketThreadView(
                messages: TicketMessage.listFrom(_ticket()['messages']),
                closed: closed,
                closedAt: DateTime(2026, 11, 8, 9, 30),
                onSend: onSend,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows both sides of the conversation, in order', (tester) async {
      await pumpThread(tester, closed: false, onSend: (_) async => null);

      expect(find.text('I have not received my report'), findsOneWidget);
      expect(find.text('We are looking into it'), findsOneWidget);
      expect(find.textContaining('You · '), findsOneWidget);
      expect(find.textContaining('Humancare Support · '), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('I have not received my report')).dy,
        lessThan(tester.getTopLeft(find.text('We are looking into it')).dy),
      );
    });

    testWidgets('open: Send is disabled until text is typed, then sends',
        (tester) async {
      final sent = <String>[];
      await pumpThread(tester, closed: false, onSend: (text) async {
        sent.add(text);
        return null;
      });

      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'whitespace only');

      await tester.enterText(find.byType(TextField), '  thanks  ');
      await tester.pump();
      expect(button().onPressed, isNotNull);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();

      expect(sent, ['thanks']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
    });

    testWidgets('a failed send keeps the text and shows the error',
        (tester) async {
      await pumpThread(
        tester,
        closed: false,
        onSend: (_) async => 'Could not send your message. Please try again.',
      );

      await tester.enterText(find.byType(TextField), 'my message');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not send your message. Please try again.'),
          findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'my message');
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
    });

    testWidgets('closed: no reply box, shows the closed notice',
        (tester) async {
      await pumpThread(tester, closed: true, onSend: (_) async => null);

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Send'), findsNothing);
      expect(
        find.textContaining('This ticket was closed by support on 8 Nov 2026'),
        findsOneWidget,
      );
    });
  });

  group('RaiseTicketPage', () {
    Future<void> pumpPage(WidgetTester tester, _FakeTicketService service) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RaiseTicketPage(ticketService: service, enableRealtime: false),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('list shows the ref, the status and a "New reply" cue',
        (tester) async {
      await pumpPage(tester, _FakeTicketService([_ticket()]));

      expect(find.textContaining('TCK-ABC123'), findsOneWidget);
      expect(find.text('New reply'), findsOneWidget);
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('expanding a ticket shows the thread; replying appends it',
        (tester) async {
      final service = _FakeTicketService([_ticket()]);
      await pumpPage(tester, service);

      await tester.tap(find.text('Reports not received'));
      await tester.pump();

      expect(find.text('We are looking into it'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '').last,
        'Thank you',
      );
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();

      expect(service.replies, ['Thank you']);
      expect(find.text('Thank you'), findsOneWidget);
      // we answered, so the "New reply" cue is gone
      expect(find.text('New reply'), findsNothing);
    });

    testWidgets('resolved ticket has no reply box', (tester) async {
      final service = _FakeTicketService([
        _ticket(status: 'resolved', closedAt: '2026-11-08T09:30:00.000Z'),
      ]);
      await pumpPage(tester, service);

      await tester.tap(find.text('Reports not received'));
      await tester.pump();

      expect(find.textContaining('This ticket was closed by support'),
          findsOneWidget);
      expect(find.text('Send'), findsNothing);
      expect(find.text('New reply'), findsNothing);
    });

    testWidgets('409 on send turns the ticket into the closed state',
        (tester) async {
      final service = _FakeTicketService([_ticket()])
        ..replyResult = const ApiResult(
          success: false,
          message: 'This ticket is resolved.',
          statusCode: 409,
        );
      await pumpPage(tester, service);

      await tester.tap(find.text('Reports not received'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '').last, 'late');
      await tester.pump();
      // Support closed it meanwhile: the next list fetch returns it resolved.
      service.tickets = [
        _ticket(status: 'resolved', closedAt: '2026-11-08T09:30:00.000Z'),
      ];
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('This ticket was closed by support'),
          findsOneWidget);
      expect(find.text('Send'), findsNothing);
    });
  });
}
