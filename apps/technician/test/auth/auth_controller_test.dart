import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo(this._result) : super(Dio());
  final Result<TechnicianProfileDto> _result;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async => _result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

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

  setUp(() { backing.clear(); mockStorage(); });

  Future<Session> boot(Result<TechnicianProfileDto> profileResult) async {
    final container = ProviderContainer(overrides: [
      technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileResult)),
    ]);
    addTearDown(container.dispose);
    return container.read(authControllerProvider.future);
  }

  test('no token -> Unauthenticated', () async {
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: ['FAN'], status: 'VERIFIED')));
    expect(s, isA<SessionUnauthenticated>());
  });

  test('token + VERIFIED profile -> Authenticated with isVerified true', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: ['FAN'], status: 'VERIFIED')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.isVerified, true);
  });

  test('token + PENDING profile -> Authenticated with isVerified false', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: '', skills: [], status: 'PENDING')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.isVerified, false);
  });

  test('token + 401 -> tokens cleared, Unauthenticated', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.unauthorized, 'stale'));
    expect(s, isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('token + network fail -> Authenticated NOT hydrated, PENDING fallback (isVerified false)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.network, 'offline'));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, false);
    expect(a.isVerified, false);
    expect(a.status, 'PENDING');
    expect(backing['fixcare.access'], 'a'); // not cleared
  });
}
