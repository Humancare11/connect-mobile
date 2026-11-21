/// Models for the patient "My Visit Notes" screens.
///
/// Shapes mirror the web app's `GET /api/consultation-reports/mine`,
/// `GET /api/consultation-reports/mine/:id` responses (see
/// `connect/backend/controllers/consultationReportController.js` and
/// `utils/consultationReportService.js` `serializeReport`) — the same
/// contract the React `MyVisitNotes` / `VisitNotePreview` pages consume.
library;

import 'package:intl/intl.dart';

String _text(Object? value) => (value ?? '').toString();

Map<String, dynamic> _map(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

/// "dd MMM yyyy" (web `fmtDate`, en-IN). An empty value is empty; text that is
/// not a date is returned as it came.
String formatVisitNoteDate(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat('dd MMM yyyy').format(date.toLocal());
}

/// "dd MMM yyyy hh:mm a" (web `fmtDateTime`).
String formatVisitNoteDateTime(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat('dd MMM yyyy hh:mm a').format(date.toLocal());
}

class VisitNoteAmendment {
  const VisitNoteAmendment({
    this.id = '',
    this.authorName = '',
    this.reason = '',
    this.text = '',
    this.createdAt = '',
  });

  factory VisitNoteAmendment.fromJson(dynamic value) {
    final json = _map(value);
    return VisitNoteAmendment(
      id: _text(json['_id'] ?? json['id']),
      authorName: _text(json['authorName']),
      reason: _text(json['reason']),
      text: _text(json['text']),
      createdAt: _text(json['createdAt']),
    );
  }

  final String id;
  final String authorName;
  final String reason;
  final String text;
  final String createdAt;
}

class VisitNoteReport {
  const VisitNoteReport({
    required this.id,
    this.reportNumber = '',
    this.patientName = '',
    this.patientGender = '',
    this.patientDob = '',
    this.patientAge = '',
    this.consultationDate = '',
    this.consultationTime = '',
    this.consultationMode = '',
    this.physicianName = '',
    this.physicianRegistrationNumber = '',
    this.physicianSpeciality = '',
    this.physicianCountry = '',
    this.symptoms = '',
    this.clinicalFindings = '',
    this.plan = '',
    this.note = '',
    this.signedAt = '',
    this.amendments = const [],
  });

  factory VisitNoteReport.fromJson(dynamic value) {
    final json = _map(value);
    final patient = _map(json['patient']);
    final consultation = _map(json['consultation']);
    final physician = _map(json['physician']);
    final amendments = json['amendments'];
    return VisitNoteReport(
      id: _text(json['_id'] ?? json['id']),
      reportNumber: _text(json['reportNumber']),
      patientName: _text(patient['name']),
      patientGender: _text(patient['gender']),
      patientDob: _text(patient['dob']),
      patientAge: _text(patient['age']),
      consultationDate: _text(consultation['date']),
      consultationTime: _text(consultation['time']),
      consultationMode: _text(consultation['mode']),
      physicianName: _text(physician['name']),
      physicianRegistrationNumber: _text(physician['registrationNumber']),
      physicianSpeciality: _text(physician['speciality']),
      physicianCountry: _text(physician['country']),
      symptoms: _text(json['symptoms']),
      clinicalFindings: _text(json['clinicalFindings']),
      plan: _text(json['plan']),
      note: _text(json['note']),
      signedAt: _text(json['signedAt']),
      amendments: amendments is List
          ? amendments.map(VisitNoteAmendment.fromJson).toList()
          : const [],
    );
  }

  final String id;
  final String reportNumber;
  final String patientName;
  final String patientGender;
  final String patientDob;
  final String patientAge;
  final String consultationDate;
  final String consultationTime;
  final String consultationMode;
  final String physicianName;
  final String physicianRegistrationNumber;
  final String physicianSpeciality;
  final String physicianCountry;
  final String symptoms;
  final String clinicalFindings;
  final String plan;
  final String note;
  final String signedAt;
  final List<VisitNoteAmendment> amendments;

  bool get isAmended => amendments.isNotEmpty;

  /// The date shown on a list card: the consultation date, else the signing
  /// time (web: `r.consultation?.date || r.signedAt`).
  String get displayDate =>
      consultationDate.trim().isNotEmpty ? consultationDate : signedAt;

  /// "date · time" shown in the slip's Consultation field.
  String get consultationWhen {
    final parts = [
      if (consultationDate.trim().isNotEmpty)
        formatVisitNoteDate(consultationDate),
      if (consultationTime.trim().isNotEmpty) consultationTime,
    ];
    return parts.join(' · ');
  }

  String get modeLabel =>
      consultationMode.trim().isEmpty ? 'Video Consultation' : consultationMode;
}

/// A completed consultation whose doctor has not signed a Visit Note yet
/// (web: "Report pending").
class VisitNotePending {
  const VisitNotePending({
    required this.appointmentId,
    this.date = '',
    this.time = '',
    this.doctorName = '',
  });

  factory VisitNotePending.fromJson(dynamic value) {
    final json = _map(value);
    return VisitNotePending(
      appointmentId: _text(json['appointmentId']),
      date: _text(json['date']),
      time: _text(json['time']),
      doctorName: _text(json['doctorName']),
    );
  }

  final String appointmentId;
  final String date;
  final String time;
  final String doctorName;
}

class VisitNotesSnapshot {
  const VisitNotesSnapshot({
    this.reports = const [],
    this.pending = const [],
  });

  factory VisitNotesSnapshot.fromJson(Map<String, dynamic> json) {
    final reports = json['reports'];
    final pending = json['pending'];
    return VisitNotesSnapshot(
      reports: reports is List
          ? reports.map(VisitNoteReport.fromJson).toList()
          : const [],
      pending: pending is List
          ? pending.map(VisitNotePending.fromJson).toList()
          : const [],
    );
  }

  final List<VisitNoteReport> reports;
  final List<VisitNotePending> pending;

  List<VisitNoteListItem> get items =>
      mergeVisitNoteItems(reports: reports, pending: pending);
}

/// One row of the list: either a signed report or a "Report pending" entry.
class VisitNoteListItem {
  const VisitNoteListItem._({
    required this.dateKey,
    this.report,
    this.pending,
  });

  factory VisitNoteListItem.report(VisitNoteReport report) =>
      VisitNoteListItem._(
        dateKey: _dateKey(report.displayDate),
        report: report,
      );

  factory VisitNoteListItem.pending(VisitNotePending pending) =>
      VisitNoteListItem._(dateKey: _dateKey(pending.date), pending: pending);

  /// First 10 characters of the date (YYYY-MM-DD), as the web sorts on.
  final String dateKey;
  final VisitNoteReport? report;
  final VisitNotePending? pending;

  bool get isReport => report != null;

  static String _dateKey(String value) {
    final text = value.trim();
    return text.length > 10 ? text.substring(0, 10) : text;
  }
}

/// Signed reports and pending entries in one list, newest first — the same
/// merge and ordering as the web `MyVisitNotes` page. Entries with the same
/// date keep their original order (reports before pending ones).
List<VisitNoteListItem> mergeVisitNoteItems({
  required List<VisitNoteReport> reports,
  required List<VisitNotePending> pending,
}) {
  final items = <VisitNoteListItem>[
    ...reports.map(VisitNoteListItem.report),
    ...pending.map(VisitNoteListItem.pending),
  ];
  final order = <VisitNoteListItem, int>{
    for (var i = 0; i < items.length; i++) items[i]: i,
  };
  items.sort((a, b) {
    final byDate = b.dateKey.compareTo(a.dateKey);
    return byDate != 0 ? byDate : order[a]!.compareTo(order[b]!);
  });
  return items;
}
