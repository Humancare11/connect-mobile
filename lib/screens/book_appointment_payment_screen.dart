import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../config/api_config.dart';
import '../services/payment_service.dart';

class AppointmentPaymentPage extends StatefulWidget {
  const AppointmentPaymentPage({super.key});

  @override
  State<AppointmentPaymentPage> createState() => _AppointmentPaymentPageState();
}

class _AppointmentPaymentPageState extends State<AppointmentPaymentPage> {
  final _paymentService = PaymentService();
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        <String, dynamic>{};
    final amount = _amount(args['cost']);

    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _progress(),
            const SizedBox(height: 18),
            _summary(args, amount),
            const SizedBox(height: 18),
            _paymentCard(),
            if (_useLocalPaymentBypass) ...[
              const SizedBox(height: 18),
              _localPaymentBypassCard(),
            ],
            if (_isStripeTestMode) ...[
              const SizedBox(height: 18),
              _testModeCard(),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff1a3a5c),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _processing ? null : () => _payAndCreate(args),
                child: _processing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _useLocalPaymentBypass
                            ? 'Create Test Appointment'
                            : 'Pay \$${_displayAmount(amount)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> args, num amount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointment Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _line('Category', args['catLabel']),
          _line('Specialty', args['specName']),
          _line('Condition', args['condName']),
          _line('Date', _formatDate(_parseDate(args['date']))),
          _line('Time', args['time']),
          const Divider(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                '\$${_displayAmount(amount)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xff1a3a5c),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Card Payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _useLocalPaymentBypass
                ? 'Local payment bypass is enabled. Stripe will be skipped for this development build.'
                : 'Secure checkout is processed by Stripe. Your card details are not stored in this app.',
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _localPaymentBypassCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box().copyWith(color: const Color(0xffeefbf3)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local Payment Bypass',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'This local build will mark the appointment as paid with a mock payment reference.',
            style: TextStyle(color: Colors.black87, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _testModeCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box().copyWith(color: const Color(0xfffffbeb)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stripe Test Mode',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'Use card 4242 4242 4242 4242, any future expiry date, any CVC, and any ZIP.',
            style: TextStyle(color: Colors.black87, height: 1.4),
          ),
          SizedBox(height: 6),
          Text(
            'Real cards will not complete while the app is using a test publishable key.',
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Row(
        children: const [
          _StepDot(text: '1', label: 'Details', active: true),
          Expanded(child: Divider(thickness: 2)),
          _StepDot(text: '2', label: 'Payment', active: true),
          Expanded(child: Divider(thickness: 2)),
          _StepDot(text: '3', label: 'Confirmed'),
        ],
      ),
    );
  }

  Future<void> _payAndCreate(Map<String, dynamic> args) async {
    if (_useLocalPaymentBypass) {
      await _createAppointmentWithLocalPayment(args);
      return;
    }

    if (!_supportsStripePaymentSheet) {
      _snack('Stripe card payment is available on Android and iOS builds.');
      return;
    }

    final stripeKey = _stripePublishableKey;
    if (stripeKey.isEmpty) {
      debugPrint('[PaymentSheet] Missing Stripe publishable key.');
      _snack('Payment is not configured. Missing Stripe publishable key.');
      return;
    }

    setState(() => _processing = true);

    try {
      debugPrint(
        '[PaymentSheet] Starting payment. '
        'amount=${_amount(args['cost'])} '
        'key=${_redactPublishableKey(stripeKey)}',
      );

      if (!_hasStripePublishableKey) {
        debugPrint('[PaymentSheet] Applying Stripe publishable key.');
        Stripe.publishableKey = stripeKey;
        await Stripe.instance.applySettings();
        debugPrint('[PaymentSheet] Stripe settings applied.');
      }

      final amount = _amount(args['cost']);
      final intentResult =
          await _paymentService.createStripeIntentByAmount(amount);
      if (!mounted) return;

      final intent = intentResult.data;
      if (!intentResult.success || intent == null) {
        debugPrint(
          '[PaymentSheet] create-intent failed: ${intentResult.message}',
        );
        _snack(intentResult.message);
        return;
      }

      debugPrint(
        '[PaymentSheet] initPaymentSheet() with '
        'clientSecret=${_redactClientSecret(intent.clientSecret)} '
        'paymentIntentId=${intent.paymentIntentId} '
        'amountCents=${intent.amountCents} '
        'currency=${intent.currency} '
        'intentLivemode=${intent.livemode} '
        'keyMode=${_stripeKeyMode(stripeKey)}',
      );
      _validateStripeMode(stripeKey, intent);

      await _logPaymentIntentStatus(
        intent.clientSecret,
        phase: 'before initPaymentSheet',
      );
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          customFlow: false,
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'Humancare Connect',
          primaryButtonLabel: 'Pay \$${_displayAmount(amount)}',
          style: ThemeMode.system,
          allowsDelayedPaymentMethods: false,
          billingDetails: const BillingDetails(
            name: 'Humancare Connect Patient',
            email: 'patient@example.com',
            address: Address(
              city: null,
              country: 'US',
              line1: null,
              line2: null,
              postalCode: '10001',
              state: null,
            ),
          ),
          billingDetailsCollectionConfiguration:
              const BillingDetailsCollectionConfiguration(
                name: CollectionMode.never,
                phone: CollectionMode.never,
                email: CollectionMode.never,
                address: AddressCollectionMode.never,
                attachDefaultsToPaymentMethod: true,
              ),
          linkDisplayParams: const LinkDisplayParams(
            linkDisplay: LinkDisplay.never,
          ),
          returnURL: 'humancareconnect://stripe-redirect',
        ),
      );
      debugPrint('[PaymentSheet] initPaymentSheet() completed.');

      debugPrint('[PaymentSheet] presentPaymentSheet() starting.');
      await Stripe.instance.presentPaymentSheet();
      debugPrint('[PaymentSheet] presentPaymentSheet() completed.');

      final finalIntent = await _logPaymentIntentStatus(
        intent.clientSecret,
        phase: 'after presentPaymentSheet',
      );
      if (!_isCompletedPayment(finalIntent.status)) {
        final message = _paymentStatusMessage(finalIntent.status);
        debugPrint(
          '[PaymentSheet] Blocking appointment creation because '
          'PaymentIntent ${finalIntent.id} status=${finalIntent.status.name}',
        );
        _snack(message);
        return;
      }

      final appointmentPayload = _appointmentPayload(
        args,
        amount,
        finalIntent.id.isNotEmpty ? finalIntent.id : intent.paymentIntentId,
      );
      debugPrint(
        '[PaymentSheet] Creating paid appointment for '
        'paymentIntentId=${appointmentPayload['paymentIntentId']}',
      );
      final appointmentResult =
          await _paymentService.createPaidAppointment(appointmentPayload);
      if (!mounted) return;

      if (!appointmentResult.success) {
        debugPrint(
          '[PaymentSheet] Appointment creation failed after successful payment: '
          'status=${appointmentResult.statusCode} '
          'message="${appointmentResult.message}"',
        );
        _snack(appointmentResult.message);
        return;
      }
      debugPrint('[PaymentSheet] Paid appointment created successfully.');

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/appointment-confirmation',
        (route) => route.isFirst,
        arguments: {
          ...args,
          'amount': amount,
          'paymentIntentId': finalIntent.id.isNotEmpty
              ? finalIntent.id
              : intent.paymentIntentId,
          'appointment': appointmentResult.data ?? <String, dynamic>{},
        },
      );
    } on StripeException catch (error) {
      if (!mounted) return;
      debugPrint(
        '[PaymentSheet] StripeException code=${error.error.code} '
        'message=${error.error.message} localized=${error.error.localizedMessage}',
      );
      final message =
          error.error.localizedMessage ??
          error.error.message ??
          'Payment was cancelled.';
      _snack(message);
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint('Payment failed: $error');
      debugPrint('$stackTrace');
      _snack('Payment failed. Please try again.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _createAppointmentWithLocalPayment(
    Map<String, dynamic> args,
  ) async {
    setState(() => _processing = true);

    final amount = _amount(args['cost']);
    final paymentIntentId =
        'local_payment_${DateTime.now().millisecondsSinceEpoch}';
    final appointmentPayload = _appointmentPayload(
      args,
      amount,
      paymentIntentId,
    );

    try {
      debugPrint(
        '[LocalPaymentBypass] Creating paid appointment for '
        'paymentIntentId=$paymentIntentId',
      );
      final appointmentResult =
          await _paymentService.createPaidAppointment(appointmentPayload);
      if (!mounted) return;

      if (!appointmentResult.success) {
        debugPrint(
          '[LocalPaymentBypass] Appointment creation failed: '
          'status=${appointmentResult.statusCode} '
          'message="${appointmentResult.message}"',
        );
        _snack(appointmentResult.message);
        return;
      }

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/appointment-confirmation',
        (route) => route.isFirst,
        arguments: {
          ...args,
          'amount': amount,
          'paymentIntentId': paymentIntentId,
          'appointment': appointmentResult.data ?? <String, dynamic>{},
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint('[LocalPaymentBypass] Appointment creation failed: $error');
      debugPrint('$stackTrace');
      _snack('Appointment booking failed. Please try again.');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<PaymentIntent> _logPaymentIntentStatus(
    String clientSecret, {
    required String phase,
  }) async {
    final paymentIntent = await Stripe.instance.retrievePaymentIntent(
      clientSecret,
    );
    debugPrint(
      '[PaymentSheet] PaymentIntent status $phase: '
      'id=${paymentIntent.id} '
      'status=${paymentIntent.status.name} '
      'amount=${paymentIntent.amount} '
      'currency=${paymentIntent.currency} '
      'livemode=${paymentIntent.livemode} '
      'paymentMethodId=${paymentIntent.paymentMethodId ?? "(none)"} '
      'captureMethod=${paymentIntent.captureMethod.name} '
      'confirmationMethod=${paymentIntent.confirmationMethod.name}',
    );
    return paymentIntent;
  }

  void _validateStripeMode(String publishableKey, StripeIntent intent) {
    final keyMode = _stripeKeyMode(publishableKey);
    if (keyMode == 'unknown') {
      debugPrint('[PaymentSheet] Unable to determine Stripe key mode.');
      return;
    }

    final intentLivemode = intent.livemode;
    if (intentLivemode == null) {
      debugPrint(
        '[PaymentSheet] Backend response did not include PaymentIntent livemode; '
        'Stripe retrievePaymentIntent() will log the authoritative mode.',
      );
      return;
    }

    final intentMode = intentLivemode ? 'live' : 'test';
    if (keyMode != intentMode) {
      throw StateError(
        'Stripe key mode mismatch. App is using a $keyMode publishable key, '
        'but the PaymentIntent is $intentMode.',
      );
    }
  }

  bool _isCompletedPayment(PaymentIntentsStatus status) {
    return status == PaymentIntentsStatus.Succeeded;
  }

  String _paymentStatusMessage(PaymentIntentsStatus status) {
    switch (status) {
      case PaymentIntentsStatus.RequiresPaymentMethod:
        return 'Payment was not completed. Please check the card details and try again.';
      case PaymentIntentsStatus.RequiresConfirmation:
        return 'Payment is waiting for confirmation. Please try again.';
      case PaymentIntentsStatus.RequiresAction:
        return 'Payment requires additional authentication. Please try again.';
      case PaymentIntentsStatus.Processing:
        return 'Payment is still processing. Please wait and try again.';
      case PaymentIntentsStatus.RequiresCapture:
        return 'Payment was authorized but not captured. Please contact support.';
      case PaymentIntentsStatus.Canceled:
        return 'Payment was cancelled.';
      case PaymentIntentsStatus.Unknown:
        return 'Payment status could not be confirmed. Please try again.';
      case PaymentIntentsStatus.Succeeded:
        return 'Payment successful.';
    }
  }

  Map<String, dynamic> _appointmentPayload(
    Map<String, dynamic> args,
    num amount,
    String paymentIntentId,
  ) {
    final date = _parseDate(args['date']) ?? DateTime.now();
    final time = args['time']?.toString() ?? '';
    final appointmentDateTime = _combineDateAndTime(date, time);

    return {
      'category': args['catLabel']?.toString() ?? '',
      'specialty': args['specName']?.toString() ?? '',
      'condition': args['condName']?.toString() ?? '',
      'consultationPrice': amount,
      'date': _apiDate(date),
      'time': time,
      'appointmentDateTimeUtc': appointmentDateTime.toUtc().toIso8601String(),
      'patientTimezone': DateTime.now().timeZoneName,
      'problem': args['problem']?.toString() ?? '',
      'medicalReports': const <dynamic>[],
      'paymentIntentId': paymentIntentId,
    };
  }

  DateTime _combineDateAndTime(DateTime date, String time) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(time.trim());
    if (match == null) return date;

    var hour = int.tryParse(match.group(1) ?? '') ?? 0;
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final period = (match.group(3) ?? '').toUpperCase();
    if (period == 'PM' && hour < 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  String _apiDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }

  num _amount(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _displayAmount(num amount) {
    if (amount == amount.roundToDouble()) return amount.round().toString();
    return amount.toStringAsFixed(2);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg.isEmpty ? 'Something went wrong.' : msg)),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}

bool get _supportsStripePaymentSheet {
  if (kIsWeb) return false;

  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String get _stripePublishableKey {
  return (dotenv.env['STRIPE_PUBLISHABLE_KEY'] ??
          dotenv.env['VITE_STRIPE_PUBLISHABLE_KEY'] ??
          '')
      .trim();
}

bool get _isStripeTestMode => _stripePublishableKey.startsWith('pk_test_');

bool get _useLocalPaymentBypass {
  const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');
  final enabled = _envFlag('LOCAL_PAYMENT_BYPASS') || _envFlag('DEV_BYPASS');
  return appEnv == 'local' && enabled && _isLocalApiBaseUrl;
}

bool _envFlag(String key) {
  final value = dotenv.env[key]?.trim().toLowerCase();
  return value == 'true' || value == '1' || value == 'yes';
}

bool get _isLocalApiBaseUrl {
  final uri = Uri.tryParse(ApiConfig.baseUrl);
  final host = uri?.host.toLowerCase() ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
}

bool get _hasStripePublishableKey {
  try {
    return Stripe.publishableKey.trim().isNotEmpty;
  } on StripeConfigException {
    return false;
  }
}

String _redactClientSecret(String value) {
  if (value.isEmpty) return '(missing)';
  final marker = value.indexOf('_secret_');
  if (marker > 0) return '${value.substring(0, marker)}_secret_...';
  if (value.length <= 12) return '...';
  return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
}

String _redactPublishableKey(String value) {
  if (value.length <= 12) return value.isEmpty ? '(missing)' : '...';
  return '${value.substring(0, 7)}...${value.substring(value.length - 4)}';
}

String _stripeKeyMode(String value) {
  if (value.startsWith('pk_live_')) return 'live';
  if (value.startsWith('pk_test_')) return 'test';
  return 'unknown';
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.text,
    required this.label,
    this.active = false,
  });

  final String text;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active ? const Color(0xff1a3a5c) : Colors.black12,
          child: Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
