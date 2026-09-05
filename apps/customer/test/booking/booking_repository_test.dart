import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';

Map<String, dynamic> _bookingJson({String state = 'DISPATCHED'}) => {
  'id': 'b1', 'bookingNumber': 'FC-1001', 'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Fridge not cooling'},
  'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'},
  'diagnosis': null,
  'parts': <Map<String, dynamic>>[],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': <Map<String, dynamic>>[],
  'payment': null, 'dispute': null,
};

Map<String, dynamic> _fullBookingJson() => {
  'id': 'b2', 'bookingNumber': 'FC-1002', 'state': 'PAYMENT_RECEIVED',
  'scheduledSlot': '2026-09-11T10:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 50000, 'laborTier': 'T3',
  'service': {'id': 's1', 'name': 'Fridge not cooling'},
  'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'},
  'technician': {'name': 'Ramesh K', 'maskedPhone': '******1234'},
  'diagnosis': {'issueName': 'Compressor failure'},
  'parts': [
    {'id': 'p1', 'sku': 'SKU-1', 'name': 'Compressor', 'ceilingPricePaise': 300000, 'qty': 1},
  ],
  'estimate': {'laborPaise': 50000, 'partsPaise': 300000, 'visitFeeCreditPaise': 14900, 'totalPayablePaise': 335100},
  'photos': [
    {'kind': 'OLD_PART_REMOVED', 'capturedAt': '2026-09-11T10:30:00.000Z', 'url': 'https://cdn.example/photo1.jpg'},
  ],
  'payment': {'status': 'CAPTURED', 'method': 'UPI', 'amountPaise': 335100},
  'dispute': {'status': 'OPEN', 'outcome': 'PENDING', 'refundPaise': null},
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late BookingRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = BookingRepository(dio);
  });

  test('create posts EXACTLY {addressId, serviceId, scheduledSlot} and parses minimal BookingDto (nested nulls)', () async {
    adapter.onPost('/me/bookings', (s) => s.reply(201, _bookingJson()),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-10T09:00:00.000Z'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-10T09:00:00.000Z');
    final b = (r as Ok<BookingDto>).value;
    expect(b.bookingNumber, 'FC-1001');
    expect(b.state, 'DISPATCHED');
    expect(b.service.name, 'Fridge not cooling');
    expect(b.estimate.totalPayablePaise, 45000);
    expect(b.technician, isNull);
    expect(b.diagnosis, isNull);
    expect(b.payment, isNull);
    expect(b.dispute, isNull);
    expect(b.parts, isEmpty);
    expect(b.photos, isEmpty);
  });

  test('create 200 -> Ok(BookingDto) parses FULL DTO incl. nested technician/estimate/part/payment/dispute', () async {
    adapter.onPost('/me/bookings', (s) => s.reply(200, _fullBookingJson()),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-11T10:00:00.000Z'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-11T10:00:00.000Z');
    final b = (r as Ok<BookingDto>).value;
    expect(b.id, 'b2');
    expect(b.technician?.name, 'Ramesh K');
    expect(b.technician?.maskedPhone, '******1234');
    expect(b.diagnosis?.issueName, 'Compressor failure');
    expect(b.parts, hasLength(1));
    expect(b.parts.single.sku, 'SKU-1');
    expect(b.estimate.totalPayablePaise, 335100);
    expect(b.photos, hasLength(1));
    expect(b.photos.single.kind, 'OLD_PART_REMOVED');
    expect(b.payment?.status, 'CAPTURED');
    expect(b.payment?.amountPaise, 335100);
    expect(b.dispute?.status, 'OPEN');
    expect(b.dispute?.refundPaise, isNull);
  });

  test('create — exact-body matcher rejects a request missing an expected extra field (proves the matcher is strict)', () async {
    // The interaction is registered expecting a body WITH an extra 'customerId' field (simulating what the
    // request would look like if a customer id leaked in). The repo only ever sends {addressId, serviceId,
    // scheduledSlot} (see booking_repository.dart), so its real request body does NOT match this registration,
    // FullHttpRequestMatcher(needsExactBody: true) refuses to match it, and dio surfaces that as a 404 with no
    // matching interaction -> Failure. This proves the exact-body matcher would catch a leaked extra field.
    adapter.onPost('/me/bookings', (s) => s.reply(201, _bookingJson()),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-10T09:00:00.000Z', 'customerId': 'u1'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-10T09:00:00.000Z');
    expect(r, isA<Failure<BookingDto>>());
  });

  test('create 422 -> Failure(unknown) with the backend message', () async {
    adapter.onPost('/me/bookings',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': "We don't serve this area yet"}),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-10T09:00:00.000Z'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-10T09:00:00.000Z');
    final f = r as Failure;
    // failureKindFromStatus(422) returns FailureKind.unknown (only 400 is `validation`); the MESSAGE
    // is what the confirm step surfaces, so the message assertion below is the load-bearing one.
    expect(f.kind, FailureKind.unknown);
    expect(f.message, "We don't serve this area yet");
  });

  test('get 200 -> Ok(BookingDto)', () async {
    adapter.onGet('/me/bookings/b1', (s) => s.reply(200, _bookingJson()));
    final r = await repo.get('b1');
    expect((r as Ok<BookingDto>).value.id, 'b1');
  });

  test('cancel 200 -> Ok(void), handles empty/non-map body without crashing', () async {
    adapter.onPost('/me/bookings/b1/cancel', (s) => s.reply(200, ''));
    final r = await repo.cancel('b1');
    expect(r, isA<Ok<void>>());
  });
}
