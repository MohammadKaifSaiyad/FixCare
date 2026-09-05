import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import 'package:fixcare_customer/core/router/app_router.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

/// Fake profile repo: getProfile returns a named profile so boot hydration lands on home.
class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

/// The router's redirect is driven by AuthController.build(), which reads the
/// access token from secure storage. We mock the secure-storage channel to an
/// in-memory map so we can control token presence per test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

  void mockStorage() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write':
            backing[call.arguments['key'] as String] = call.arguments['value'] as String;
            return null;
          case 'read':
            return backing[call.arguments['key'] as String];
          case 'delete':
            backing.remove(call.arguments['key'] as String);
            return null;
          case 'deleteAll':
            backing.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(backing);
          case 'containsKey':
            return backing.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  }

  setUp(() {
    backing.clear();
    mockStorage();
  });

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(_FakeProfileRepo())],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(goRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('no token → lands on phone entry', (tester) async {
    final router = await pumpApp(tester);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/phone',
    );
  });

  testWidgets('token present → lands on home', (tester) async {
    backing['fixcare.access'] = 'a-token';
    backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/home',
    );
  });
}
