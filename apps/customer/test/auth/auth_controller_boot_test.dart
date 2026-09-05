import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/domain/session.dart';
import 'package:fixcare_customer/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo(this._result) : super(Dio());
  final Result<CustomerProfileDto> _result;
  @override
  Future<Result<CustomerProfileDto>> getProfile() async => _result;
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
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

  Future<Session> boot(Result<CustomerProfileDto> profileResult) async {
    final container = ProviderContainer(overrides: [
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileResult)),
    ]);
    addTearDown(container.dispose);
    return container.read(authControllerProvider.future);
  }

  test('no token -> Unauthenticated', () async {
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE')));
    expect(s, isA<SessionUnauthenticated>());
  });

  test('token + named profile -> Authenticated(hydrated, named)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.name, 'Ravi');
  });

  test('token + empty-name profile -> Authenticated(hydrated, name empty)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: '', status: 'ACTIVE')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.name, '');
  });

  test('token + 401 -> tokens cleared, Unauthenticated', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.unauthorized, 'stale'));
    expect(s, isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('token + network fail -> Authenticated but NOT hydrated (stays logged in)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.network, 'offline'));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, false);
    expect(backing['fixcare.access'], 'a'); // not cleared
  });
}
