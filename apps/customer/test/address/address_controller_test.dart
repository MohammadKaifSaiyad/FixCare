import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/address/presentation/address_controller.dart';

Map<String, dynamic> _addrJson({String id = 'a1', bool isDefault = false}) => {
  'id': id, 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': true,
  'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
};

/// Fully controllable fake — each call is independently scriptable so tests
/// can assert both the happy path and the Failure path without hitting Dio.
class _FakeAddressRepository extends AddressRepository {
  _FakeAddressRepository() : super(Dio());

  Result<List<AddressDto>> listResult = Ok([AddressDto.fromJson(_addrJson())]);
  Result<AddressDto> updateResult = Ok(AddressDto.fromJson(_addrJson(isDefault: true)));
  Result<void> deleteResult = const Ok(null);

  int listCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;

  @override
  Future<Result<List<AddressDto>>> list() async {
    listCalls++;
    return listResult;
  }

  @override
  Future<Result<AddressDto>> update(String id, Map<String, dynamic> body) async {
    updateCalls++;
    return updateResult;
  }

  @override
  Future<Result<void>> delete(String id) async {
    deleteCalls++;
    return deleteResult;
  }
}

void main() {
  late _FakeAddressRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeAddressRepository();
    container = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  test('build() -> list() Ok returns the list', () async {
    repo.listResult = Ok([AddressDto.fromJson(_addrJson(id: 'a1')), AddressDto.fromJson(_addrJson(id: 'a2'))]);
    final list = await container.read(addressControllerProvider.future);
    expect(list.map((a) => a.id), ['a1', 'a2']);
  });

  test('build() -> list() Failure surfaces as AsyncError (not silently empty)', () async {
    repo.listResult = const Failure(FailureKind.server, 'boom');

    // Keep the provider subscribed for the whole async gap: reading `.future`
    // on an autoDispose provider with nothing else listening races the
    // container's dispose scheduler once the future rejects, surfacing a
    // StateError instead of the build's real exception. A live subscription
    // (mirroring what ref.watch does from the widget tree) keeps it alive
    // long enough for the rejection to be observed correctly.
    AsyncValue<List<AddressDto>>? last;
    final sub = container.listen(addressControllerProvider, (_, next) => last = next);
    addTearDown(sub.close);

    await pumpEventQueue();

    expect(last!.hasError, isTrue);
    expect(last!.error, isA<Exception>());
  });

  test('refresh() reloads the list', () async {
    await container.read(addressControllerProvider.future);
    repo.listResult = Ok([AddressDto.fromJson(_addrJson(id: 'a2'))]);

    await container.read(addressControllerProvider.notifier).refresh();

    final state = container.read(addressControllerProvider);
    expect(state.value!.map((a) => a.id), ['a2']);
    expect(repo.listCalls, 2);
  });

  test('setDefault() Ok -> calls update then refreshes, returns Ok', () async {
    await container.read(addressControllerProvider.future);

    final r = await container.read(addressControllerProvider.notifier).setDefault('a1');

    expect(r, isA<Ok<void>>());
    expect(repo.updateCalls, 1);
    expect(repo.listCalls, 2); // initial build + refresh after setDefault
  });

  test('setDefault() Failure -> returns Failure (does NOT throw, does NOT refresh)', () async {
    await container.read(addressControllerProvider.future);
    repo.updateResult = const Failure(FailureKind.validation, 'cannot set default');

    final r = await container.read(addressControllerProvider.notifier).setDefault('a1');

    expect(r, isA<Failure<void>>());
    expect((r as Failure<void>).message, 'cannot set default');
    expect(repo.listCalls, 1); // no refresh on failure
  });

  test('remove() Ok -> calls delete then refreshes, returns Ok', () async {
    await container.read(addressControllerProvider.future);

    final r = await container.read(addressControllerProvider.notifier).remove('a1');

    expect(r, isA<Ok<void>>());
    expect(repo.deleteCalls, 1);
    expect(repo.listCalls, 2);
  });

  test('remove() Failure -> returns Failure (does NOT throw, does NOT refresh)', () async {
    await container.read(addressControllerProvider.future);
    repo.deleteResult = const Failure(FailureKind.server, 'cannot delete');

    final r = await container.read(addressControllerProvider.notifier).remove('a1');

    expect(r, isA<Failure<void>>());
    expect((r as Failure<void>).message, 'cannot delete');
    expect(repo.listCalls, 1);
  });
}
