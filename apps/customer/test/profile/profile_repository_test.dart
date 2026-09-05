import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ProfileRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    // Enforce exact body match to prevent sending extra fields in PATCH
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = ProfileRepository(dio);
  });

  test('getProfile 200 -> Ok(dto)', () async {
    adapter.onGet('/me/profile',
        (s) => s.reply(200, {'id': 'u1', 'role': 'CUSTOMER', 'name': 'Ravi', 'status': 'ACTIVE'}));
    final r = await repo.getProfile();
    expect((r as Ok<CustomerProfileDto>).value.name, 'Ravi');
  });

  test('getProfile 401 -> Failure(unauthorized)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'nope'}));
    final r = await repo.getProfile();
    final f = r as Failure;
    expect(f.kind, FailureKind.unauthorized);
    expect(f.message, 'nope'); // reads {message}, not {error}
  });

  test('updateName PATCHes exactly {name} and 200 -> Ok(dto)', () async {
    adapter.onPatch('/me/profile',
        (s) => s.reply(200, {'id': 'u1', 'role': 'CUSTOMER', 'name': 'Sita', 'status': 'ACTIVE'}),
        data: {'name': 'Sita'});
    final r = await repo.updateName('Sita');
    expect((r as Ok<CustomerProfileDto>).value.name, 'Sita');
  });

  test('updateName 400 -> Failure(validation) with server message', () async {
    adapter.onPatch('/me/profile',
        (s) => s.reply(400, {'code': 'VALIDATION', 'message': 'name must not be empty'}),
        data: {'name': ''});
    final r = await repo.updateName('');
    final f = r as Failure;
    expect(f.kind, FailureKind.validation);
    expect(f.message, 'name must not be empty');
  });
}
