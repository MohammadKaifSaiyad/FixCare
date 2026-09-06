// Backend contract-smoke test.
//
// This is the ONE test that exercises the app's REAL dio requests against a
// REAL running backend + seeded dev DB — the layer the mocked-transport unit
// tests structurally can't see. It exists because two shipped bugs slipped
// past the mocked suite and were only caught by a real backend call:
//   - a bodyless DELETE that carried `content-type: application/json` (Fastify
//     rejected it with FST_ERR_CTP_EMPTY_JSON_BODY);
//   - request-shape drift the mocks happened to agree with.
//
// It is NOT part of the normal hermetic `flutter test`: if the backend isn't
// reachable on the base URL, the whole group SKIPS with a clear message, so the
// default suite stays green offline. To actually run it:
//   1. docker compose up -d            (from repo root)
//   2. cd apps/backend && set -a && source .env && set +a && pnpm dev
//   3. cd apps/backend && NODE_ENV=development pnpm db:seed   (zones/pincodes/catalog)
//   4. cd apps/customer && flutter test test/contract/backend_contract_smoke_test.dart \
//        --dart-define=BASE_URL=http://localhost:3000
//
// It uses a fresh random phone each run (the backend auto-registers a new phone
// as a CUSTOMER), so it leaves no shared-state footprint and is re-runnable.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fixcare_customer/core/env.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/auth/data/auth_repository.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/catalog/data/catalog_repository.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

/// A seeded serviceable pincode (see apps/backend/prisma/seed.ts).
const _seededPincode = '390001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory secure storage so the real auth interceptor can read/write tokens.
  final storage = <String, String>{};

  late ProviderContainer container;
  bool backendUp = false;

  // TestWidgetsFlutterBinding installs a global HttpOverrides that fakes every
  // HttpClient (returns 400, makes no real request) to keep unit tests hermetic.
  // This file is the deliberate exception: null out that override for the file's
  // lifetime so the app's real dio actually reaches the backend, and restore it
  // after. (Per-dio adapter tweaks can't escape a global HttpOverrides.)
  HttpOverrides? savedOverrides;

  setUpAll(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null; // real networking on
    // Probe the backend once. If it's not there, every test in the group skips.
    try {
      final probe = Dio(BaseOptions(
        baseUrl: Env.baseUrl,
        connectTimeout: const Duration(seconds: 3),
        validateStatus: (_) => true,
      ));
      final res = await probe.get<dynamic>('/health');
      backendUp = res.statusCode == 200;
    } catch (_) {
      backendUp = false;
    }
  });

  tearDownAll(() => HttpOverrides.global = savedOverrides);

  setUp(() {
    storage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'write':
            storage[args!['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            return storage[args!['key'] as String];
          case 'delete':
            storage.remove(args!['key'] as String);
            return null;
          case 'deleteAll':
            storage.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(storage);
          case 'containsKey':
            return storage.containsKey(args!['key'] as String);
        }
        return null;
      },
    );
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  // Returns true (and records a skip) when the backend isn't reachable, so the
  // default hermetic `flutter test` stays green offline. `backendUp` is set in
  // setUpAll, which runs BEFORE any test body but AFTER test collection — so
  // this is a RUNTIME check inside the body, not the `skip:` parameter (that's
  // evaluated at collection time, when backendUp is still false). Callers do
  // `if (skipNoBackend()) return;` at the top of the test.
  bool skipNoBackend() {
    if (backendUp) return false;
    markTestSkipped(
        'backend not reachable on ${Env.baseUrl} — start the backend + seed '
        'the dev DB to run the contract smoke (see file header)');
    return true;
  }

  /// Registers a fresh customer, saves the tokens to TokenStore (so the auth
  /// interceptor attaches them), and returns nothing — later repo calls are authed.
  Future<void> loginFreshCustomer() async {
    final auth = container.read(authRepositoryProvider);
    // A fresh, valid Indian mobile (starts 6-9, exactly 10 digits) UNIQUE per
    // call — the LAST 9 digits of the microsecond clock (the low digits, which
    // actually change between fast calls; the high digits don't). A repeated
    // phone would trip the backend's per-phone OTP send-throttle.
    final micros = DateTime.now().microsecondsSinceEpoch.toString();
    final phone = '9${micros.substring(micros.length - 9)}';
    final sent = await auth.sendOtp(phone);
    expect(sent, isA<Ok<SendOtpResponse>>(), reason: 'sendOtp should succeed against a real backend');
    final devOtp = (sent as Ok<SendOtpResponse>).value.devOtp;
    expect(devOtp, isNotNull,
        reason: 'the dev backend must echo devOtp — is NODE_ENV=development?');
    final verified = await auth.verifyOtp(phone, devOtp!);
    expect(verified, isA<Ok<VerifyResponse>>(), reason: 'verifyOtp should succeed');
    final v = (verified as Ok<VerifyResponse>).value;
    await container.read(tokenStoreProvider).save(access: v.accessToken, refresh: v.refreshToken);
  }

  group('backend contract smoke (real dio → real backend)', () {
    test('auth: send OTP → verify → real tokens', () async {
      if (skipNoBackend()) return;
      await loginFreshCustomer();
      expect(await container.read(tokenStoreProvider).readAccess(), isNotNull);
    });

    test('profile: get → updateName → get reflects it', () async {
      if (skipNoBackend()) return;
      await loginFreshCustomer();
      final repo = container.read(profileRepositoryProvider);
      final before = await repo.getProfile();
      expect(before, isA<Ok<CustomerProfileDto>>());
      final updated = await repo.updateName('Smoke Test');
      expect(updated, isA<Ok<CustomerProfileDto>>());
      expect((updated as Ok<CustomerProfileDto>).value.name, 'Smoke Test');
      final after = await repo.getProfile();
      expect((after as Ok<CustomerProfileDto>).value.name, 'Smoke Test');
    });

    test('address: create (serviceable) → list → DELETE → gone', () async {
      if (skipNoBackend()) return;
      await loginFreshCustomer();
      final repo = container.read(addressRepositoryProvider);

      final created = await repo.create({
        'label': 'Smoke Home',
        'line1': '1 Contract St',
        'pincode': _seededPincode,
        'isDefault': true,
      });
      expect(created, isA<Ok<AddressDto>>(), reason: 'create address should 201');
      final addr = (created as Ok<AddressDto>).value;
      expect(addr.serviceable, isTrue,
          reason: 'pincode $_seededPincode must be seeded serviceable — run pnpm db:seed');
      expect(addr.zone, isNotNull);

      final listed = await repo.list();
      expect(listed, isA<Ok<List<AddressDto>>>());
      expect((listed as Ok<List<AddressDto>>).value.any((a) => a.id == addr.id), isTrue);

      // THE bug this whole file guards: a bodyless DELETE must not carry a json
      // content-type. Against the real backend, a broken client 400s here.
      final deleted = await repo.delete(addr.id);
      expect(deleted, isA<Ok<void>>(),
          reason: 'DELETE must succeed — a global json content-type on a bodyless '
              'request triggers Fastify FST_ERR_CTP_EMPTY_JSON_BODY');

      final after = await repo.list();
      expect((after as Ok<List<AddressDto>>).value.any((a) => a.id == addr.id), isFalse);
    });

    test('catalog: categories + per-zone services are seeded', () async {
      if (skipNoBackend()) return;
      await loginFreshCustomer();
      final addrRepo = container.read(addressRepositoryProvider);
      final created = await addrRepo.create(
          {'label': 'Z', 'line1': '1 St', 'pincode': _seededPincode, 'isDefault': true});
      final zoneId = (created as Ok<AddressDto>).value.zone!.id;

      final cat = container.read(catalogRepositoryProvider);
      final cats = await cat.categories();
      expect(cats, isA<Ok<List<CategoryDto>>>());
      expect((cats as Ok<List<CategoryDto>>).value, isNotEmpty,
          reason: 'no categories — run pnpm db:seed');

      final svcs = await cat.services(zoneId: zoneId);
      expect(svcs, isA<Ok<List<ServiceDto>>>());
      expect((svcs as Ok<List<ServiceDto>>).value, isNotEmpty,
          reason: 'no services for the seeded zone — run pnpm db:seed');
    });

    test('booking: create → get → cancel', () async {
      if (skipNoBackend()) return;
      await loginFreshCustomer();
      final addrRepo = container.read(addressRepositoryProvider);
      final created = await addrRepo.create(
          {'label': 'B', 'line1': '1 St', 'pincode': _seededPincode, 'isDefault': true});
      final addr = (created as Ok<AddressDto>).value;

      final cat = container.read(catalogRepositoryProvider);
      final svcs = (await cat.services(zoneId: addr.zone!.id)) as Ok<List<ServiceDto>>;
      final serviceId = svcs.value.first.id;

      // A slot a few days out (comfortably future, avoids the past-slot guard).
      final slot = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();

      final booking = container.read(bookingRepositoryProvider);
      final createdBooking =
          await booking.create(addressId: addr.id, serviceId: serviceId, scheduledSlot: slot);
      expect(createdBooking, isA<Ok<BookingDto>>(), reason: 'create booking should succeed');
      final b = (createdBooking as Ok<BookingDto>).value;
      expect(b.bookingNumber, startsWith('FC-'));
      expect(b.state, 'DISPATCHED');

      final fetched = await booking.get(b.id);
      expect((fetched as Ok<BookingDto>).value.id, b.id);

      final cancelled = await booking.cancel(b.id);
      expect(cancelled, isA<Ok<void>>());
    });
  });
}
