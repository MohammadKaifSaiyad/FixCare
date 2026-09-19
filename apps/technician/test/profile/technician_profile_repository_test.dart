import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TechnicianProfileRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = TechnicianProfileRepository(dio);
  });

  test('getProfile parses a VERIFIED technician with skills', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': 'Ramesh', 'skills': ['FAN', 'AC'], 'status': 'VERIFIED'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'VERIFIED');
    expect(v.skills, ['FAN', 'AC']);
  });

  test('getProfile parses a fresh PENDING technician (empty name/skills)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': '', 'skills': <String>[], 'status': 'PENDING'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'PENDING');
    expect(v.name, '');
    expect(v.skills, isEmpty);
  });

  test('getProfile 401 -> Failure(unauthorized)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'nope'}));
    expect((await repo.getProfile() as Failure).kind, FailureKind.unauthorized);
  });
}
