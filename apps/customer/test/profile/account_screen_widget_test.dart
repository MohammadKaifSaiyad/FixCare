import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/router/app_router.dart';
import 'package:fixcare_customer/features/auth/data/auth_repository.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

/// Named profile so boot hydration lands the session on /home directly.
class _NamedRepo extends ProfileRepository {
  _NamedRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio());
  @override
  Future<Result<void>> logout(String refresh) async => const Ok(null);
}

/// getProfile succeeds (boot hydrates to /home) but updateName always fails —
/// exercises the name-edit error path (the review-round-1 fix).
class _UpdateNameFailsRepo extends ProfileRepository {
  _UpdateNameFailsRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      const Failure(FailureKind.validation, 'name must not be empty');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

  setUp(() {
    backing
      ..clear()
      ..addAll({
        'fixcare.access': 'a',
        'fixcare.refresh': 'r',
        'fixcare.phone': '9876543210',
      });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
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

  Future<GoRouter> pump(WidgetTester tester, {ProfileRepository? profileRepo}) async {
    late GoRouter router;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo ?? _NamedRepo()),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      ],
      child: Consumer(builder: (c, ref, _) {
        router = ref.watch(goRouterProvider);
        return MaterialApp.router(routerConfig: router);
      }),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('home avatar navigates to /account showing name + sign out', (tester) async {
    await pump(tester);
    expect(find.text('What needs fixing?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('accountAvatar')));
    await tester.pumpAndSettle();

    // Landed on the Account screen (AppBar title + the pushed name/sign-out UI).
    expect(find.widgetWithText(AppBar, 'Account'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.byKey(const Key('signOutBtn')), findsOneWidget);
    // Phone read from the token store, shown plain — never logged.
    expect(find.textContaining('9876543210'), findsOneWidget);
  });

  testWidgets('sign out clears session and returns to /phone', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('accountAvatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('signOutBtn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('phoneField')), findsOneWidget);
  });

  testWidgets('editing name calls updateName and reflects the new value', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('accountAvatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editNameBtn')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'Ravi Kumar');
    await tester.tap(find.byKey(const Key('accountNameSave')));
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
  });

  testWidgets('my addresses row navigates to /addresses', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('accountAvatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('myAddressesTile')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Addresses'), findsOneWidget);
  });

  testWidgets('name-edit failure shows the error and does not update the name', (tester) async {
    await pump(tester, profileRepo: _UpdateNameFailsRepo());
    await tester.tap(find.byKey(const Key('accountAvatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editNameBtn')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('accountNameField')), 'Ravi Kumar');
    await tester.tap(find.byKey(const Key('accountNameSave')));
    await tester.pumpAndSettle();

    // Error surfaced, field stays open for retry (not swallowed) — the save
    // button is still the edit-mode "check" icon, not the read-only "Edit" tile.
    expect(find.text('name must not be empty'), findsOneWidget);
    expect(find.byKey(const Key('accountNameField')), findsOneWidget);
    expect(find.byKey(const Key('accountNameSave')), findsOneWidget);
    expect(find.byKey(const Key('editNameBtn')), findsNothing);
    // The read-only "Ravi" label is gone (we're mid-edit) and the session's
    // name was never updated to "Ravi Kumar" — only the local unsaved draft.
    expect(find.widgetWithText(AppBar, 'Account'), findsOneWidget);
  });
}
