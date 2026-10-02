import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/domain/session.dart';
import 'package:fixcare_customer/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_customer/features/auth/presentation/otp_entry_screen.dart';
import 'package:fixcare_customer/features/auth/presentation/phone_entry_screen.dart';

const _mismatch = 'This number is registered as a FixCare technician. Please use the FixCare Pro app.';

class _FakeAuth extends AuthController {
  _FakeAuth(this.result);
  final Result<void> result;
  @override
  Future<Session> build() async => const SessionUnauthenticated();
  @override
  Future<Result<void>> submitOtp(String phone, String code) async => result;
}

void main() {
  Future<void> pumpAndVerify(WidgetTester tester, Result<void> result) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => _FakeAuth(result))],
      child: const MaterialApp(home: OtpEntryScreen(args: OtpArgs('9800000011', null))),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otpField')), '123456');
    await tester.tap(find.byKey(const Key('verifyBtn')));
    await tester.pumpAndSettle();
  }

  testWidgets('ROLE_MISMATCH → the server message, wrapped (no overflow at 320 px)', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unknown, _mismatch, code: 'ROLE_MISMATCH'));
    expect(find.text(_mismatch), findsOneWidget);
    expect(find.text("That code isn't right."), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong code still reads "That code isn\'t right."', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unauthorized, 'Invalid or expired OTP'));
    expect(find.text("That code isn't right."), findsOneWidget);
  });
}
