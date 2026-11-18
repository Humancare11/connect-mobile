import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/auth_response.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/auth_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _oid = '64b7f0c2a1d3e4f5a6b7c8d9';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = TokenStorageService();

  AuthService serviceReturning(Object body, {int status = 200}) => AuthService(
    apiClient: ApiClient(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
      tokenStorage: storage,
    ),
  );

  Map<String, dynamic> meBody() => {
    'user': {
      '_id': _oid,
      'patientId': 12345,
      'name': 'Asha',
      'email': 'asha@example.com',
      'role': 'user',
    },
  };

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'refresh_token': 'refresh',
      // What older builds stored: the patient number in place of the _id.
      'user_id': '12345',
      'user_name': 'Asha',
      'user_email': 'asha@example.com',
      'user_role': 'user',
    });
  });

  test('fetchCurrentProfile keeps _id as userId and patientId apart', () async {
    final result = await serviceReturning(meBody()).fetchCurrentProfile(silent: true);

    expect(result.success, isTrue);
    expect(result.data!['userId'], _oid);
    expect(result.data!['patientId'], '12345');
  });

  test('repairStoredUserId overwrites a stale userId with the server _id', () async {
    await serviceReturning(meBody()).repairStoredUserId();

    final profile = await storage.getUserProfile();
    expect(profile['userId'], _oid);
    expect(profile['patientId'], '12345');
    expect(profile['name'], 'Asha', reason: 'other fields are preserved');
  });

  test('repairStoredUserId leaves storage alone when /auth/me fails', () async {
    await serviceReturning({'msg': 'Server error.'}, status: 500).repairStoredUserId();

    expect((await storage.getUserProfile())['userId'], '12345');
  });

  test('UserModel keeps the _id as id and the patient number as patientId', () {
    final user = UserModel.fromMaps({
      'user': {'_id': _oid, 'patientId': 12345, 'name': 'Asha', 'role': 'user'},
    }, const {});

    expect(user.id, _oid);
    expect(user.patientId, '12345');
  });

  test('saving a profile without patientId keeps the stored one', () async {
    await storage.saveUserProfile(
      userId: _oid,
      name: 'Asha',
      email: 'asha@example.com',
      role: 'user',
      mobile: '',
      dob: '',
      gender: '',
      country: '',
      patientId: '12345',
    );
    await storage.saveUserProfile(
      userId: _oid,
      name: 'Asha B',
      email: 'asha@example.com',
      role: 'user',
      mobile: '',
      dob: '',
      gender: '',
      country: '',
    );

    final profile = await storage.getUserProfile();
    expect(profile['userId'], _oid);
    expect(profile['patientId'], '12345');
  });
}
