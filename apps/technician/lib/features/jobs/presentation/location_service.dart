import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// The outcome of one location read: a precise [LocationFix], or a
/// [LocationProblem] that says WHY there is none, so the caller can tell the
/// technician exactly what to fix (and link to the right settings page).
sealed class LocationResult {
  const LocationResult();
}

/// A precise device position. (A plain value, not geolocator's `Position`, so
/// fakes are trivial.)
@immutable
class LocationFix extends LocationResult {
  const LocationFix(this.lat, this.lng);
  final double lat;
  final double lng;
}

enum LocationProblemKind {
  /// The device's location services switch is off.
  servicesOff,

  /// Permission denied this time (the OS can still prompt again).
  denied,

  /// Permission permanently denied — only the app's settings page can fix it.
  deniedForever,

  /// Permission granted, but only "Approximate" location. Never used for the
  /// arrival geofence: approximate coordinates would fail it with no hint.
  reducedAccuracy,

  /// No fix within the time limit, or any platform error.
  unavailable,
}

@immutable
class LocationProblem extends LocationResult {
  const LocationProblem(this.kind);
  final LocationProblemKind kind;
}

/// One-shot device location seam, shared by the arrival handshake
/// (Key('arriveBtn') on job_detail_screen.dart) and the capture-time photo
/// geotag (ImagePickerCameraService in photo_capture.dart) — one permission
/// flow, so the two can never drift. Never throws.
abstract class LocationService {
  Future<LocationResult> current();
}

/// The real, on-device location service: service-enabled check -> permission
/// check -> request -> precise-accuracy check -> read position (time-boxed).
class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationProblem(LocationProblemKind.servicesOff);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return const LocationProblem(LocationProblemKind.deniedForever);
      }
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        return const LocationProblem(LocationProblemKind.denied);
      }
      // Android 12+ / iOS 14+ let the user grant only approximate location.
      // Do NOT return approximate coordinates: say so, so the technician can
      // turn on Precise location.
      if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced) {
        return const LocationProblem(LocationProblemKind.reducedAccuracy);
      }
      // Time-boxed: indoors / no GPS fix, getCurrentPosition would otherwise
      // hang indefinitely and strand the technician on a spinner at the
      // customer's door. The resulting TimeoutException is caught below,
      // same as any other location failure -> unavailable.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationFix(pos.latitude, pos.longitude);
    } catch (_) {
      // Nothing logged: no coordinates or platform detail leave this method.
      return const LocationProblem(LocationProblemKind.unavailable);
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());
