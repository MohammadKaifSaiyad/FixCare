import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/router/app_router.dart';
import 'package:fixcare_customer/features/auth/data/auth_repository.dart';

/// Fake repo: send + verify always succeed; verify returns a real user so the
/// controller flips to Authenticated and the router lands on home.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio());

  int sendCalls = 0;
  int verifyCalls = 0;

  @override
  Future<Result<SendOtpResponse>> sendOtp(String phone) async {
    sendCalls++;
    return const Ok(SendOtpResponse(ok: true, devOtp: '123456'));
  }

  @override
  Future<Result<VerifyResponse>> verifyOtp(String phone, String code) async {
    verifyCalls++;
    return const Ok(VerifyResponse(
      accessToken: 'a',
      refreshToken: 'r',
      user: UserDto(id: 'u1', role: 'CUSTOMER', status: 'ACTIVE'),
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

  setUp(() {
    backing.clear();
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
  });

  testWidgets('phone → OTP → home happy path', (tester) async {
    final fakeRepo = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fakeRepo)],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(goRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Boot → no token → phone screen.
    expect(find.byKey(const Key('phoneField')), findsOneWidget);

    // Invalid number keeps us on phone with an error.
    await tester.enterText(find.byKey(const Key('phoneField')), '123');
    await tester.tap(find.byKey(const Key('continueBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
    expect(fakeRepo.sendCalls, 0);

    // Valid number → sendOtp → OTP screen.
    await tester.enterText(find.byKey(const Key('phoneField')), '9876543210');
    await tester.tap(find.byKey(const Key('continueBtn')));
    await tester.pumpAndSettle();
    expect(fakeRepo.sendCalls, 1);
    expect(find.byKey(const Key('otpField')), findsOneWidget);

    // Enter code → verifyOtp → home.
    await tester.enterText(find.byKey(const Key('otpField')), '123456');
    await tester.tap(find.byKey(const Key('verifyBtn')));
    await tester.pumpAndSettle();
    expect(fakeRepo.verifyCalls, 1);
    // Landed on the home shell.
    expect(find.text('What needs fixing?'), findsOneWidget);
  });

  testWidgets('wrong code shows inline error, stays on OTP', (tester) async {
    final repo = _WrongCodeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(goRouterProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('phoneField')), '9876543210');
    await tester.tap(find.byKey(const Key('continueBtn')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('otpField')), '000000');
    await tester.tap(find.byKey(const Key('verifyBtn')));
    await tester.pumpAndSettle();

    expect(find.text("That code isn't right."), findsOneWidget);
    expect(find.byKey(const Key('otpField')), findsOneWidget);
  });
}

class _WrongCodeRepo extends AuthRepository {
  _WrongCodeRepo() : super(Dio());

  @override
  Future<Result<SendOtpResponse>> sendOtp(String phone) async =>
      const Ok(SendOtpResponse(ok: true));

  @override
  Future<Result<VerifyResponse>> verifyOtp(String phone, String code) async =>
      const Failure(FailureKind.unauthorized, 'nope');
}
