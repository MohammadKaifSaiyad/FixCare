import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fixcare_technician/features/jobs/presentation/location_service.dart';

/// Drives the REAL [GeolocatorLocationService] (the static `Geolocator` calls
/// delegate to `GeolocatorPlatform.instance`), so the permission / accuracy /
/// timeout mapping is tested without a device.
class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission checkResult = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  Object? accuracyError;
  Object? positionError;

  int requestCalls = 0;
  int positionCalls = 0;
  LocationSettings? lastSettings;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => checkResult;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    final e = accuracyError;
    if (e != null) throw e;
    return accuracy;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    positionCalls++;
    lastSettings = locationSettings;
    final e = positionError;
    if (e != null) throw e;
    return Position(
      latitude: 22.3,
      longitude: 73.2,
      timestamp: DateTime.utc(2026, 9, 20),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

Matcher _problem(LocationProblemKind kind) =>
    isA<LocationProblem>().having((p) => p.kind, 'kind', kind);

void main() {
  late _FakeGeolocator geo;
  final svc = GeolocatorLocationService();

  setUp(() {
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
  });

  test('granted + precise -> LocationFix with the coordinates, read with a 20s time limit', () async {
    final r = await svc.current();

    expect(r, isA<LocationFix>());
    final fix = r as LocationFix;
    expect((fix.lat, fix.lng), (22.3, 73.2));
    expect(geo.lastSettings?.timeLimit, const Duration(seconds: 20));
    expect(geo.lastSettings?.accuracy, LocationAccuracy.high);
  });

  test('location services off -> servicesOff (no permission prompt, no read)', () async {
    geo.serviceEnabled = false;

    expect(await svc.current(), _problem(LocationProblemKind.servicesOff));
    expect(geo.requestCalls, 0);
    expect(geo.positionCalls, 0);
  });

  test('denied, then the prompt is denied again -> denied', () async {
    geo
      ..checkResult = LocationPermission.denied
      ..requestResult = LocationPermission.denied;

    expect(await svc.current(), _problem(LocationProblemKind.denied));
    expect(geo.requestCalls, 1);
    expect(geo.positionCalls, 0);
  });

  test('denied, then granted at the prompt -> fix', () async {
    geo
      ..checkResult = LocationPermission.denied
      ..requestResult = LocationPermission.whileInUse;

    expect(await svc.current(), isA<LocationFix>());
    expect(geo.requestCalls, 1);
  });

  test('already deniedForever -> deniedForever (the OS will not prompt again)', () async {
    geo.checkResult = LocationPermission.deniedForever;

    expect(await svc.current(), _problem(LocationProblemKind.deniedForever));
    expect(geo.requestCalls, 0);
  });

  test('denied, then "don\'t ask again" at the prompt -> deniedForever', () async {
    geo
      ..checkResult = LocationPermission.denied
      ..requestResult = LocationPermission.deniedForever;

    expect(await svc.current(), _problem(LocationProblemKind.deniedForever));
  });

  test('approximate location only -> reducedAccuracy, and NO coordinates are read', () async {
    geo.accuracy = LocationAccuracyStatus.reduced;

    expect(await svc.current(), _problem(LocationProblemKind.reducedAccuracy));
    expect(geo.positionCalls, 0);
  });

  test('accuracy status unknown (older Android) is not treated as reduced -> fix', () async {
    geo.accuracy = LocationAccuracyStatus.unknown;

    expect(await svc.current(), isA<LocationFix>());
  });

  test('no fix within the time limit -> unavailable (never throws)', () async {
    geo.positionError = TimeoutException('no fix');

    expect(await svc.current(), _problem(LocationProblemKind.unavailable));
  });

  test('any platform error -> unavailable (never throws)', () async {
    geo.accuracyError = StateError('channel down');

    expect(await svc.current(), _problem(LocationProblemKind.unavailable));
  });
}
