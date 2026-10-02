import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/onboarding/presentation/under_review_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_dto.dart';

TechnicianProfileDto _p(String status) => TechnicianProfileDto(
    id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['AC', 'WIRING'], status: status,
    zones: const [ZoneRefDto(id: 'z1', name: 'Padra')]);

class _FakeAuth extends AuthController {
  int refreshCalls = 0;
  Result<TechnicianProfileDto> next = Ok(_p('KYC_SUBMITTED'));
  @override
  Future<Session> build() async => SessionAuthenticated(_p('KYC_SUBMITTED'));
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return next;
  }
}

void main() {
  late _FakeAuth auth;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    auth = _FakeAuth();
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => auth)],
      child: const MaterialApp(home: UnderReviewScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('shows the copy and a read-only summary of what was submitted', (tester) async {
    await pump(tester);
    expect(find.text('Verification pending'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('verificationStatusText'))).data, 'Your details are with FixCare for verification');
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('AC, Wiring'), findsOneWidget);
    expect(find.text('Padra'), findsOneWidget);
    expect(auth.refreshCalls, 0); // no check on mount (the session was just loaded)
    await unmount(tester);
  });

  testWidgets('re-checks every 30 s while in the foreground', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 29));
    expect(auth.refreshCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.refreshCalls, 1);
    await tester.pump(reviewPollInterval);
    expect(auth.refreshCalls, 2);
    await unmount(tester);
  });

  testWidgets('pauses in the background; checks right away on resume', (tester) async {
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await pump(tester);
    for (final st in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump(const Duration(minutes: 3));
    expect(auth.refreshCalls, 0);
    for (final st in const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump();
    expect(auth.refreshCalls, 1);
    await tester.pump(reviewPollInterval);
    expect(auth.refreshCalls, 2);
    await unmount(tester);
  });

  testWidgets('Check status: still under review → a SnackBar; a failure → its message', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('checkStatusBtn')));
    await tester.pumpAndSettle();
    expect(find.text("Still under review. We'll update this screen when FixCare decides."), findsOneWidget);
    // Let the first SnackBar expire; a second one would otherwise queue behind it (test mechanics only).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    auth.next = const Failure(FailureKind.network, 'Network error. Check your connection.');
    await tester.tap(find.byKey(const Key('checkStatusBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('pull to refresh re-checks', (tester) async {
    await pump(tester);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(auth.refreshCalls, 1);
    await unmount(tester);
  });
}
