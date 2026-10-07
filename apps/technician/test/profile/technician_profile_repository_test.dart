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
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
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
    final f = await repo.getProfile() as Failure;
    expect(f.kind, FailureKind.unauthorized);
    expect(f.code, 'UNAUTHORIZED');
  });

  Map<String, dynamic> profile(String status) => {
        'id': 't1', 'role': 'TECHNICIAN', 'name': 'Ramesh', 'skills': ['AC'], 'status': status,
        'zones': [{'id': 'z1', 'name': 'Padra'}], 'reviewNote': null, 'submittedAt': null,
      };

  test('getProfile parses zones, reviewNote and submittedAt', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {...profile('PENDING'), 'reviewNote': 'Add your full name', 'submittedAt': '2026-10-01T10:00:00.000Z'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.zones, [const ZoneRefDto(id: 'z1', name: 'Padra')]);
    expect(v.reviewNote, 'Add your full name');
    expect(v.submittedAt, '2026-10-01T10:00:00.000Z');
  });

  test('a profile without zones/reviewNote (older backend) still parses', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': '', 'skills': <String>[], 'status': 'PENDING'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.zones, isEmpty);
    expect(v.reviewNote, isNull);
  });

  test('updateProfile PATCHes exactly {name, skills, zoneIds}', () async {
    adapter.onPatch('/me/profile', (s) => s.reply(200, profile('PENDING')),
        data: {'name': 'Ramesh', 'skills': ['AC'], 'zoneIds': ['z1']});
    final v = (await repo.updateProfile(name: 'Ramesh', skills: ['AC'], zoneIds: ['z1']) as Ok<TechnicianProfileDto>).value;
    expect(v.zones.single.name, 'Padra');
  });

  test('updateProfile 409 PROFILE_LOCKED -> Failure with the code and message', () async {
    adapter.onPatch('/me/profile', (s) => s.reply(409, {'code': 'PROFILE_LOCKED', 'message': 'Your profile is locked while under review'}),
        data: {'name': 'R', 'skills': ['AC'], 'zoneIds': ['z1']});
    final f = await repo.updateProfile(name: 'R', skills: ['AC'], zoneIds: ['z1']) as Failure;
    expect(f.code, 'PROFILE_LOCKED');
    expect(f.message, 'Your profile is locked while under review');
  });

  test('submit is a bodyless POST and parses the submitted profile', () async {
    adapter.onPost('/technician/me/submit', (s) => s.reply(200, profile('KYC_SUBMITTED')));
    final v = (await repo.submit() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'KYC_SUBMITTED');
  });

  test('submit network error -> Failure(network)', () async {
    adapter.onPost('/technician/me/submit', (s) => s.throws(0, DioException.connectionError(requestOptions: RequestOptions(path: '/technician/me/submit'), reason: 'down')));
    expect((await repo.submit() as Failure).kind, FailureKind.network);
  });
}
