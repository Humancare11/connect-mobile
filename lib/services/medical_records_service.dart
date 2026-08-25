import '../models/api_result.dart';
import '../models/medical_record_models.dart';
import 'api_client.dart';

class MedicalRecordsSnapshot {
  const MedicalRecordsSnapshot({
    required this.prescriptions,
    required this.certificates,
    this.error = '',
  });

  final List<PrescriptionRecord> prescriptions;
  final List<MedicalCertificateRecord> certificates;
  final String error;
}

class MedicalRecordsService {
  MedicalRecordsService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<MedicalRecordsSnapshot> fetchMyRecords({bool silent = false}) async {
    final results = await Future.wait<ApiResult<Map<String, dynamic>>>([
      _apiClient.get('/medical/my-prescriptions', null, silent),
      _apiClient.get('/medical/my-certificates', null, silent),
    ]);

    final prescriptionResult = results[0];
    final certificateResult = results[1];

    final prescriptions = prescriptionResult.success
        ? _prescriptionsFromResult(prescriptionResult)
        : const <PrescriptionRecord>[];
    final certificates = certificateResult.success
        ? _certificatesFromResult(certificateResult)
        : const <MedicalCertificateRecord>[];

    // Previously only prescriptionResult's failure was ever surfaced — if
    // certificates failed to load (401, 500, timeout) while prescriptions
    // succeeded, `certificates` silently became `[]` with no error at all,
    // and the UI showed "No certificates yet" as if that were confirmed
    // fact rather than an unreported fetch failure.
    final failures = [
      if (!prescriptionResult.success) prescriptionResult,
      if (!certificateResult.success) certificateResult,
    ];

    var error = '';
    if (failures.isNotEmpty) {
      final anySessionExpired = failures.any((r) => r.statusCode == 401);
      if (anySessionExpired) {
        error = 'Session expired. Please log in again.';
      } else if (!prescriptionResult.success && !certificateResult.success) {
        error = 'Could not load your prescriptions or certificates. '
            '${prescriptionResult.message}';
      } else if (!prescriptionResult.success) {
        error = 'Could not load prescriptions. ${prescriptionResult.message}';
      } else {
        error = 'Could not load certificates. ${certificateResult.message}';
      }
    }

    return MedicalRecordsSnapshot(
      prescriptions: prescriptions,
      certificates: certificates,
      error: error,
    );
  }

  List<PrescriptionRecord> _prescriptionsFromResult(
    ApiResult<Map<String, dynamic>> result,
  ) {
    return _extractList(result.data ?? result.raw)
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(PrescriptionRecord.fromJson)
        .toList();
  }

  List<MedicalCertificateRecord> _certificatesFromResult(
    ApiResult<Map<String, dynamic>> result,
  ) {
    return _extractList(result.data ?? result.raw)
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(MedicalCertificateRecord.fromJson)
        .toList();
  }

  List<dynamic> _extractList(Map<String, dynamic>? response) {
    if (response == null) return const [];
    for (final candidate in [
      response['data'],
      response['prescriptions'],
      response['certificates'],
      response['items'],
    ]) {
      if (candidate is List) return candidate;
      if (candidate is Map) {
        for (final value in candidate.values) {
          if (value is List) return value;
        }
      }
    }
    return const [];
  }
}
