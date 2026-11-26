import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../config/api_config.dart';
import '../services/appointment_tree_service.dart';
import '../services/auth_service.dart';
import '../services/currency_service.dart';
import '../services/device_time_zone.dart';
import '../services/payment_in_progress_tracker.dart';
import '../services/payment_service.dart';
import '../services/pricing_service.dart';
import '../services/razorpay_checkout.dart';
import '../services/token_storage_service.dart';
import '../utils/money.dart';
import '../utils/patient_profile.dart';
import '../utils/price_resolver.dart';
import '../utils/time_slots.dart';
import 'complete_details_screen.dart';

class AppointmentPaymentPage extends StatefulWidget {
  const AppointmentPaymentPage({super.key, this.clock, this.authService});

  /// The phone's local time; replaced in tests.
  final DateTime Function()? clock;

  /// Replaced in tests.
  final AuthService? authService;

  @override
  State<AppointmentPaymentPage> createState() => _AppointmentPaymentPageState();
}

class _AppointmentPaymentPageState extends State<AppointmentPaymentPage> {
  final _paymentService = PaymentService.instance;
  bool _processing = false;

  // Set once a Stripe charge has actually succeeded. If the subsequent
  // POST /appointments call fails (network blip, a transient backend error,
  // a validation bug), the card must not be charged again on retry — Stripe
  // would treat a fresh PaymentIntent as a second, separate charge. While
  // this is set, retrying finishes the booking with this same payment
  // reference instead of presenting the PaymentSheet again. Cleared on a
  // successful booking; also naturally reset if the user leaves this screen,
  // since a stale reference isn't reused across a fresh navigation.
  String? _succeededPaymentIntentId;

  // The rupee counterpart of the above: a Razorpay payment has gone through but
  // the booking has not been saved yet. It is also kept in secure storage (see
  // PendingRazorpayBookingStore), so the booking can still be finished after
  // the app was closed — `_pendingRazorpayArgs` is the booking it belongs to,
  // which then replaces whatever this screen was opened with.
  RazorpayPayment? _pendingRazorpay;
  Map<String, dynamic>? _pendingRazorpayArgs;
  num _pendingRazorpayAmount = 0;

  // Holds back the forced-update dialog (see PaymentInProgressTracker) while a
  // payment is running, and while a paid booking is still unsaved on this
  // screen: the Stripe reference above lives only in memory.
  bool _paymentRunning = false;
  bool _holdingUpdate = false;
  bool _closed = false;

  void _syncUpdateHold() {
    final unsaved =
        !_closed &&
        (_succeededPaymentIntentId != null || _pendingRazorpay != null);
    final hold = _paymentRunning || unsaved;
    if (hold == _holdingUpdate) return;
    _holdingUpdate = hold;
    final tracker = PaymentInProgressTracker.instance;
    hold ? tracker.markActive() : tracker.markInactive();
  }

  // The device's IANA time zone, looked up as soon as the screen opens so the
  // booking write (which happens right after a payment) never waits on it.
  late final Future<String> _timeZone;

  // The price is shown in the customer's currency, which the server decides
  // (see CurrencyService); the price table carries the EUR / GBP prices. What
  // is actually charged is decided by the server when the intent is created.
  final CurrencyService _currency = CurrencyService.instance;
  final PricingService _pricing = PricingService.instance;
  StreamSubscription<CurrencyChange>? _currencyChanges;
  // True while a refused charge is being explained: its message says the same
  // thing as the "prices updated" notice, so only one of them is shown.
  bool _explainingChange = false;

  @override
  void initState() {
    super.initState();
    _timeZone = deviceTimeZone();
    _currency.addListener(_onPriceInputsChanged);
    _pricing.addListener(_onPriceInputsChanged);
    _currencyChanges = _currency.changes.listen(_onCurrencyChanged);
    // A new booking screen asks the server again (at most every 20 s).
    _currency.ensureLoaded().then((_) => _currency.recheck());
    _pricing.ensureLoaded();
    _restorePendingRazorpay();
  }

  Future<String> _userId() async {
    final profile = await const TokenStorageService().getUserProfile();
    return (profile['userId'] ?? '').trim();
  }

  /// A rupee payment that was made but whose booking was never saved (the app
  /// was closed or the booking call failed): bring it back so the customer can
  /// finish the booking without paying again.
  Future<void> _restorePendingRazorpay() async {
    final saved = await PendingRazorpayBookingStore.instance.load(
      await _userId(),
    );
    if (!mounted || saved == null || _pendingRazorpay != null) return;
    setState(() {
      _pendingRazorpay = saved.payment;
      _pendingRazorpayArgs = saved.args;
      _pendingRazorpayAmount = saved.amount;
    });
    _syncUpdateHold();
  }

  Future<void> _clearPendingRazorpay() async {
    if (mounted) {
      setState(() {
        _pendingRazorpay = null;
        _pendingRazorpayArgs = null;
        _pendingRazorpayAmount = 0;
      });
    }
    await PendingRazorpayBookingStore.instance.clear(await _userId());
  }

  @override
  void dispose() {
    // A payment still running keeps its hold until it ends.
    _closed = true;
    _syncUpdateHold();
    _currency.removeListener(_onPriceInputsChanged);
    _pricing.removeListener(_onPriceInputsChanged);
    _currencyChanges?.cancel();
    super.dispose();
  }

  void _onPriceInputsChanged() {
    if (mounted) setState(() {});
  }

  void _onCurrencyChanged(CurrencyChange change) {
    // Both booking screens can be open at once: only the one in front says so.
    if (!mounted || _explainingChange) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(currencyChangeNotice(change.to)),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  PriceInfo _priceFor(Map<String, dynamic> args) {
    return selectionPriceInfo(
      selection: args,
      prices: _pricing.prices,
      currency: _currency.currency,
      currencyLoading: _currency.loading,
      pricesLoading: _pricing.loading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = _pendingRazorpayArgs ??
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        <String, dynamic>{};
    final price = _priceFor(args);
    final pendingBookingOnly =
        _succeededPaymentIntentId != null || _pendingRazorpay != null;

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
            _summary(args, price),
            const SizedBox(height: 18),
            _paymentCard(price),
            if (pendingBookingOnly) ...[
              const SizedBox(height: 18),
              _paymentReceivedCard(razorpay: _pendingRazorpay != null),
            ],
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
                // A booking that is already paid for only has to be finished,
                // whatever the price slot is doing.
                onPressed: _processing || (!pendingBookingOnly && price.loading)
                    ? null
                    : () => _payAndCreate(args),
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
                            : pendingBookingOnly
                            ? 'Complete Booking'
                            : price.ready && price.currency == 'INR'
                            ? 'Pay ${formatPrice(price.amount, price.currency)} with Razorpay'
                            : price.ready
                            ? 'Pay ${formatPrice(price.amount, price.currency)}'
                            : 'Pay',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> args, PriceInfo price) {
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
              if (price.loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  price.ready
                      ? formatPrice(price.amount, price.currency)
                      : 'Price unavailable',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff1a3a5c),
                  ),
                ),
            ],
          ),
          if (price.loading) ...[
            const SizedBox(height: 8),
            const Text(
              'Loading your price...',
              style: TextStyle(color: Colors.black54),
            ),
          ] else if (price.unavailable) ...[
            const SizedBox(height: 8),
            const Text(
              'The price is not available right now. Please go back and try again in a moment.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentCard(PriceInfo price) {
    // Customers in India pay in rupees through Razorpay only (the web hides
    // Stripe for them too).
    final rupees = price.currency == 'INR' && !_useLocalPaymentBypass;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rupees ? 'Online Payment' : 'Card Payment',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _useLocalPaymentBypass
                ? 'Local payment bypass is enabled. Stripe will be skipped for this development build.'
                : rupees
                ? 'Secure checkout is processed by Razorpay.'
                : 'Secure checkout is processed by Stripe. Your card details are not stored in this app.',
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
          if (rupees) ...[
            const SizedBox(height: 6),
            const Text(
              'UPI · Cards · Netbanking · Wallets',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentReceivedCard({bool razorpay = false}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _box().copyWith(color: const Color(0xffeefbf3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Received',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            // A rupee payment may have been made by UPI, not by card.
            '${razorpay ? 'Your payment has' : 'Your card has'} already been '
            'charged. We just need to finish saving your appointment — tap '
            'below to complete it. You will not be charged again.',
            style: const TextStyle(color: Colors.black87, height: 1.4),
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
    _paymentRunning = true;
    _syncUpdateHold();
    try {
      await _runPayment(args);
    } finally {
      _paymentRunning = false;
      _syncUpdateHold();
    }
  }

  Future<void> _runPayment(Map<String, dynamic> args) async {
    final priceType = _priceType(args);
    final priceRef = _priceRef(args, priceType);

    // Defensive re-check: this screen can in principle be reached without
    // going through the form screen's own validation (e.g. a future entry
    // point or a deep link), and an unresolved price would otherwise reach
    // the backend as an invalid $0 charge and fail with an opaque
    // "could not determine price" error deep inside the payment flow.
    // priceRef is checked too since it's what the backend actually resolves
    // the price from now — a missing category/service label would fail the
    // same way a missing cost would.
    if (_amount(args['cost']) <= 0 || priceRef.isEmpty) {
      _snack(
        'We couldn\'t determine a valid price for this selection. Please go back and choose again.',
      );
      return;
    }

    // A prior attempt already charged the card successfully but the booking
    // write afterwards failed (network blip, transient backend error, etc).
    // Retrying must finish the booking with that same payment reference
    // instead of going through Stripe again — a second PaymentIntent would
    // be a second, separate charge.
    final pendingPaymentIntentId = _succeededPaymentIntentId;
    if (pendingPaymentIntentId != null) {
      setState(() => _processing = true);
      try {
        await _finishBooking(args, _amount(args['cost']), pendingPaymentIntentId);
      } finally {
        if (mounted) setState(() => _processing = false);
      }
      return;
    }

    // The same for a rupee payment that is already made: finish its booking
    // with the saved reference, never charge again.
    final pendingRazorpay = _pendingRazorpay;
    if (pendingRazorpay != null) {
      setState(() => _processing = true);
      try {
        await _finishRazorpayBooking(
          args,
          _pendingRazorpayAmount > 0
              ? _pendingRazorpayAmount
              : _amount(args['cost']),
          pendingRazorpay,
        );
      } finally {
        if (mounted) setState(() => _processing = false);
      }
      return;
    }

    // Nothing has been paid yet (a paid booking is finished above, whatever
    // the time): never take money for a slot that has passed.
    if (_stopIfSlotPassed(args)) return;

    if (_useLocalPaymentBypass) {
      await _createAppointmentWithLocalPayment(args);
      return;
    }

    // Customers priced in rupees pay through Razorpay only.
    if (_priceFor(args).currency == 'INR') {
      await _payWithRazorpay(args, priceType, priceRef);
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

      // The USD price of the selection: what the booking records as its
      // consultationPrice (the server replaces it with what was really paid).
      final amount = _amount(args['cost']);

      // Right before anything is created at Stripe the customer's location is
      // asked again (no 20 s limit): the IP may have changed since the screen
      // opened. If the currency changed, the screen follows it at once (with
      // the "prices updated" notice) and nothing is created for the old one.
      final recheck = await _currency.recheck(force: true);
      if (!mounted) return;
      if (recheck.changed) return;
      await _pricing.refresh();
      if (!mounted) return;

      final shown = _priceFor(args);
      if (!shown.ready) {
        _snack(
          'The price is not available right now. Please go back and try again in a moment.',
        );
        return;
      }

      // Asked again: the checks above can take a while.
      if (_stopIfSlotPassed(args)) return;

      final intentResult = await _paymentService.createStripeIntent(
        priceType: priceType,
        priceRef: priceRef,
      );
      if (!mounted) return;

      final intent = intentResult.data;
      if (!intentResult.success || intent == null) {
        debugPrint(
          '[PaymentSheet] create-intent failed: ${intentResult.message}',
        );

        if (isProfileIncompleteResponse(
          intentResult.statusCode,
          intentResult.raw,
        )) {
          await _completeDetails();
          return;
        }

        // The backend resolves priceRef against its own current
        // HealthcareCategory/ServicePrice records — if the category or
        // service was renamed/removed after AppointmentTreeService cached
        // the tree (cache TTL is 2 minutes, easily longer than filling out
        // the booking form), this call fails with a "category/service not
        // recognized" style message even though the tree screen still shows
        // the now-stale option. Just showing the message and leaving the
        // user on this screen means retrying resends the same stale
        // priceRef and fails again. Clear the cache and send them back to
        // reselect so the next pick comes from a fresh fetch.
        if (_looksLikeStalePriceRefError(intentResult.message)) {
          AppointmentTreeService.invalidateCache();
          _snack(
            intentResult.message.isEmpty
                ? 'This option is no longer available. Please reselect and try again.'
                : '${intentResult.message} Please reselect and try again.',
          );
          final navigator = Navigator.of(context);
          navigator.pop();
          if (navigator.canPop()) navigator.pop();
          return;
        }

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

      // The price shown on this screen was never checked against what the
      // backend actually created a PaymentIntent for. If server-side pricing
      // had changed or diverged (a stale category price, the customer's
      // location) between the user seeing the summary and this call, the
      // Stripe sheet — and the real charge — could silently differ from what
      // the user consented to. Abort before presenting the sheet rather than
      // charging a different amount or currency than what was displayed.
      final check = checkCharge(
        intentAmountCents: intent.amountCents,
        intentCurrency: intent.currency,
        shownAmount: shown.amount!,
        shownCurrency: shown.currency,
      );
      if (check != ChargeCheck.ok) {
        debugPrint(
          '[PaymentSheet] Amount/currency mismatch ($check): displayed '
          '${formatPrice(shown.amount, shown.currency)} '
          '(${(shown.amount! * 100).round()} ${shown.currency}) but '
          'PaymentIntent is ${intent.amountCents} ${intent.currency}.',
        );
        await _explainChargeMismatch(check);
        return;
      }

      await _logPaymentIntentStatus(
        intent.clientSecret,
        phase: 'before initPaymentSheet',
      );
      const tokenStorage = TokenStorageService();
      final billingName = (await tokenStorage.getUserName())?.trim() ?? '';
      final billingEmail = (await tokenStorage.getUserEmail())?.trim() ?? '';
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          customFlow: false,
          paymentIntentClientSecret: intent.clientSecret,
          merchantDisplayName: 'Humancare Connect',
          primaryButtonLabel:
              'Pay ${formatPrice(shown.amount, shown.currency)}',
          style: ThemeMode.system,
          allowsDelayedPaymentMethods: false,
          // The signed-in patient's real name/email are attached to the
          // payment method (collection mode `never` below, so the sheet
          // doesn't re-ask). The address is left to the sheet to collect —
          // no placeholder address is ever sent to Stripe.
          billingDetails: BillingDetails(
            name: billingName.isEmpty ? null : billingName,
            email: billingEmail.isEmpty ? null : billingEmail,
          ),
          billingDetailsCollectionConfiguration:
              BillingDetailsCollectionConfiguration(
                name: billingName.isEmpty
                    ? CollectionMode.automatic
                    : CollectionMode.never,
                email: billingEmail.isEmpty
                    ? CollectionMode.automatic
                    : CollectionMode.never,
                phone: CollectionMode.never,
                address: AddressCollectionMode.automatic,
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

      final paymentIntentId = finalIntent.id.isNotEmpty
          ? finalIntent.id
          : intent.paymentIntentId;
      // The Stripe charge has now succeeded. From this point on, any
      // failure below (e.g. the /appointments call) must not cause a retry
      // to charge the card again — remember this reference so a retry
      // finishes the booking instead of presenting the PaymentSheet again.
      _succeededPaymentIntentId = paymentIntentId;

      await _finishBooking(args, amount, paymentIntentId);
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

  /// When the chosen slot has passed: says so and goes back to the booking
  /// form, which clears it.
  bool _stopIfSlotPassed(Map<String, dynamic> args) {
    final date = _parseDate(args['date']);
    final time = args['time']?.toString() ?? '';
    final now = (widget.clock ?? DateTime.now)();
    if (date == null || !isSlotPassed(date, time, now)) return false;
    _snack(kSlotPassedMessage);
    Navigator.of(context).maybePop();
    return true;
  }

  /// The server refused to start the payment because the profile has no date
  /// of birth or gender (nothing was created). The step opens on top of this
  /// screen; after saving, the patient taps Pay again: no automatic charge.
  Future<void> _completeDetails() async {
    final authService = widget.authService ?? AuthService();
    final details = await authService.fetchPatientDetails();
    if (!mounted) return;
    final saved = await CompleteDetailsScreen.open(
      context,
      dob: details?.dob ?? '',
      gender: details?.gender ?? '',
      authService: authService,
    );
    if (!mounted || !saved) return;
    _snack('Details saved. Tap Pay to continue.');
  }

  /// The server created a charge that is not what the screen shows. The screen
  /// is brought up to date and the customer is told why (nothing was paid).
  Future<void> _explainChargeMismatch(ChargeCheck check) async {
    if (check == ChargeCheck.currencyChanged) {
      // The customer's location changed: the screen is brought up to date
      // instead of charging in a currency that was not shown.
      _explainingChange = true;
      try {
        await _currency.recheck(force: true);
        await _pricing.refresh();
      } finally {
        _explainingChange = false;
      }
      _snack(
        'Your location changed, so the price was updated. Please check it and tap Pay again.',
      );
    } else {
      await _pricing.refresh();
      _snack(
        'The price for this appointment changed. Please go back and try again.',
      );
    }
  }

  /// Rupee payment through Razorpay Checkout, like the web: the server creates
  /// the order (amount and currency are its decision), Checkout collects the
  /// payment, and the three values it returns go to the booking request, where
  /// the server verifies them before anything is booked.
  Future<void> _payWithRazorpay(
    Map<String, dynamic> args,
    String priceType,
    String priceRef,
  ) async {
    setState(() => _processing = true);
    try {
      // The USD price of the selection: what the booking records as its
      // consultationPrice (the server replaces it with what was really paid).
      final amount = _amount(args['cost']);

      // Right before an order is created the customer's location is asked
      // again (no 20 s limit). If the currency changed, the screen follows it
      // and nothing is created for the old one.
      final recheck = await _currency.recheck(force: true);
      if (!mounted) return;
      if (recheck.changed) return;
      await _pricing.refresh();
      if (!mounted) return;

      final shown = _priceFor(args);
      if (!shown.ready) {
        _snack(
          'The price is not available right now. Please go back and try again in a moment.',
        );
        return;
      }
      if (shown.currency != 'INR') {
        // The price table no longer has a rupee price for this selection.
        _snack(
          'The price for this appointment changed. Please go back and try again.',
        );
        return;
      }

      // Asked again: the checks above can take a while.
      if (_stopIfSlotPassed(args)) return;

      final orderResult = await _paymentService.createRazorpayOrder(
        priceType: priceType,
        priceRef: priceRef,
      );
      if (!mounted) return;
      final order = orderResult.data;
      if (!orderResult.success || order == null) {
        if (isProfileIncompleteResponse(
          orderResult.statusCode,
          orderResult.raw,
        )) {
          await _completeDetails();
          return;
        }
        if (_looksLikeStalePriceRefError(orderResult.message)) {
          AppointmentTreeService.invalidateCache();
          _snack(
            '${orderResult.message} Please reselect and try again.',
          );
          final navigator = Navigator.of(context);
          navigator.pop();
          if (navigator.canPop()) navigator.pop();
          return;
        }
        _snack(
          orderResult.message.isEmpty
              ? kRazorpayStartFailedMessage
              : orderResult.message,
        );
        return;
      }

      final check = checkCharge(
        intentAmountCents: order.amountCents,
        intentCurrency: order.currency,
        shownAmount: shown.amount!,
        shownCurrency: shown.currency,
      );
      if (check != ChargeCheck.ok) {
        debugPrint(
          '[Razorpay] Amount/currency mismatch ($check): displayed '
          '${formatPrice(shown.amount, shown.currency)} but the order is '
          '${order.amountCents} ${order.currency}.',
        );
        await _explainChargeMismatch(check);
        return;
      }

      const tokenStorage = TokenStorageService();
      final profile = await tokenStorage.getUserProfile();
      final category = (args['catLabel']?.toString() ?? '').trim();
      final outcome = await RazorpayCheckout.launcher.open(
        RazorpayCheckout.buildOptions(
          keyId: order.keyId,
          orderId: order.orderId,
          amountPaise: order.amountCents,
          description:
              '${category.isEmpty ? 'Consultation' : category} booking fee',
          name: profile['name'] ?? '',
          email: profile['email'] ?? '',
          contact: profile['mobile'] ?? '',
        ),
      );
      if (!mounted) return;

      switch (outcome) {
        case RazorpayCancelled():
          _snack(kRazorpayCancelledMessage);
        case RazorpayFailed(:final message):
          _snack(message.isEmpty ? kRazorpayFailedMessage : message);
        case RazorpaySuccess(:final payment):
          // The customer has paid. From here on a failure must never lead to a
          // second charge: keep the payment (also across an app restart) until
          // the booking is saved.
          setState(() {
            _pendingRazorpay = payment;
            _pendingRazorpayArgs = args;
            _pendingRazorpayAmount = amount;
          });
          await PendingRazorpayBookingStore.instance.save(
            await _userId(),
            PendingRazorpayBooking(
              payment: payment,
              args: args,
              amount: amount,
            ),
          );
          await _finishRazorpayBooking(args, amount, payment);
      }
    } catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint('Razorpay payment failed: $error');
      debugPrint('$stackTrace');
      _snack(kRazorpayStartFailedMessage);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Saves the booking of a rupee payment that has been made. An answer in the
  /// 4xx range is final (the payment is refused, already used, the slot is
  /// gone): the saved payment is dropped so the customer is never stuck on
  /// "Complete Booking", and the server's message says what to do.
  Future<void> _finishRazorpayBooking(
    Map<String, dynamic> args,
    num amount,
    RazorpayPayment payment,
  ) async {
    final appointmentPayload = await _appointmentPayload(
      args,
      amount,
      '',
      razorpay: payment,
    );
    debugPrint(
      '[Razorpay] Creating paid appointment for payment=${payment.paymentId}',
    );
    final appointmentResult = await _paymentService.createPaidAppointment(
      appointmentPayload,
    );
    if (!mounted) return;

    if (!appointmentResult.success) {
      debugPrint(
        '[Razorpay] Appointment creation failed after successful payment: '
        'status=${appointmentResult.statusCode} '
        'message="${appointmentResult.message}"',
      );
      final status = appointmentResult.statusCode;
      if (status >= 400 && status < 500) await _clearPendingRazorpay();
      _snack(
        appointmentResult.message.isEmpty
            ? 'Appointment creation failed after payment. Please contact support.'
            : appointmentResult.message,
      );
      return;
    }
    await _clearPendingRazorpay();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/appointment-confirmation',
      (route) => route.isFirst,
      arguments: {
        ...args,
        'amount': amount,
        'paymentIntentId': payment.paymentId,
        'appointment': appointmentResult.data ?? <String, dynamic>{},
      },
    );
  }

  // Shared by both the first-attempt flow and the "payment already
  // succeeded, just retry the booking write" path above — the only
  // difference between them is whether a new Stripe charge happened first.
  Future<void> _finishBooking(
    Map<String, dynamic> args,
    num amount,
    String paymentIntentId,
  ) async {
    final appointmentPayload = await _appointmentPayload(
      args,
      amount,
      paymentIntentId,
    );
    debugPrint(
      '[PaymentSheet] Creating paid appointment for '
      'paymentIntentId=$paymentIntentId',
    );
    final appointmentResult = await _paymentService.createPaidAppointment(
      appointmentPayload,
    );
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
    _succeededPaymentIntentId = null;

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
  }

  Future<void> _createAppointmentWithLocalPayment(
    Map<String, dynamic> args,
  ) async {
    setState(() => _processing = true);

    final amount = _amount(args['cost']);
    final paymentIntentId =
        'local_payment_${DateTime.now().millisecondsSinceEpoch}';
    final appointmentPayload = await _appointmentPayload(
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

  Future<Map<String, dynamic>> _appointmentPayload(
    Map<String, dynamic> args,
    num amount,
    String paymentIntentId, {
    RazorpayPayment? razorpay,
  }) async {
    final date = _parseDate(args['date']) ?? DateTime.now();
    final time = args['time']?.toString() ?? '';
    final appointmentDateTime = _combineDateAndTime(date, time);
    // Already running since the screen opened, so this normally resolves at
    // once. '' (lookup failed) means the field is simply left out.
    final timeZone = await _timeZone;

    final serviceId = args['serviceId']?.toString() ?? '';
    final categoryId = args['catId']?.toString() ?? '';

    return {
      'category': args['catLabel']?.toString() ?? '',
      if (categoryId.isNotEmpty) 'categoryId': categoryId,
      'specialty': args['specName']?.toString() ?? '',
      'condition': args['condName']?.toString() ?? '',
      'consultationPrice': amount,
      'date': _apiDate(date),
      'time': time,
      'appointmentDateTimeUtc': appointmentDateTime.toUtc().toIso8601String(),
      if (timeZone.isNotEmpty) 'patientTimezone': timeZone,
      'problem': args['problem']?.toString() ?? '',
      'medicalReports': _medicalReports(args['medicalReports']),
      // Stripe sends the PaymentIntent id; Razorpay the three values Checkout
      // returned (the web's paymentFields()).
      if (razorpay != null)
        ...razorpay.toBookingFields()
      else
        'paymentIntentId': paymentIntentId,
      if (serviceId.isNotEmpty) 'serviceId': serviceId,
    };
  }

  List<Map<String, dynamic>> _medicalReports(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((report) => report.map((key, v) => MapEntry(key.toString(), v)))
        .toList();
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

  // Matches the web app's isServiceBooking split: the "Service" tiles flow
  // (medical_services_section.dart) tags its navigation args with
  // bookingType: 'service'; the category/specialty/condition tree flow
  // (book_appointment_screen.dart) never sets it, so it defaults to
  // 'category'.
  String _priceType(Map<String, dynamic> args) {
    return args['bookingType']?.toString() == 'service'
        ? 'service'
        : 'category';
  }

  // For 'service' this is ServicePrice.name (what specName carries for the
  // Service tiles flow, verbatim from GET /api/services). For 'category'
  // this prefers catId — the category's stable Mongo _id, carried through
  // the tree (see AppointmentTreeCategory.id) — over the display name in
  // catLabel. The backend accepts either, but catId survives a category
  // being renamed between fetching the tree and paying, where catLabel
  // would not: a rename in that window used to make this call fail with an
  // "unrecognized category" error after the tree screen had already shown
  // the option as bookable.
  String _priceRef(Map<String, dynamic> args, String priceType) {
    if (priceType == 'service') {
      return args['specName']?.toString().trim() ?? '';
    }
    final catId = args['catId']?.toString().trim() ?? '';
    if (catId.isNotEmpty) return catId;
    return args['catLabel']?.toString().trim() ?? '';
  }

  // Matches the backend's "priceRef didn't resolve to a known category/
  // service" failure without hard-coding its exact wording — only the
  // general shape (unrecognized/not found/no longer valid, scoped to a
  // category or service reference) so this doesn't misfire on unrelated
  // failures like a declined card or a network error.
  bool _looksLikeStalePriceRefError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.isEmpty) return false;
    if (!normalized.contains('categ') && !normalized.contains('service')) {
      return false;
    }
    return normalized.contains('unrecognized') ||
        normalized.contains('not recognized') ||
        normalized.contains('not found') ||
        normalized.contains('invalid') ||
        normalized.contains('no longer');
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
  // kReleaseMode is a genuine compile-time constant set by the Flutter build
  // tool itself (`flutter build ... --release`), not something any .env value
  // can override. A release build can never take this path — it would mark
  // appointments "paid" via a client-generated reference with no real Stripe
  // charge and no server-side proof of payment. The remaining checks only
  // gate it further for local development: the flag must be set *and* the
  // API base URL must point at a loopback host.
  if (kReleaseMode) return false;

  final enabled = _envFlag('LOCAL_PAYMENT_BYPASS') || _envFlag('DEV_BYPASS');
  return enabled && _isLocalApiBaseUrl;
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
