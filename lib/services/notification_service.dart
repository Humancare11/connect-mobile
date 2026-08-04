import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../models/api_result.dart';
import '../screens/login_screen.dart';
import '../screens/main_screen.dart';
import '../screens/my_records_screen.dart';
import '../screens/video_call_screen.dart';
import 'api_client.dart';
import 'token_storage_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[Notifications] background message=${message.messageId}');
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const String channelId = 'humancare_connect_notifications';
  static const String channelName = 'Humancare Connect';
  static const String channelDescription =
      'Appointment, medical record, chat, and video call updates.';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final TokenStorageService _tokenStorage = const TokenStorageService();
  final ApiClient _apiClient = ApiClient();

  bool _initialized = false;
  String? _pendingPayload;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initializeLocalNotifications();
    await _createAndroidNotificationChannel();
    await requestPermission();
    await _configureForegroundPresentation();
    _listenForMessages();
    await _handleInitialMessage();
  }

  Future<void> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
        '[Notifications] permission=${settings.authorizationStatus.name}',
      );

      if (!kIsWeb && Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
    } catch (error, stackTrace) {
      debugPrint('[Notifications] permission request failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> syncTokenAfterLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) return;

      debugPrint('[Notifications] FCM token=${_redactToken(token)}');
      await _saveTokenToBackend(token);
    } catch (error, stackTrace) {
      debugPrint('[Notifications] token sync failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void flushPendingNavigation() {
    final payload = _pendingPayload;
    if (payload == null) return;
    _pendingPayload = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateFromPayload(payload);
    });
  }

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/home':
      case '/user/dashboard':
        return MaterialPageRoute(builder: (_) => const MainScreen());
      case '/appointments':
        final data = _asStringMap(settings.arguments);
        return MaterialPageRoute(
          builder: (_) => MainScreen(
            initialIndex: 1,
            appointmentId: _firstNonEmpty([
              data['appointmentId'],
              data['activityId'],
              data['id'],
            ]),
          ),
        );
      case '/book-appointment':
        return MaterialPageRoute(
          builder: (_) => const MainScreen(initialIndex: 2),
        );
      case '/records':
      case '/medical-records':
        final data = _asStringMap(settings.arguments);
        return MaterialPageRoute(
          builder: (_) => MyRecordsPage(
            initialTab: _firstNonEmpty([
              data['tab'],
              data['recordType'],
              data['type'],
            ], fallback: 'prescriptions'),
          ),
        );
      case '/video-call':
        final data = _asStringMap(settings.arguments);
        final appointmentId = _firstNonEmpty([
          data['appointmentId'],
          data['activityId'],
          data['id'],
        ]);
        if (appointmentId.isEmpty) return null;
        return MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            appointmentId: appointmentId,
            initialRole: data['role'] ?? 'user',
          ),
        );
    }

    return null;
  }

  Future<void> _initializeLocalNotifications() async {
    const initializationSettings = InitializationSettings(
      // Status-bar icon: must be a white-on-transparent silhouette, not the
      // full-color launcher icon — see res/drawable/ic_notification.xml.
      // AndroidNotificationDetails calls below that don't set an explicit
      // `icon` (e.g. _showForegroundNotification) inherit this default.
      android: AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) return;
        _navigateFromPayload(payload);
      },
    );
  }

  Future<void> _createAndroidNotificationChannel() async {
    if (kIsWeb || !Platform.isAndroid) return;

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _configureForegroundPresentation() async {
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _listenForMessages() {
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message.data);
    });
    _messaging.onTokenRefresh.listen((token) async {
      try {
        await _saveTokenToBackend(token);
      } catch (error, stackTrace) {
        debugPrint('[Notifications] token refresh sync failed: $error');
        debugPrint('$stackTrace');
      }
    });
  }

  Future<void> _handleInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message == null) return;

    _pendingPayload = jsonEncode(message.data);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      final title = notification?.title ?? message.data['title']?.toString();
      final body = notification?.body ?? message.data['body']?.toString();

      if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
        return;
      }

      await _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (error, stackTrace) {
      debugPrint('[Notifications] foreground notification failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    _navigateFromPayload(jsonEncode(data));
  }

  Future<void> _navigateFromPayload(String payload) async {
    try {
      final data = _asStringMap(jsonDecode(payload));
      final authenticated = await _tokenStorage.isAuthenticated();
      final navigator = navigatorKey.currentState;

      if (navigator == null) {
        _pendingPayload = payload;
        return;
      }

      if (!authenticated) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }

      final target = _notificationTarget(data);
      switch (target) {
        case _NotificationTarget.videoCall:
          final appointmentId = _appointmentId(data);
          if (appointmentId.isEmpty) {
            _openAppointments(navigator, data);
            return;
          }
          navigator.push(
            MaterialPageRoute(
              builder: (_) => VideoCallScreen(
                appointmentId: appointmentId,
                initialRole: data['role'] ?? 'user',
              ),
            ),
          );
          return;
        case _NotificationTarget.appointment:
          _openAppointments(navigator, data);
          return;
        case _NotificationTarget.records:
          navigator.push(
            MaterialPageRoute(
              builder: (_) => MyRecordsPage(initialTab: _recordsTab(data)),
            ),
          );
          return;
        case _NotificationTarget.booking:
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const MainScreen(initialIndex: 2),
            ),
            (route) => false,
          );
          return;
        case _NotificationTarget.home:
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
          return;
      }
    } catch (error, stackTrace) {
      debugPrint('[Notifications] tap navigation failed: $error');
      debugPrint('$stackTrace');
    }
  }

  void _openAppointments(NavigatorState navigator, Map<String, String> data) {
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            MainScreen(initialIndex: 1, appointmentId: _appointmentId(data)),
      ),
      (route) => false,
    );
  }

  // Before/after: a single failed attempt against a non-404/405 endpoint
  // (a transient 5xx, a timeout) used to `return` immediately with no log
  // and no retry — the device would silently stop receiving push
  // notifications until some unrelated future token-refresh happened to
  // succeed, possibly days later, with no visible signal anywhere.
  static const List<int> _fcmRetryDelaysMs = [1000, 3000];

  Future<void> _saveTokenToBackend(String token) async {
    final authenticated = await _tokenStorage.isAuthenticated();
    if (!authenticated) return;

    final profile = await _tokenStorage.getUserProfile();
    final payload = <String, dynamic>{
      'token': token,
      'fcmToken': token,
      'deviceToken': token,
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      if ((profile['userId'] ?? '').isNotEmpty) 'userId': profile['userId'],
    };

    for (final endpoint in const [
      '/notifications/fcm-token',
      '/notifications/device-token',
      '/auth/fcm-token',
      '/users/fcm-token',
    ]) {
      for (var attempt = 0; attempt <= _fcmRetryDelaysMs.length; attempt++) {
        final result = await _apiClient.post(endpoint, payload);
        if (_isAcceptedTokenResponse(result)) {
          debugPrint('[Notifications] token synced via $endpoint');
          return;
        }

        if (result.statusCode == 404 || result.statusCode == 405) {
          // Wrong endpoint shape for this backend deployment — try the
          // next candidate, not worth retrying this one.
          break;
        }

        if (attempt < _fcmRetryDelaysMs.length) {
          debugPrint(
            '[Notifications] token sync via $endpoint failed '
            '(status=${result.statusCode}), retrying...',
          );
          await Future.delayed(
            Duration(milliseconds: _fcmRetryDelaysMs[attempt]),
          );
          continue;
        }

        debugPrint(
          '[Notifications] token sync via $endpoint failed after retries '
          '(status=${result.statusCode}): ${result.message}',
        );
        return;
      }
    }

    debugPrint('[Notifications] token sync failed on all known endpoints.');
  }

  bool _isAcceptedTokenResponse(ApiResult<Map<String, dynamic>> result) {
    return result.success ||
        result.statusCode == 200 ||
        result.statusCode == 204;
  }

  _NotificationTarget _notificationTarget(Map<String, String> data) {
    final route = _normalized(
      data['route'] ?? data['screen'] ?? data['target'],
    );
    final type = _normalized(data['type'] ?? data['notificationType']);

    if (route.contains('video') || type.contains('video')) {
      return _NotificationTarget.videoCall;
    }
    if (route.contains('record') ||
        route.contains('prescription') ||
        route.contains('certificate') ||
        type.contains('prescription') ||
        type.contains('certificate')) {
      return _NotificationTarget.records;
    }
    if (route.contains('book')) return _NotificationTarget.booking;
    if (route.contains('appointment') ||
        type.contains('appointment') ||
        _appointmentId(data).isNotEmpty) {
      return _NotificationTarget.appointment;
    }

    return _NotificationTarget.home;
  }

  String _appointmentId(Map<String, String> data) {
    return _firstNonEmpty([
      data['appointmentId'],
      data['appointment_id'],
      data['activityId'],
      data['activity_id'],
      data['id'],
    ]);
  }

  String _recordsTab(Map<String, String> data) {
    final value = _normalized(
      _firstNonEmpty([data['tab'], data['recordType'], data['type']]),
    );
    return value.contains('certificate') ? 'certificates' : 'prescriptions';
  }

  Map<String, String> _asStringMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    }

    return <String, String>{};
  }

  String _firstNonEmpty(List<String?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  String _normalized(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  String _redactToken(String token) {
    if (token.length <= 12) return '...';
    return '${token.substring(0, 6)}...${token.substring(token.length - 4)}';
  }
}

enum _NotificationTarget { appointment, booking, home, records, videoCall }
