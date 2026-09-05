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
    // Google Maps key flows: `MAPS_API_KEY` env var (build time) -> the
    // `MAPS_API_KEY` user-defined Xcode build setting (see project.pbxproj,
    // defaults to empty) -> Info.plist's `MapsApiKey` entry (both
    // Info.plist and the debug-only Info-Debug.plist) -> read here via the
    // app bundle at RUNTIME. `ProcessInfo.processInfo.environment` does NOT
    // work for this: env vars are only visible to processes Xcode itself
    // launches (a debug run from the scheme), never to a TestFlight/App
    // Store/ad-hoc install — so a real installed build would silently never
    // get the key. Reading it back out of Info.plist (baked in at build
    // time) is what actually reaches production installs.
    //
    // Without the env var at build time the Info.plist value resolves to
    // empty, so no key is provided. The GoogleMaps SDK ABORTS (SIGABRT) if a
    // GMSMapView is created without a key — so the Dart side must not build
    // GoogleMap unless a key is actually present. Dart gates the map on the
    // `MAPS_API_KEY` dart-define being non-empty (see Env.mapsEnabled), which
    // the runbook sets alongside this native key, so `MAPS_ENABLED=true`
    // without a key renders the placeholder instead of crashing.
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "MapsApiKey") as? String, !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
