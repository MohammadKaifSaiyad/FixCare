import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Opens the OS settings pages a technician needs when a permission or a
/// device switch blocks a keystone step (camera denied -> no evidence photos;
/// location off/blocked -> no arrival). A seam so widget tests can assert the
/// right page is requested without a platform channel.
abstract class SettingsOpener {
  /// This app's settings page (permissions: camera, location, precise location).
  Future<bool> openAppSettings();

  /// The device's location settings page (the location services switch).
  Future<bool> openLocationSettings();
}

/// Production: geolocator already ships both intents (no extra dependency).
class GeolocatorSettingsOpener implements SettingsOpener {
  const GeolocatorSettingsOpener();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

final settingsOpenerProvider = Provider<SettingsOpener>((ref) => const GeolocatorSettingsOpener());
