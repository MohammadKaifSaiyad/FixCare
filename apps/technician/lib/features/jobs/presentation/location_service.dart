import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// One-shot device location seam for the arrival handshake (Key('arriveBtn')
/// on [job_detail_screen.dart]). Returns null on denied/disabled/failure —
/// the caller decides how to surface that; this never throws.
///
/// A plain record (not geolocator's `Position`, which has no public
/// constructor and so cannot be built in a fake for tests).
abstract class LocationService {
  Future<({double lat, double lng})?> current();
}

/// The real, on-device location service. Mirrors the exact permission flow
/// used by the camera-evidence pipeline's one-shot geotag read
/// (`ImagePickerCameraService._defaultReadLocation` in photo_capture.dart):
/// service-enabled check -> permission check -> request -> read position,
/// swallowing every failure into a null result (best-effort, never blocks).
class GeolocatorLocationService implements LocationService {
  @override
  Future<({double lat, double lng})?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      // Time-boxed: indoors / no GPS fix, getCurrentPosition would otherwise
      // hang indefinitely and strand the technician on a spinner at the
      // customer's door. The resulting TimeoutException is caught below,
      // same as any other location failure -> null.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }
}

final locationServiceProvider = Provider<LocationService>((ref) => GeolocatorLocationService());
