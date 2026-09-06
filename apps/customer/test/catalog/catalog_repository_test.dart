import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/catalog/data/catalog_repository.dart';

Map<String, dynamic> _cat(String id, String name) => {'id': id, 'name': name, 'status': 'ACTIVE'};
Map<String, dynamic> _svc({int? labor = 45000}) =>
    {'id': 's1', 'name': 'Fridge not cooling', 'tier': 'T2', 'categoryId': 'c1', 'laborPaise': labor, 'visitFeePaise': 14900};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late CatalogRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = CatalogRepository(dio);
  });

  test('categories 200 -> Ok(list)', () async {
    adapter.onGet('/catalog/categories', (s) => s.reply(200, [_cat('c1', 'Refrigerator')]));
    final r = await repo.categories();
    expect((r as Ok<List<CategoryDto>>).value.single.name, 'Refrigerator');
  });

  test('services sends zoneId + categoryId query and parses', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(200, [_svc()]),
        queryParameters: {'zoneId': 'z1', 'categoryId': 'c1'});
    final r = await repo.services(zoneId: 'z1', categoryId: 'c1');
    final svc = (r as Ok<List<ServiceDto>>).value.single;
    expect(svc.tier, 'T2');
    expect(svc.laborPaise, 45000);
    expect(svc.visitFeePaise, 14900);
  });

  test('services with null laborPaise parses (unpriced in zone)', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(200, [_svc(labor: null)]),
        queryParameters: {'zoneId': 'z1'});
    final r = await repo.services(zoneId: 'z1');
    expect((r as Ok<List<ServiceDto>>).value.single.laborPaise, isNull);
  });

  test('services 400 -> Failure(validation) with backend message', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(400, {'code': 'VALIDATION', 'message': 'zoneId is required'}),
        queryParameters: {'zoneId': 'z1'});
    final r = await repo.services(zoneId: 'z1');
    final f = r as Failure;
    expect(f.kind, FailureKind.validation);
    expect(f.message, 'zoneId is required');
  });
}
