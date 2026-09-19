import 'package:flutter/foundation.dart';

class Env {
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://10.0.2.2:3000');
  static bool get isDev => !kReleaseMode;

  // The Google Maps API key, passed to Dart via --dart-define alongside the
  // native build-time key. Empty when unconfigured.
  static const String mapsApiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');

  // Whether to render the native Google map. This is true ONLY when maps are
  // opted in (MAPS_ENABLED=true) AND a key is actually present (MAPS_API_KEY
  // non-empty). Requiring the key here is what prevents the SIGABRT crash: the
  // GoogleMaps SDK aborts if a map view is built without GMSServices having a
  // key, so MAPS_ENABLED=true on its own must NOT construct GoogleMap. Default
  // false so builds/tests without a key render the placeholder instead.
  static const bool mapsEnabled =
      bool.fromEnvironment('MAPS_ENABLED', defaultValue: false) && mapsApiKey != '';
}
