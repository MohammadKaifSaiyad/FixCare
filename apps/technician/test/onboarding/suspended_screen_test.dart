import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/onboarding/presentation/suspended_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_dto.dart';

TechnicianProfileDto _p({String? note}) =>
    TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', status: 'SUSPENDED', reviewNote: note);

class _FakeAuth extends AuthController {
  _FakeAuth(this.profile);
  final TechnicianProfileDto profile;
  int refreshCalls = 0;
  @override
  Future<Session> build() async => SessionAuthenticated(profile);
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return Ok(profile);
  }
}

void main() {
  Future<_FakeAuth> pump(WidgetTester tester, TechnicianProfileDto p) async {
    final auth = _FakeAuth(p);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => auth)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const SuspendedScreen()),
          GoRoute(path: '/earnings', builder: (_, _) => const Text('EARNINGS PAGE')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('shows the reason and the support pointer; Check again re-checks', (tester) async {
    final auth = await pump(tester, _p(note: 'Customer complaint under review'));
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Customer complaint under review'), findsOneWidget);
    expect(find.text('Contact FixCare support'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkAgainBtn')));
    await tester.pumpAndSettle();
    expect(auth.refreshCalls, 1);
    expect(find.text('Your account is still suspended.'), findsOneWidget);
  });

  testWidgets('no reason → no reason box', (tester) async {
    await pump(tester, _p());
    expect(find.byKey(const Key('suspensionReason')), findsNothing);
  });

  testWidgets('a 500-character reason wraps on a 320 px wide phone (no overflow)', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, _p(note: 'word ' * 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Earnings button is there and opens /earnings', (tester) async {
    await pump(tester, _p());
    expect(find.byKey(const Key('earningsBtn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('earningsBtn')));
    await tester.pumpAndSettle();
    expect(find.text('EARNINGS PAGE'), findsOneWidget);
  });
}
