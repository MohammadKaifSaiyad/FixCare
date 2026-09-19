import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/router/app_router.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

/// Fake profile repo per test: the boot hydration reads getProfile() to
/// resolve the session's TechnicianStatus (VERIFIED/PENDING/SUSPENDED/...).
class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo(this._status) : super(Dio());
  final String _status;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async => Ok(
        TechnicianProfileDto(
          id: 't1',
          role: 'TECHNICIAN',
          name: 'Ramesh',
          skills: const ['FAN'],
          status: _status,
        ),
      );
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

  Future<GoRouter> pumpApp(WidgetTester tester, {String? status}) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (status != null)
            technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(status)),
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

  testWidgets('token + VERIFIED session → reaches /home (not redirected to /phone)',
      (tester) async {
    backing['fixcare.access'] = 'a-token';
    backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'VERIFIED');
    // JobsHomeScreen doesn't exist until Task 6; /home's verified branch is a
    // temporary placeholder (VerificationPendingScreen). Assert routing
    // actually reached /home rather than bouncing back to /phone.
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('token + PENDING session → verification screen, "under review" copy',
      (tester) async {
    backing['fixcare.access'] = 'a-token';
    backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'PENDING');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('verificationPendingScreen')), findsOneWidget);
    final bodyText = tester.widget<Text>(find.byKey(const Key('verificationStatusText')));
    expect(bodyText.data, contains('under review'));
  });

  testWidgets('token + SUSPENDED session → verification screen, "suspended" copy',
      (tester) async {
    backing['fixcare.access'] = 'a-token';
    backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'SUSPENDED');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('verificationPendingScreen')), findsOneWidget);
    final bodyText = tester.widget<Text>(find.byKey(const Key('verificationStatusText')));
    expect(bodyText.data, contains('suspended'));
  });
}
