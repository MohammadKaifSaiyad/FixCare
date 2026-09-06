import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_address_label.dart';

AddressDto _addr(String id) => AddressDto.fromJson({
  'id': id, 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': true, 'status': 'ACTIVE',
  'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
});

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo(this._result) : super(Dio());
  final Result<List<AddressDto>> _result;
  @override
  Future<Result<List<AddressDto>>> list() async => _result;
}

void main() {
  test('matching id -> "label · line1, pincode"', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(_FakeAddressRepo(Ok([_addr('a1')]))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a1').future);
    expect(label, 'Home · 12 MG Road, 390001');
  });

  test('id not in the list -> falls back to the raw id', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(_FakeAddressRepo(Ok([_addr('a1')]))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a2').future);
    expect(label, 'a2');
  });

  test('list fetch fails -> falls back to the raw id (never throws)', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(
        _FakeAddressRepo(const Failure(FailureKind.network, 'offline'))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a1').future);
    expect(label, 'a1');
  });
}
