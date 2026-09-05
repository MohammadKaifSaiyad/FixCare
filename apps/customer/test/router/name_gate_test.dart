import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/router/app_router.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _NamelessRepo extends ProfileRepository {
  _NamelessRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: '', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

class _NamedRepo extends ProfileRepository {
  _NamedRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

/// getProfile fails on network → the controller falls back to an unhydrated
/// authenticated session (see AuthController._hydrate, Failure() branch).
class _NetworkBlipRepo extends ProfileRepository {
  _NetworkBlipRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Failure(FailureKind.network, 'Network error. Check your connection.');
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{'fixcare.access': 'a', 'fixcare.refresh': 'r'};

  void mockStorage() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': backing[call.arguments['key'] as String] = call.arguments['value'] as String; return null;
          case 'read': return backing[call.arguments['key'] as String];
          case 'delete': backing.remove(call.arguments['key'] as String); return null;
          case 'deleteAll': backing.clear(); return null;
          case 'readAll': return Map<String, String>.from(backing);
          case 'containsKey': return backing.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  }

  setUp(mockStorage);

  Future<String> pump(WidgetTester tester, ProfileRepository repo) async {
    late GoRouter router;
    await tester.pumpWidget(ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: Consumer(builder: (c, ref, _) {
        router = ref.watch(goRouterProvider);
        return MaterialApp.router(routerConfig: router);
      }),
    ));
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri.path;
  }

  testWidgets('authenticated + hydrated + empty name -> /name', (tester) async {
    expect(await pump(tester, _NamelessRepo()), '/name');
  });

  testWidgets('authenticated + hydrated + named -> /home', (tester) async {
    expect(await pump(tester, _NamedRepo()), '/home');
  });

  testWidgets('authenticated + NOT hydrated (network blip) + empty name -> /home (no gate)',
      (tester) async {
    expect(await pump(tester, _NetworkBlipRepo()), '/home');
  });
}
