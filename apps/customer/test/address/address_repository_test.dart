import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';

Map<String, dynamic> _addrJson({bool serviceable = true, bool isDefault = false}) => {
  'id': 'a1', 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': serviceable,
  'zone': serviceable ? {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900} : null,
  if (!serviceable) 'message': "We don't serve this area yet",
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AddressRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    // Enforce exact body match — a subset-match adapter would silently pass
    // a create/update request that sends extra fields undetected.
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = AddressRepository(dio);
  });

  test('list 200 -> Ok(list)', () async {
    adapter.onGet('/me/addresses', (s) => s.reply(200, [_addrJson()]));
    final r = await repo.list();
    final v = (r as Ok<List<AddressDto>>).value;
    expect(v.single.label, 'Home');
    expect(v.single.zone!.visitFeePaise, 14900);
  });

  test('create POSTs the exact body and 201 -> Ok(dto)', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(201, _addrJson()),
        data: {'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001'});
    final r = await repo.create({'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001'});
    expect((r as Ok<AddressDto>).value.id, 'a1');
  });

  test('create out-of-area still 201 -> Ok(serviceable:false + message)', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(201, _addrJson(serviceable: false)),
        data: {'label': 'Home', 'line1': 'x', 'pincode': '999999'});
    final r = await repo.create({'label': 'Home', 'line1': 'x', 'pincode': '999999'});
    final dto = (r as Ok<AddressDto>).value;
    expect(dto.serviceable, false);
    expect(dto.message, isNotNull);
  });

  test('update PATCHes the body and 200 -> Ok', () async {
    adapter.onPatch('/me/addresses/a1', (s) => s.reply(200, _addrJson(isDefault: true)),
        data: {'isDefault': true});
    final r = await repo.update('a1', {'isDefault': true});
    expect((r as Ok<AddressDto>).value.isDefault, true);
  });

  test('delete 204 -> Ok(void)', () async {
    adapter.onDelete('/me/addresses/a1', (s) => s.reply(204, null));
    final r = await repo.delete('a1');
    expect(r, isA<Ok<void>>());
  });

  test('checkServiceability GET -> Ok(dto)', () async {
    adapter.onGet('/serviceability',
        (s) => s.reply(200, {'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900}}),
        queryParameters: {'pincode': '390001'});
    final r = await repo.checkServiceability('390001');
    expect((r as Ok<ServiceabilityDto>).value.zone!.name, 'Vadodara');
  });

  test('list 500 -> Failure(server) with {code,message} message', () async {
    adapter.onGet('/me/addresses', (s) => s.reply(500, {'code': 'INTERNAL_ERROR', 'message': 'boom'}));
    final r = await repo.list();
    final f = r as Failure;
    expect(f.kind, FailureKind.server);
    expect(f.message, 'boom');
  });

  test('create 400 -> Failure(validation) with server message', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(400, {'code': 'VALIDATION', 'message': 'pincode must be 6 digits'}),
        data: {'label': 'Home', 'line1': 'x', 'pincode': '123'});
    final r = await repo.create({'label': 'Home', 'line1': 'x', 'pincode': '123'});
    final f = r as Failure;
    expect(f.kind, FailureKind.validation);
    expect(f.message, 'pincode must be 6 digits');
  });

  test('update 401 -> Failure(unauthorized)', () async {
    adapter.onPatch('/me/addresses/a1', (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'nope'}),
        data: {'isDefault': true});
    final r = await repo.update('a1', {'isDefault': true});
    final f = r as Failure;
    expect(f.kind, FailureKind.unauthorized);
    expect(f.message, 'nope');
  });

  test('delete 404 -> Failure with server message', () async {
    adapter.onDelete('/me/addresses/a1', (s) => s.reply(404, {'code': 'NOT_FOUND', 'message': 'address not found'}));
    final r = await repo.delete('a1');
    final f = r as Failure;
    expect(f.message, 'address not found');
  });

  test('create with lat set but lng missing throws before any request is made', () async {
    await expectLater(
      () => repo.create({'label': 'Home', 'line1': 'x', 'pincode': '390001', 'lat': 22.3}),
      throwsArgumentError,
    );
  });

  test('create with lng set but lat missing throws before any request is made', () async {
    await expectLater(
      () => repo.create({'label': 'Home', 'line1': 'x', 'pincode': '390001', 'lng': 73.2}),
      throwsArgumentError,
    );
  });

  test('update with only lat set throws before any request is made', () async {
    await expectLater(
      () => repo.update('a1', {'lat': 22.3}),
      throwsArgumentError,
    );
  });

  test('create with both lat and lng set POSTs successfully', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(201, _addrJson()),
        data: {'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001', 'lat': 22.3, 'lng': 73.2});
    final r = await repo.create(
        {'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001', 'lat': 22.3, 'lng': 73.2});
    expect((r as Ok<AddressDto>).value.id, 'a1');
  });
}
