import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/router/app_router.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog() : super(Dio());
  @override
  Future<Result<List<ZoneRefDto>>> zones() async => const Ok([ZoneRefDto(id: 'z1', name: 'Padra')]);
}

/// Fake profile repo per test: the boot hydration reads getProfile() to resolve the session's
/// TechnicianStatus. A null status simulates a failed (network) fetch → an unhydrated session.
class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo(this._status) : super(Dio());
  final String? _status;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async => switch (_status) {
        final String status => Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['FAN'], status: status)),
        null => const Failure(FailureKind.network, 'down'),
      };
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

  Future<GoRouter> pumpApp(WidgetTester tester, {String? status, bool profileFails = false}) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (status != null || profileFails)
            technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileFails ? null : status)),
          catalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
        ],
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
    expect(router.routerDelegate.currentConfiguration.uri.path, '/phone');
  });

  testWidgets('PENDING → onboarding form', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'PENDING');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('onboardingScreen')), findsOneWidget);
  });

  testWidgets('KYC_SUBMITTED → under review', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, status: 'KYC_SUBMITTED');
    expect(find.byKey(const Key('underReviewScreen')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('SUSPENDED and DEACTIVATED → suspended screen', (tester) async {
    for (final status in ['SUSPENDED', 'DEACTIVATED']) {
      backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
      await pumpApp(tester, status: status);
      expect(find.byKey(const Key('suspendedScreen')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('VERIFIED → jobs home', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, status: 'VERIFIED');
    expect(find.byKey(const Key('jobsHomeScreen')), findsOneWidget);
  });

  testWidgets('profile could not load → "Couldn\'t load your profile" + Retry, never a blank form', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, profileFails: true);
    expect(find.byKey(const Key('profileLoadError')), findsOneWidget);
    expect(find.text("Couldn't load your profile"), findsOneWidget);
    expect(find.byKey(const Key('onboardingScreen')), findsNothing);
    await tester.tap(find.byKey(const Key('retryProfileBtn')));
    await tester.pumpAndSettle();
    expect(find.text('down'), findsOneWidget); // the failure is shown, not swallowed
  });

  testWidgets('a non-verified technician on a job route is sent home', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'SUSPENDED');
    router.go('/job/b1');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('suspendedScreen')), findsOneWidget);
  });
}
