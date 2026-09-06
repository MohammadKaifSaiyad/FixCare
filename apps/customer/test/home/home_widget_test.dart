import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/catalog/data/catalog_repository.dart';
import 'package:fixcare_customer/features/home/presentation/home_screen.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

Map<String, dynamic> _addr({bool isDefault = true}) => {
  'id': 'a1', 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
};

Map<String, dynamic> _nonServiceableDefaultAddr() => {
  'id': 'a2', 'label': 'Farmhouse', 'line1': '1 Out of Zone Rd', 'line2': null, 'landmark': null,
  'pincode': '390099', 'lat': null, 'lng': null, 'isDefault': true, 'status': 'ACTIVE',
  'serviceable': false, 'zone': null,
};

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo(this._list) : super(Dio());
  final List<AddressDto> _list;
  @override
  Future<Result<List<AddressDto>>> list() async => Ok(_list);
}

class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());
  @override
  Future<Result<List<CategoryDto>>> categories() async =>
      const Ok([CategoryDto(id: 'c1', name: 'Refrigerator', status: 'ACTIVE')]);
  @override
  Future<Result<List<ServiceDto>>> services({required String zoneId, String? categoryId}) async =>
      const Ok([ServiceDto(id: 's1', name: 'Fridge not cooling', tier: 'T2', categoryId: 'c1', laborPaise: 45000, visitFeePaise: 14900)]);
}

/// Named profile so the avatar shows real initials ("Kaif Saiyad" → "KS").
class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Kaif Saiyad', status: 'ACTIVE'));
}

Future<void> _pump(WidgetTester tester, {required AddressRepository addr, required CatalogRepository cat}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addressRepositoryProvider.overrideWithValue(addr),
      catalogRepositoryProvider.overrideWithValue(cat),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(initialLocation: '/home', routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/book/:serviceId', builder: (_, _) => const Scaffold(body: Text('wizard stub'))),
        GoRoute(path: '/address/new', builder: (_, _) => const Scaffold(body: Text('add address stub'))),
        GoRoute(path: '/account', builder: (_, _) => const Scaffold(body: Text('account stub'))),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Seed a token so AuthController.build() proceeds to _hydrate() (via the
  // overridden profile repo) instead of short-circuiting to Unauthenticated —
  // that's what makes the real profile name (and thus the avatar initials) load.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return call.arguments['key'] == 'fixcare.access' ? 'tok' : null;
          case 'readAll':
            return <String, String>{'fixcare.access': 'tok'};
          case 'containsKey':
            return call.arguments['key'] == 'fixcare.access';
        }
        return null;
      },
    );
  });

  testWidgets('with a default address, categories + priced service render', (tester) async {
    await _pump(tester, addr: _FakeAddressRepo([AddressDto.fromJson(_addr())]), cat: _FakeCatalogRepo());
    expect(find.text('Refrigerator'), findsWidgets);
    expect(find.text('Fridge not cooling'), findsOneWidget);
    expect(find.textContaining('149'), findsWidgets); // visit fee ₹149 teaser (14900 paise)
    // Avatar shows the customer's real initials, not a hardcoded value.
    expect(find.text('KS'), findsOneWidget); // "Kaif Saiyad" → "KS"
  });

  testWidgets('no default address -> add-address CTA, no crash', (tester) async {
    await _pump(tester, addr: _FakeAddressRepo(const []), cat: _FakeCatalogRepo());
    expect(find.byKey(const Key('homeAddAddressCta')), findsOneWidget);
    // never crashes trying to fetch services without a zone
  });

  testWidgets('default address is non-serviceable but another IS serviceable -> real catalog renders, not the CTA', (tester) async {
    await _pump(
      tester,
      addr: _FakeAddressRepo([
        AddressDto.fromJson(_nonServiceableDefaultAddr()),
        AddressDto.fromJson(_addr(isDefault: false)),
      ]),
      cat: _FakeCatalogRepo(),
    );
    // Finding 2+4 regression: a non-serviceable default must NOT hide the bookable
    // catalog when another address on the account is serviceable.
    expect(find.byKey(const Key('homeAddAddressCta')), findsNothing);
    expect(find.text('Refrigerator'), findsWidgets);
    expect(find.text('Fridge not cooling'), findsOneWidget);
  });
}
