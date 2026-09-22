import '../models/api_result.dart';
import '../models/payment_model.dart';
import 'api_client.dart';

/// Reads the patient's billing data from the existing backend payment APIs.
///
/// Nothing here creates or mutates server state — the invoice itself is
/// generated and emailed by the backend automatically right after a paid
/// booking (`recordPaymentAndInvoice` in `connect/backend/utils/billing.js`).
/// This service only surfaces the result in the app dashboard, exactly like
/// the web `PaymentHistory` page.
class PaymentHistoryService {
  PaymentHistoryService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// `GET /api/payments/mine` — the logged-in patient's own payments, most
  /// recent first, paginated. [limit] is capped at 50 server-side.
  Future<ApiResult<PaymentHistoryResult>> fetchMyPayments({
    int page = 1,
    int limit = 20,
    bool silent = false,
  }) async {
    final result = await _apiClient.get(
      '/payments/mine',
      {'page': '${page < 1 ? 1 : page}', 'limit': '$limit'},
      silent,
    );

    if (!result.success) {
      return ApiResult<PaymentHistoryResult>(
        success: false,
        message: result.message.isNotEmpty
            ? result.message
            : 'We couldn\'t load your payment history. Please try again.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<PaymentHistoryResult>(
      success: true,
      message: result.message,
      data: PaymentHistoryResult.fromJson(result.data ?? const {}),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  /// `GET /api/payments/:paymentId/invoice-url` — a short-lived (5 min)
  /// presigned S3 URL for the invoice PDF. Returns a `404` while the invoice
  /// is still being generated; callers should surface [ApiResult.message] and
  /// let the user retry.
  Future<ApiResult<InvoiceDownloadLink>> fetchInvoiceDownloadLink(
    String paymentId, {
    bool silent = false,
  }) async {
    final id = paymentId.trim();
    if (id.isEmpty) {
      return const ApiResult<InvoiceDownloadLink>(
        success: false,
        message: 'This payment has no invoice reference.',
      );
    }

    final result = await _apiClient.get(
      '/payments/$id/invoice-url',
      null,
      silent,
    );

    if (!result.success) {
      return ApiResult<InvoiceDownloadLink>(
        success: false,
        message: result.message.isNotEmpty
            ? result.message
            : 'Invoice isn\'t ready yet. Please try again in a moment.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    final link = InvoiceDownloadLink.fromJson(result.data ?? const {});
    if (link.url.isEmpty) {
      return ApiResult<InvoiceDownloadLink>(
        success: false,
        message: 'Invoice isn\'t ready yet. Please try again in a moment.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<InvoiceDownloadLink>(
      success: true,
      message: result.message,
      data: link,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }
}
