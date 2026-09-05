import 'package:flutter/foundation.dart';

class Env {
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://10.0.2.2:3000');
  static bool get isDev => !kReleaseMode;

  // Whether the Google Maps key is wired (opt-in via --dart-define). Default
  // false so builds/tests without a key never instantiate the native map view.
  static const bool mapsEnabled = bool.fromEnvironment('MAPS_ENABLED', defaultValue: false);
}
