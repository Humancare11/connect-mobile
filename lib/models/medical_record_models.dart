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
    );
  }

  final String specialization;
  final String qualification;
  final String clinicName;
  final String clinicAddress;
  final String medicalRegistrationNumber;
  final String medicalCouncilName;
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
    this.medicines = const <PrescriptionMedicine>[],
    this.instructions = '',
    this.followUpDate = '',
    this.createdAt = '',
  });

  factory PrescriptionRecord.fromJson(Map<String, dynamic> json) {
    return PrescriptionRecord(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      diagnosis: (json['diagnosis'] ?? '').toString(),
      doctor: DoctorSummary.fromJson(json['doctorId']),
      appointment: AppointmentSummary.fromJson(json['appointmentId']),
      medicines: (json['medicines'] as List<dynamic>? ?? const [])
          .map(PrescriptionMedicine.fromJson)
          .toList(),
      instructions: (json['instructions'] ?? '').toString(),
      followUpDate: (json['followUpDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
    );
  }

  final String id;
  final String diagnosis;
  final DoctorSummary doctor;
  final AppointmentSummary appointment;
  final List<PrescriptionMedicine> medicines;
  final String instructions;
  final String followUpDate;
  final String createdAt;
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
}
