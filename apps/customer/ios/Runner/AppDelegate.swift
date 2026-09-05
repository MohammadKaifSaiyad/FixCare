import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Google Maps key from an env var at build time; never committed. Without it
    // the map shows a placeholder (MAPS_ENABLED gate in Dart), so this is safe to
    // leave unset for testing. For a real device build, set the key in the
    // scheme's environment or hardcode locally — never commit it.
    if let mapsKey = ProcessInfo.processInfo.environment["MAPS_API_KEY"], !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
