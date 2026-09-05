import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/theme.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/address/presentation/address_form_screen.dart';

class _FakeAddrRepo extends AddressRepository {
  _FakeAddrRepo(this._serviceable) : super(Dio());
  final bool _serviceable;
  int createCalls = 0;
  Map<String, dynamic>? lastCreateBody;
  Result<AddressDto>? createResult;

  @override
  Future<Result<ServiceabilityDto>> checkServiceability(String pincode) async =>
      Ok(ServiceabilityDto(
        serviceable: _serviceable,
        zone: _serviceable ? const ZoneDto(id: 'z1', name: 'Vadodara', visitFeePaise: 14900) : null,
        message: _serviceable ? null : "We don't serve this area yet",
      ));

  @override
  Future<Result<AddressDto>> create(Map<String, dynamic> body) async {
    createCalls++; lastCreateBody = body;
    if (createResult != null) return createResult!;
    return Ok(AddressDto(
      id: 'a1', label: body['label'] as String, line1: body['line1'] as String,
      pincode: body['pincode'] as String, isDefault: false, status: 'ACTIVE',
      serviceable: _serviceable, zone: null,
    ));
  }

  @override
  Future<Result<List<AddressDto>>> list() async => const Ok([]);
}

Future<void> _pump(WidgetTester tester, _FakeAddrRepo repo) async {
  // The form's content (6 fields + map placeholder + switch + button)
  // exceeds the default 800x600 test surface, and off-screen sliver
  // children aren't built as Elements — so enlarge the surface to fit
  // the whole form without scrolling (test-only; production layout is
  // unaffected — real devices simply scroll).
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // A real GoRouter with a route stack (list -> new), matching the
  // project convention (see address_list_screen_widget_test.dart) so
  // context.pop() on save-success has somewhere to return to.
  final router = GoRouter(initialLocation: '/addresses', routes: [
    GoRoute(path: '/addresses', builder: (_, _) => const Scaffold(body: Text('addresses list stub'))),
    GoRoute(path: '/address/new', builder: (_, _) => const AddressFormScreen(addressId: null)),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [addressRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(theme: buildFixCareTheme(), routerConfig: router),
  ));
  router.push('/address/new');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('serviceable pincode shows the serve affordance', (tester) async {
    final repo = _FakeAddrRepo(true);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('pincodeField')), '390001');
    await tester.pump(const Duration(milliseconds: 450)); // debounce
    await tester.pumpAndSettle();
    expect(find.text('We serve this area'), findsOneWidget);
  });

  testWidgets('out-of-area shows warning but save stays enabled and saves', (tester) async {
    final repo = _FakeAddrRepo(false);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('labelField')), 'Home');
    await tester.enterText(find.byKey(const Key('line1Field')), '12 MG Road');
    await tester.enterText(find.byKey(const Key('pincodeField')), '999999');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Out of service area'), findsOneWidget);
    // Save is still enabled and calls create.
    await tester.tap(find.byKey(const Key('saveAddressBtn')));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.lastCreateBody!['pincode'], '999999');
  });

  testWidgets('save Failure surfaces the error instead of being swallowed', (tester) async {
    final repo = _FakeAddrRepo(true)
      ..createResult = const Failure(FailureKind.server, 'Something went wrong.');
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('labelField')), 'Home');
    await tester.enterText(find.byKey(const Key('line1Field')), '12 MG Road');
    await tester.enterText(find.byKey(const Key('pincodeField')), '390001');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveAddressBtn')));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(find.text('Something went wrong.'), findsOneWidget);
    // Still on the form (did not navigate away on failure).
    expect(find.byKey(const Key('saveAddressBtn')), findsOneWidget);
  });
}
