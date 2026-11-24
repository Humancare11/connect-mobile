class DoctorSummary {
  const DoctorSummary({this.id = '', this.name = '', this.email = ''});

  factory DoctorSummary.fromJson(dynamic value) {
    if (value is! Map) return const DoctorSummary();
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    return DoctorSummary(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
    );
  }

  final String id;
  final String name;
  final String email;
}

class AppointmentSummary {
  const AppointmentSummary({
    this.id = '',
    this.date = '',
    this.time = '',
    this.problem = '',
  });

  factory AppointmentSummary.fromJson(dynamic value) {
    if (value is! Map) return const AppointmentSummary();
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    return AppointmentSummary(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      problem: (json['problem'] ?? '').toString(),
    );
  }

  final String id;
  final String date;
  final String time;
  final String problem;
}

class DoctorEnrollment {
  const DoctorEnrollment({
    this.specialization = '',
    this.qualification = '',
    this.clinicName = '',
    this.clinicAddress = '',
    this.medicalRegistrationNumber = '',
    this.medicalCouncilName = '',
    this.country = '',
  });

  factory DoctorEnrollment.fromJson(dynamic value) {
    if (value is! Map) return const DoctorEnrollment();
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    return DoctorEnrollment(
      specialization: (json['specialization'] ?? '').toString(),
      qualification: (json['qualification'] ?? '').toString(),
      clinicName: (json['clinicName'] ?? '').toString(),
      clinicAddress: (json['clinicAddress'] ?? '').toString(),
      medicalRegistrationNumber: (json['medicalRegistrationNumber'] ?? '')
          .toString(),
      medicalCouncilName: (json['medicalCouncilName'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
    );
  }

  final String specialization;
  final String qualification;
  final String clinicName;
  final String clinicAddress;
  final String medicalRegistrationNumber;
  final String medicalCouncilName;

  /// ISO code (or name) of the doctor's country, as the web prescription shows.
  final String country;
}

class PrescriptionMedicine {
  const PrescriptionMedicine({
    this.name = '',
    this.dosage = '',
    this.frequency = '',
    this.duration = '',
    this.notes = '',
  });

  factory PrescriptionMedicine.fromJson(dynamic value) {
    if (value is! Map) return const PrescriptionMedicine();
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    return PrescriptionMedicine(
      name: (json['name'] ?? '').toString(),
      dosage: (json['dosage'] ?? '').toString(),
      frequency: (json['frequency'] ?? '').toString(),
      duration: (json['duration'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }

  final String name;
  final String dosage;
  final String frequency;
  final String duration;
  final String notes;
}

class PrescriptionRecord {
  const PrescriptionRecord({
    required this.id,
    required this.diagnosis,
    this.doctor = const DoctorSummary(),
    this.appointment = const AppointmentSummary(),
    this.enrollment = const DoctorEnrollment(),
    this.medicines = const <PrescriptionMedicine>[],
    this.instructions = '',
    this.followUpDate = '',
    this.createdAt = '',
    this.isSigned = false,
    this.signedAt = '',
  });

  factory PrescriptionRecord.fromJson(Map<String, dynamic> json) {
    return PrescriptionRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      diagnosis: (json['diagnosis'] ?? '').toString(),
      doctor: DoctorSummary.fromJson(json['doctorId']),
      appointment: AppointmentSummary.fromJson(json['appointmentId']),
      enrollment: DoctorEnrollment.fromJson(json['doctorEnrollment']),
      medicines: (json['medicines'] as List<dynamic>? ?? const [])
          .map(PrescriptionMedicine.fromJson)
          .toList(),
      instructions: (json['instructions'] ?? '').toString(),
      followUpDate: (json['followUpDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      isSigned: json['isSigned'] == true,
      signedAt: (json['signedAt'] ?? '').toString(),
    );
  }

  final String id;
  final String diagnosis;
  final DoctorSummary doctor;
  final AppointmentSummary appointment;
  final DoctorEnrollment enrollment;
  final List<PrescriptionMedicine> medicines;
  final String instructions;
  final String followUpDate;
  final String createdAt;

  /// True when the doctor signed this prescription. Older prescriptions (and
  /// ones issued unsigned) have no such flag and read as unsigned.
  final bool isSigned;
  final String signedAt;
}

class MedicalCertificateRecord {
  const MedicalCertificateRecord({
    required this.id,
    required this.diagnosis,
    this.doctor = const DoctorSummary(),
    this.appointment = const AppointmentSummary(),
    this.enrollment = const DoctorEnrollment(),
    this.recommendation = '',
    this.restFromDate = '',
    this.restToDate = '',
    this.notes = '',
    this.issuedDate = '',
    this.createdAt = '',
    this.isSigned = false,
    this.signedAt = '',
  });

  factory MedicalCertificateRecord.fromJson(Map<String, dynamic> json) {
    return MedicalCertificateRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      diagnosis: (json['diagnosis'] ?? '').toString(),
      doctor: DoctorSummary.fromJson(json['doctorId']),
      appointment: AppointmentSummary.fromJson(json['appointmentId']),
      enrollment: DoctorEnrollment.fromJson(json['doctorEnrollment']),
      recommendation: (json['recommendation'] ?? '').toString(),
      restFromDate: (json['restFromDate'] ?? '').toString(),
      restToDate: (json['restToDate'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      issuedDate: (json['issuedDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      isSigned: json['isSigned'] == true,
      signedAt: (json['signedAt'] ?? '').toString(),
    );
  }

  final String id;
  final String diagnosis;
  final DoctorSummary doctor;
  final AppointmentSummary appointment;
  final DoctorEnrollment enrollment;
  final String recommendation;
  final String restFromDate;
  final String restToDate;
  final String notes;
  final String issuedDate;
  final String createdAt;

  /// See [PrescriptionRecord.isSigned].
  final bool isSigned;
  final String signedAt;
}

/// An admin-issued medical report (`GET /medical/my-reports`). Metadata only —
/// the report itself is a PDF held in private storage, opened through
/// [MedicalReportDownloadLink].
class MedicalReportRecord {
  const MedicalReportRecord({
    required this.id,
    this.reportNumber = '',
    this.title = '',
    this.reportDate = '',
    this.doctorName = '',
    this.status = '',
    this.createdAt = '',
  });

  factory MedicalReportRecord.fromJson(Map<String, dynamic> json) {
    return MedicalReportRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      reportNumber: (json['reportNumber'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      reportDate: (json['reportDate'] ?? '').toString(),
      doctorName: (json['doctorName'] ?? '').toString(),
      status: (json['status'] ?? '').toString().trim().toLowerCase(),
      createdAt: (json['createdAt'] ?? '').toString(),
    );
  }

  final String id;
  final String reportNumber;
  final String title;
  final String reportDate;
  final String doctorName;
  final String status;
  final String createdAt;

  /// A voided report stays in the list (flagged) but can no longer be opened.
  bool get isVoided => status == 'voided';
}

/// `GET /medical/my-reports/:id/download` — a short-lived (5 min) presigned
/// link to the report PDF.
class MedicalReportDownloadLink {
  const MedicalReportDownloadLink({required this.url, this.reportNumber = ''});

  factory MedicalReportDownloadLink.fromJson(Map<String, dynamic> json) {
    return MedicalReportDownloadLink(
      url: (json['url'] ?? '').toString(),
      reportNumber: (json['reportNumber'] ?? '').toString(),
    );
  }

  final String url;
  final String reportNumber;
}
