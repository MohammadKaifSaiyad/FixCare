import 'package:flutter/foundation.dart';

class Env {
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://10.0.2.2:3000');
  static bool get isDev => !kReleaseMode;
}
