import '../utils/json_helpers.dart';

/// State of the signed-in patient's account-deletion request, as reported by
/// the backend (`deletionRequestStatus` / `deletionRequestedAt` on the user
/// returned by `GET /auth/me`).
///
///  - `none` / `approved` → nothing pending; the request form is shown
///  - `pending`           → a request is waiting for an admin; it can be cancelled
///  - `rejected`          → the last request was declined; a new one can be made
class DeletionRequestStatus {
  const DeletionRequestStatus({this.status = 'none', this.requestedAt});

  static const DeletionRequestStatus none = DeletionRequestStatus();

  final String status;
  final DateTime? requestedAt;

  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  /// Reads the status from a response that carries the user either at
  /// `user` (`/auth/me`, cancel, request) or at the top level.
  factory DeletionRequestStatus.fromResponse(Map<String, dynamic> data) {
    final user = asMap(data['user']);
    final source = user.isNotEmpty ? user : data;

    final status = (source['deletionRequestStatus']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final requested = source['deletionRequestedAt']?.toString() ?? '';

    return DeletionRequestStatus(
      status: status.isEmpty ? 'none' : status,
      requestedAt: requested.isEmpty
          ? null
          : DateTime.tryParse(requested)?.toLocal(),
    );
  }
}
