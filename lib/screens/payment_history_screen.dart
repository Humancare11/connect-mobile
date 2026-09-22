import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../models/payment_model.dart';
import '../services/payment_history_service.dart';

/// Patient billing dashboard — payment history with downloadable invoices.
///
/// Mirrors the web app's `/user/payment-history` page: the backend generates
/// and emails the invoice on its own right after a paid booking, and this
/// screen just surfaces it. A freshly booked payment shows up here
/// immediately with an "Generating…" invoice status, then flips to a
/// downloadable invoice number once the backend finishes — no app restart
/// needed (a short poll + pull-to-refresh + resume-refresh all keep it live).
class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({
    super.key,
    this.service,
    this.expectRecentPayment = false,
  });

  final PaymentHistoryService? service;

  /// Set when opened straight after a booking. The backend writes the
  /// `Payment` row *after* it returns the 201, so a first fetch can briefly
  /// race ahead of it — this keeps the screen polling for the full window
  /// even if the list momentarily looks settled, so the new payment and its
  /// invoice always show up without a manual refresh.
  final bool expectRecentPayment;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen>
    with WidgetsBindingObserver {
  late final PaymentHistoryService _service =
      widget.service ?? PaymentHistoryService();

  static const Color _bgCanvas = Color(0xFFF3F6F5);
  static const Color _errorBg = Color(0xFFFEF2F2);
  static const Color _errorBorder = Color(0xFFFCA5A5);
  static const Color _errorText = Color(0xFFDC2626);

  // How aggressively to chase a still-generating invoice before giving up and
  // leaving it to a manual refresh. 6 × 4s ≈ 24s, comfortably longer than the
  // backend's fire-and-forget PDF build normally takes.
  static const int _maxInvoicePolls = 6;
  static const Duration _invoicePollInterval = Duration(seconds: 4);
  static const Duration _minResumeRefreshGap = Duration(seconds: 5);

  List<PaymentRecord> _payments = const [];
  bool _loading = true;
  String _error = '';
  String _downloadingId = '';

  int _page = 1;
  int _totalPages = 1;

  // The single in-flight fetch, if any. Every trigger (first load,
  // pull-to-refresh, pagination, invoice poll, resume) funnels through
  // [_load], which returns this same future while a request is running so
  // callers — `RefreshIndicator.onRefresh` especially — await the real work
  // instead of racing a second request.
  Future<void>? _activeLoad;
  Timer? _invoicePollTimer;
  int _invoicePollAttempts = 0;
  DateTime? _lastFetchAt;
  late bool _expectRecentPayment = widget.expectRecentPayment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(page: 1, withLoader: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _invoicePollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastFetchAt;
    if (last != null && DateTime.now().difference(last) < _minResumeRefreshGap) {
      return;
    }
    _load(page: _page, withLoader: false);
  }

  // Single entry point for every fetch. While a request is in flight this
  // returns that same future rather than starting a second one, so
  // overlapping triggers (first load, pull-to-refresh, pagination, invoice
  // poll, resume) never fan out into duplicate requests and callers that
  // `await` it (RefreshIndicator) wait for the real work.
  Future<void> _load({
    required int page,
    required bool withLoader,
    bool isPoll = false,
  }) {
    final active = _activeLoad;
    if (active != null) return active;

    final future = _performLoad(page: page, withLoader: withLoader, isPoll: isPoll);
    _activeLoad = future;
    future.whenComplete(() {
      if (identical(_activeLoad, future)) _activeLoad = null;
    });
    return future;
  }

  Future<void> _performLoad({
    required int page,
    required bool withLoader,
    required bool isPoll,
  }) async {
    if (!isPoll) _invoicePollTimer?.cancel();
    if (withLoader && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    _lastFetchAt = DateTime.now();
    final result = await _service.fetchMyPayments(page: page, silent: true);
    if (!mounted) return;

    if (!result.success || result.data == null) {
      setState(() {
        _loading = false;
        // Keep whatever is already on screen on a background/poll failure;
        // only surface the error when the user is looking at a blank screen
        // or explicitly asked for data.
        if (withLoader || _payments.isEmpty) {
          _error = result.statusCode == 401
              ? 'Your session has expired. Please log in again to view your '
                    'payment history.'
              : result.message;
        }
      });
      if (isPoll) {
        // A transient poll failure still counts against the budget so a
        // flaky connection can't keep it retrying forever; reschedule the
        // next attempt if any remain.
        _invoicePollAttempts++;
        _scheduleInvoicePollIfNeeded();
      } else {
        _invoicePollAttempts = 0;
      }
      return;
    }

    final data = result.data!;
    setState(() {
      _payments = data.payments;
      _page = data.page;
      _totalPages = data.totalPages;
      _loading = false;
      _error = '';
    });

    if (isPoll) {
      _invoicePollAttempts++;
    } else {
      _invoicePollAttempts = 0;
    }
    _scheduleInvoicePollIfNeeded();
  }

  void _scheduleInvoicePollIfNeeded() {
    _invoicePollTimer?.cancel();

    if (_invoicePollAttempts >= _maxInvoicePolls) {
      _expectRecentPayment = false;
      return;
    }

    // Poll while any invoice is still generating, or — just after a booking —
    // for the whole window regardless, since the payment row may not be
    // written yet on the first fetch.
    final hasPending = _payments.any((p) => !p.hasInvoice);
    if (!hasPending && !_expectRecentPayment) return;

    _invoicePollTimer = Timer(_invoicePollInterval, () {
      if (!mounted) return;
      _load(page: _page, withLoader: false, isPoll: true);
    });
  }

  Future<void> _refresh() async {
    _invoicePollAttempts = 0;
    // Awaits the running fetch if one is already in flight (e.g. an invoice
    // poll) so the pull-to-refresh spinner tracks real work.
    await _load(page: _page, withLoader: false);
  }

  Future<void> _goToPage(int page) async {
    if (page < 1 || page > _totalPages || page == _page) return;
    _invoicePollAttempts = 0;
    // Let any in-flight fetch settle first, then load the requested page.
    await _activeLoad;
    if (!mounted || page == _page || _totalPages < page) return;
    await _load(page: page, withLoader: true);
  }

  Future<void> _downloadInvoice(PaymentRecord payment) async {
    if (_downloadingId.isNotEmpty || !payment.hasInvoice) return;

    setState(() => _downloadingId = payment.id);
    try {
      final result = await _service.fetchInvoiceDownloadLink(payment.id);
      if (!mounted) return;

      if (!result.success || result.data == null) {
        _snack(result.message);
        // The row said "ready" but the link 404'd — nudge the poll back on so
        // the status self-corrects instead of getting stuck.
        if (result.statusCode == 404) {
          _invoicePollAttempts = 0;
          _load(page: _page, withLoader: false, isPoll: true);
        }
        return;
      }

      final uri = Uri.tryParse(result.data!.url);
      var launched = false;
      if (uri != null) {
        try {
          launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          launched = false;
        }
      }
      if (!launched && mounted) {
        _snack('Couldn\'t open invoice ${result.data!.invoiceNumber}. '
            'Please try again.');
      }
    } finally {
      if (mounted) setState(() => _downloadingId = '');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isEmpty ? 'Something went wrong.' : message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: Text(
          'Payment History',
          style: AppType.body(size: 18, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      // Still a scroll view so pull-to-refresh stays available and the
      // RefreshIndicator has a scrollable child to attach to.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Text(
          'View your past payments and download invoices for your records.',
          style: AppType.body(size: 13).copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        if (_error.isNotEmpty) ...[
          _errorBanner(),
          const SizedBox(height: 14),
        ],
        if (_payments.isEmpty && _error.isEmpty)
          _emptyState()
        else
          ..._payments.map(_paymentCard),
        if (_totalPages > 1) ...[
          const SizedBox(height: 8),
          _pagination(),
        ],
      ],
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _errorBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: _errorBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _errorText, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error,
              style: AppType.body(size: 13, weight: FontWeight.w600)
                  .copyWith(color: _errorText),
            ),
          ),
          TextButton(
            onPressed: () => _load(page: _page, withLoader: true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'No payments yet',
            style: AppType.display(size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Your payment history will appear here after your first booking.',
            textAlign: TextAlign.center,
            style: AppType.body(size: 13)
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(PaymentRecord payment) {
    final downloading = _downloadingId == payment.id;
    // Only one invoice fetch runs at a time; disable every row's button
    // while any is in progress so a second tap can't silently no-op.
    final anyDownloading = _downloadingId.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.displayDescription,
                      style: AppType.body(size: 15, weight: FontWeight.w700)
                          .copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDate(payment.paidAt),
                      style: AppType.body(size: 12.5)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                payment.amountDisplay,
                style: AppType.display(size: 16, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metaChip(Icons.credit_card_outlined, payment.methodLabel),
              const SizedBox(width: 8),
              _invoiceChip(payment),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (!payment.hasInvoice || anyDownloading)
                  ? null
                  : () => _downloadInvoice(payment),
              icon: downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(
                downloading
                    ? 'Preparing…'
                    : payment.hasInvoice
                    ? 'Download invoice'
                    : 'Invoice generating…',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: payment.hasInvoice
                      ? AppColors.primary.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppType.body(size: 11.5, weight: FontWeight.w600)
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _invoiceChip(PaymentRecord payment) {
    final ready = payment.hasInvoice;
    final color = ready ? const Color(0xFF047857) : const Color(0xFFB45309);
    final bg = ready ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.verified_outlined : Icons.hourglass_bottom_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            ready ? payment.invoice!.invoiceNumber : 'Generating…',
            style: AppType.body(size: 11.5, weight: FontWeight.w700)
                .copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _pagination() {
    final busy = _activeLoad != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: (busy || _page <= 1) ? null : () => _goToPage(_page - 1),
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('Previous'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        Text(
          'Page $_page of $_totalPages',
          style: AppType.body(size: 12.5, weight: FontWeight.w600)
              .copyWith(color: AppColors.textSecondary),
        ),
        TextButton.icon(
          onPressed: (busy || _page >= _totalPages)
              ? null
              : () => _goToPage(_page + 1),
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('Next'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('dd MMM yyyy').format(date);
  }
}
