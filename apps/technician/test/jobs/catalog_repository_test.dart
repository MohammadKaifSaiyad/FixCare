import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';

void main() {
  late Dio dio; late DioAdapter adapter; late CatalogRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = CatalogRepository(dio);
  });

  test('issues(categoryId) GETs the filtered list', () async {
    adapter.onGet('/catalog/issues', (s) => s.reply(200, [
      {'id': 'i1', 'name': 'Fan capacitor failure', 'categoryId': 'c1', 'status': 'ACTIVE'},
    ]), queryParameters: {'categoryId': 'c1'});
    final v = (await repo.issues(categoryId: 'c1') as Ok<List<DiagnosedIssueDto>>).value;
    expect(v.single.name, 'Fan capacitor failure');
  });

  test('parts(categoryId) GETs the list incl. a generic null-category part', () async {
    adapter.onGet('/catalog/parts', (s) => s.reply(200, [
      {'id': 'p1', 'sku': 'FAN-CAP', 'name': 'Fan capacitor 2.5 MFD', 'categoryId': 'c1', 'ceilingPricePaise': 12000, 'status': 'ACTIVE'},
      {'id': 'p2', 'sku': 'GEN', 'name': 'Generic', 'categoryId': null, 'ceilingPricePaise': 5000, 'status': 'ACTIVE'},
    ]), queryParameters: {'categoryId': 'c1'});
    final v = (await repo.parts(categoryId: 'c1') as Ok<List<PartCatalogDto>>).value;
    expect(v, hasLength(2));
    expect(v[1].categoryId, isNull);
  });

  test('issues 500 -> Failure(server)', () async {
    adapter.onGet('/catalog/issues', (s) => s.reply(500, {'code': 'X', 'message': 'boom'}));
    expect((await repo.issues() as Failure).kind, FailureKind.server);
  });

  test('a Failure carries the envelope code alongside the message', () async {
    adapter.onGet('/catalog/parts', (s) => s.reply(403, {'code': 'FORBIDDEN', 'message': 'Verified technician required'}));
    final f = await repo.parts() as Failure;
    expect(f.message, 'Verified technician required');
    expect(f.code, 'FORBIDDEN');
  });
}
