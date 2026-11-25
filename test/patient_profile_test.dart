import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/services/auth_validators.dart';
import 'package:humancare_connect/utils/patient_profile.dart';

void main() {
  final now = DateTime.utc(2026, 5, 10, 12);
  String error(String dob) => AuthValidators.dobError(dob, now: now);

  group('date of birth', () {
    test('today and 1900-01-01 are accepted', () {
      expect(error('2026-05-10'), '');
      expect(error('1900-01-01'), '');
      expect(error('2024-02-29'), '');
    });

    test('a future date and a year before 1900 are refused', () {
      expect(error('2026-05-11'), 'Date of Birth cannot be in the future');
      expect(error('1899-12-31'), 'Date of Birth must be in or after 1900');
    });

    test('empty, badly written and impossible dates are refused', () {
      expect(error(''), 'Select Date of Birth');
      expect(error('10-05-1990'), 'Enter a valid Date of Birth');
      expect(error('1990-02-31'), 'Enter a valid Date of Birth');
      expect(error('2023-02-29'), 'Enter a valid Date of Birth');
      expect(error('1990-13-01'), 'Enter a valid Date of Birth');
    });

    test('"today" is the date in India, not on the phone or in UTC', () {
      // 18:29 UTC is 23:59 in India; one minute later it is the next day.
      final before = DateTime.utc(2026, 5, 10, 18, 29);
      final after = DateTime.utc(2026, 5, 10, 18, 30);
      expect(AuthValidators.todayInIndia(before), '2026-05-10');
      expect(AuthValidators.todayInIndia(after), '2026-05-11');
      expect(AuthValidators.dobError('2026-05-11', now: before), isNotEmpty);
      expect(AuthValidators.dobError('2026-05-11', now: after), '');
    });
  });

  test('a profile is complete only with a usable date and a known gender', () {
    bool complete(String dob, String gender) =>
        isPatientProfileComplete(dob: dob, gender: gender, now: now);

    expect(complete('1990-05-01', 'Male'), isTrue);
    expect(complete('1990-05-01', 'Female'), isTrue);
    expect(complete('1990-05-01', 'Other'), isTrue);
    expect(complete('', 'Male'), isFalse);
    expect(complete('1990-05-01', ''), isFalse);
    expect(complete('1990-05-01', 'male'), isFalse);
    expect(complete('1990-02-31', 'Male'), isFalse);
    expect(complete('1990-05-01T00:00:00.000Z', 'Male'), isFalse);
  });

  test('only a 422 PROFILE_INCOMPLETE answer counts', () {
    const body = {'code': 'PROFILE_INCOMPLETE'};
    expect(isProfileIncompleteResponse(422, body), isTrue);
    expect(isProfileIncompleteResponse(400, body), isFalse);
    expect(isProfileIncompleteResponse(422, const {'code': 'OTHER'}), isFalse);
    expect(isProfileIncompleteResponse(422, const {}), isFalse);
  });

  test('the app never sends the website header "X-Client"', () {
    final header = RegExp('[\'"]x-client[\'"]', caseSensitive: false);
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            header.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
