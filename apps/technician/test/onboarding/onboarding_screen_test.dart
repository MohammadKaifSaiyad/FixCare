import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/onboarding/presentation/onboarding_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

const _padra = ZoneRefDto(id: 'z1', name: 'Padra');
const _vadodara = ZoneRefDto(id: 'z2', name: 'Vadodara');

TechnicianProfileDto _profile({String name = 'Ramesh', List<String> skills = const ['AC'], List<ZoneRefDto> zones = const [_padra], String? reviewNote}) =>
    TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: name, skills: skills, status: 'PENDING', zones: zones, reviewNote: reviewNote);

class _FakeAuth extends AuthController {
  _FakeAuth(this._session);
  final Session _session;
  int refreshCalls = 0;
  @override
  Future<Session> build() async => _session;
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return Ok(_profile());
  }
}

class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo() : super(Dio());
  final calls = <String>[];
  Map<String, Object?>? lastPatch;
  List<Result<TechnicianProfileDto>> patchResults = [Ok(_profile())];
  List<Result<TechnicianProfileDto>> submitResults = [Ok(_profile())];
  @override
  Future<Result<TechnicianProfileDto>> updateProfile({required String name, required List<String> skills, required List<String> zoneIds}) async {
    calls.add('patch');
    lastPatch = {'name': name, 'skills': skills, 'zoneIds': zoneIds};
    return patchResults.length > 1 ? patchResults.removeAt(0) : patchResults.first;
  }
  @override
  Future<Result<TechnicianProfileDto>> submit() async {
    calls.add('submit');
    return submitResults.length > 1 ? submitResults.removeAt(0) : submitResults.first;
  }
}

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog(this.results) : super(Dio());
  final List<Result<List<ZoneRefDto>>> results;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<Result<List<ZoneRefDto>>> zones() async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    if (gate case final g?) await g.future;
    return r;
  }
}

void main() {
  late _FakeAuth auth;
  late _FakeProfileRepo profileRepo;
  late _FakeCatalog catalog;

  /// Builds the screen only once the session has loaded — exactly what HomeGate guarantees in the app
  /// (the screen prefills from the session in initState).
  Future<void> pump(WidgetTester tester, {TechnicianProfileDto? profile, List<Result<List<ZoneRefDto>>>? zones, _FakeCatalog? catalogOverride, bool settle = true}) async {
    auth = _FakeAuth(SessionAuthenticated(profile ?? _profile()));
    profileRepo = _FakeProfileRepo();
    catalog = catalogOverride ?? _FakeCatalog(zones ?? [const Ok([_padra, _vadodara])]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        technicianProfileRepositoryProvider.overrideWithValue(profileRepo),
        catalogRepositoryProvider.overrideWithValue(catalog),
      ],
      child: MaterialApp(
        home: Consumer(builder: (_, ref, _) => ref.watch(authControllerProvider).hasValue ? const OnboardingScreen() : const SizedBox()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  FilledButton submitBtn(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('submitForVerificationBtn')));

  Future<void> submitAndConfirm(WidgetTester tester) async {
    // A SnackBar from an earlier attempt could sit over the button.
    ScaffoldMessenger.of(tester.element(find.byType(OnboardingScreen))).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('submitForVerificationBtn')));
    await tester.tap(find.byKey(const Key('submitForVerificationBtn')));
    await tester.pumpAndSettle();
    expect(find.text(kSubmitConfirmBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmSubmitBtn')));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills name, skills and zones from the profile; submit enabled', (tester) async {
    await pump(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('nameField'))).controller!.text, 'Ramesh');
    expect(tester.widget<FilterChip>(find.byKey(const Key('skill_AC'))).selected, true);
    expect(tester.widget<FilterChip>(find.byKey(const Key('skill_FAN'))).selected, false);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('zone_z1'))).value, true);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('zone_z2'))).value, false);
    expect(submitBtn(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('sentBackBanner')), findsNothing);
  });

  testWidgets('submit disabled without a name, a skill or a zone', (tester) async {
    await pump(tester, profile: _profile(name: '', skills: const [], zones: const []));
    expect(submitBtn(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('nameField')), 'Ramesh');
    await tester.tap(find.byKey(const Key('skill_FAN')));
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNull); // still no zone
    await tester.tap(find.byKey(const Key('zone_z2')));
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('nameField')), '   ');
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNull);
  });

  testWidgets('sent back: the banner shows ops\' reason', (tester) async {
    await pump(tester, profile: _profile(reviewNote: 'Remove Wiring unless you hold a licence'));
    expect(find.byKey(const Key('sentBackBanner')), findsOneWidget);
    expect(find.text('FixCare sent your profile back'), findsOneWidget);
    expect(find.text('Remove Wiring unless you hold a licence'), findsOneWidget);
    expect(find.text('Please fix and resubmit.'), findsOneWidget);
  });

  testWidgets('cancel in the confirm dialog sends nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('submitForVerificationBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelSubmitBtn')));
    await tester.pumpAndSettle();
    expect(profileRepo.calls, isEmpty);
  });

  testWidgets('confirm → save (trimmed, canonical order) → submit → refresh, in order', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('nameField')), '  Ramesh Patel ');
    await tester.tap(find.byKey(const Key('skill_WIRING')));
    await tester.tap(find.byKey(const Key('zone_z2')));
    await tester.pump();
    await submitAndConfirm(tester);
    expect(profileRepo.calls, ['patch', 'submit']);
    expect(profileRepo.lastPatch, {'name': 'Ramesh Patel', 'skills': ['AC', 'WIRING'], 'zoneIds': ['z1', 'z2']});
    expect(auth.refreshCalls, 1);
  });

  testWidgets('save failure → SnackBar with the message, no submit, button usable again', (tester) async {
    await pump(tester);
    profileRepo.patchResults = [const Failure(FailureKind.server, 'Choose service zones from the list')];
    await submitAndConfirm(tester);
    expect(find.text('Choose service zones from the list'), findsOneWidget);
    expect(profileRepo.calls, ['patch']);
    expect(submitBtn(tester).onPressed, isNotNull);
  });

  testWidgets('submit failure → SnackBar; tapping again re-saves then submits', (tester) async {
    await pump(tester);
    profileRepo.submitResults = [const Failure(FailureKind.network, 'Network error. Check your connection.'), Ok(_profile())];
    await submitAndConfirm(tester);
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await submitAndConfirm(tester);
    expect(profileRepo.calls, ['patch', 'submit', 'patch', 'submit']);
    expect(auth.refreshCalls, 1);
  });

  testWidgets('save answers PROFILE_LOCKED (an earlier submit landed) → re-checks the profile', (tester) async {
    await pump(tester);
    profileRepo.patchResults = [const Failure(FailureKind.unknown, 'Your profile is locked while under review', code: 'PROFILE_LOCKED')];
    await submitAndConfirm(tester);
    expect(auth.refreshCalls, 1);
    expect(profileRepo.calls, ['patch']);
  });

  testWidgets('a prefilled zone that is no longer offered is not sent', (tester) async {
    await pump(tester, profile: _profile(zones: const [_padra, ZoneRefDto(id: 'zOld', name: 'Old')]), zones: [const Ok([_padra])]);
    await submitAndConfirm(tester);
    expect(profileRepo.lastPatch!['zoneIds'], ['z1']);
  });

  testWidgets('zones: loading, then error with Retry, then empty state', (tester) async {
    final gated = _FakeCatalog([const Failure(FailureKind.server, 'boom'), const Ok(<ZoneRefDto>[])])..gate = Completer<void>();
    await pump(tester, profile: _profile(zones: const []), catalogOverride: gated, settle: false);
    expect(find.byKey(const Key('zonesLoading')), findsOneWidget);
    catalog.gate!.complete();
    catalog.gate = null;
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.byKey(const Key('zonesRetryBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zonesEmpty')), findsOneWidget);
    expect(submitBtn(tester).onPressed, isNull);
  });
}
