import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/address/presentation/address_list_screen.dart';

Map<String, dynamic> _addrJson({String id = 'a1', bool isDefault = false}) => {
  'id': id, 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': true,
  'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
};

class _FakeAddressRepository extends AddressRepository {
  _FakeAddressRepository() : super(Dio());

  Result<List<AddressDto>> listResult = Ok([AddressDto.fromJson(_addrJson())]);
  Result<void> deleteResult = const Ok(null);
  Result<AddressDto> updateResult = Ok(AddressDto.fromJson(_addrJson(isDefault: true)));

  @override
  Future<Result<List<AddressDto>>> list() async => listResult;

  @override
  Future<Result<AddressDto>> update(String id, Map<String, dynamic> body) async => updateResult;

  @override
  Future<Result<void>> delete(String id) async => deleteResult;
}

void main() {
  Future<void> pump(WidgetTester tester, _FakeAddressRepository repo) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [addressRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/addresses', routes: [
          GoRoute(path: '/addresses', builder: (_, _) => const AddressListScreen()),
          GoRoute(path: '/address/new', builder: (_, _) => const Scaffold(body: Text('new address stub'))),
          GoRoute(path: '/address/:id/edit', builder: (_, _) => const Scaffold(body: Text('edit address stub'))),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders address cards with the serviceability chip and default badge', (tester) async {
    final repo = _FakeAddressRepository();
    repo.listResult = Ok([
      AddressDto.fromJson(_addrJson(id: 'a1', isDefault: true)),
    ]);
    await pump(tester, repo);

    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('12 MG Road'), findsOneWidget);
    expect(find.text('We serve this area'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('empty list -> shows empty state', (tester) async {
    final repo = _FakeAddressRepository();
    repo.listResult = const Ok([]);
    await pump(tester, repo);

    expect(find.textContaining('No addresses yet'), findsOneWidget);
  });

  testWidgets('delete Failure shows the error SnackBar (does not silently swallow)', (tester) async {
    final repo = _FakeAddressRepository();
    repo.listResult = Ok([AddressDto.fromJson(_addrJson(id: 'a1'))]);
    repo.deleteResult = const Failure(FailureKind.server, 'cannot delete address');
    await pump(tester, repo);

    await tester.tap(find.byKey(const Key('addrMenu_a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('cannot delete address'), findsOneWidget);
  });

  testWidgets('set-default Failure shows the error SnackBar (does not silently swallow)', (tester) async {
    final repo = _FakeAddressRepository();
    repo.listResult = Ok([AddressDto.fromJson(_addrJson(id: 'a1', isDefault: false))]);
    repo.updateResult = const Failure(FailureKind.validation, 'cannot set default');
    await pump(tester, repo);

    await tester.tap(find.byKey(const Key('addrMenu_a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as default'));
    await tester.pumpAndSettle();

    expect(find.text('cannot set default'), findsOneWidget);
  });
}
