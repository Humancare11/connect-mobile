/// Models for the patient billing / payment-history dashboard.
///
/// Shapes mirror the web app's `GET /api/payments/mine` and
/// `GET /api/payments/:paymentId/invoice-url` responses (see
/// `connect/backend/routes/payments.js`) — the same contract the React
/// `PaymentHistory` page consumes.
library;

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

DateTime? _asDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}

/// The invoice attached to a payment once the backend has finished generating
/// it. `null` on a [PaymentRecord] means "still generating" — the backend
/// creates the PDF fire-and-forget just after the booking response.
class PaymentInvoiceInfo {
  const PaymentInvoiceInfo({
    required this.invoiceNumber,
    this.issuedAt,
    this.emailed = false,
  });

  factory PaymentInvoiceInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInvoiceInfo(
      invoiceNumber: (json['invoiceNumber'] ?? '').toString().trim(),
      issuedAt: _asDate(json['issuedAt']),
      emailed: json['emailed'] == true,
    );
  }

  final String invoiceNumber;
  final DateTime? issuedAt;

  /// Whether the backend has already emailed this invoice to the patient.
  final bool emailed;
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.gateway,
    required this.status,
    this.paidAt,
    this.appointmentId,
    this.categoryConsultationId,
    this.invoice,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    final invoiceRaw = json['invoice'];
    return PaymentRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      description: (json['description'] ?? '').toString().trim(),
      amountCents: _asInt(json['amountCents'] ?? json['amount']),
      currency: (json['currency'] ?? 'usd').toString().trim().toLowerCase(),
      gateway: (json['gateway'] ?? '').toString().trim().toLowerCase(),
      status: (json['status'] ?? '').toString().trim().toLowerCase(),
      paidAt: _asDate(json['paidAt'] ?? json['createdAt']),
      appointmentId: (json['appointmentId'] ?? '').toString().trim().isEmpty
          ? null
          : json['appointmentId'].toString(),
      categoryConsultationId:
          (json['categoryConsultationId'] ?? '').toString().trim().isEmpty
          ? null
          : json['categoryConsultationId'].toString(),
      invoice: invoiceRaw is Map
          ? PaymentInvoiceInfo.fromJson(
              invoiceRaw.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
    );
  }

  final String id;
  final String description;
  final int amountCents;
  final String currency;
  final String gateway;
  final String status;
  final DateTime? paidAt;
  final String? appointmentId;
  final String? categoryConsultationId;
  final PaymentInvoiceInfo? invoice;

  bool get hasInvoice =>
      invoice != null && invoice!.invoiceNumber.isNotEmpty;

  /// The web app labels the "Method" column purely from `gateway`.
  String get methodLabel => gateway == 'paypal' ? 'PayPal' : 'Card';

  /// The web app renders a fixed "Tele Consultation" description in its
  /// history table rather than the raw stored `description`.
  String get displayDescription =>
      description.isNotEmpty ? description : 'Tele Consultation';

  /// `$50.00` for USD; `EUR 50.00` style fallback for anything else — matches
  /// the web `formatAmount()` helper (Intl currency with a manual fallback).
  String get amountDisplay {
    final amount = amountCents / 100;
    final code = currency.toUpperCase();
    if (currency == 'usd') return '\$${amount.toStringAsFixed(2)}';
    return '$code ${amount.toStringAsFixed(2)}';
  }
}

class PaymentHistoryResult {
  const PaymentHistoryResult({
    required this.payments,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaymentHistoryResult.fromJson(Map<String, dynamic> json) {
    final rawList = json['payments'];
    final payments = rawList is List
        ? rawList
              .whereType<Map>()
              .map(
                (item) => PaymentRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .toList()
        : <PaymentRecord>[];

    final page = _asInt(json['page']) <= 0 ? 1 : _asInt(json['page']);
    final totalPages =
        _asInt(json['totalPages']) <= 0 ? 1 : _asInt(json['totalPages']);

    return PaymentHistoryResult(
      payments: payments,
      page: page,
      limit: _asInt(json['limit']) <= 0 ? 20 : _asInt(json['limit']),
      total: _asInt(json['total']),
      totalPages: totalPages,
    );
  }

  final List<PaymentRecord> payments;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Result of `GET /api/payments/:paymentId/invoice-url` — a short-lived
/// presigned S3 link to the invoice PDF.
class InvoiceDownloadLink {
  const InvoiceDownloadLink({
    required this.url,
    required this.invoiceNumber,
    this.expiresAt,
  });

  factory InvoiceDownloadLink.fromJson(Map<String, dynamic> json) {
    return InvoiceDownloadLink(
      url: (json['url'] ?? '').toString().trim(),
      invoiceNumber: (json['invoiceNumber'] ?? '').toString().trim(),
      expiresAt: _asDate(json['expiresAt']),
    );
  }

  final String url;
  final String invoiceNumber;
  final DateTime? expiresAt;
}
