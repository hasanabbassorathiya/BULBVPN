import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if ProcessInfo.processInfo.arguments.contains("--bulb-connect") {
      // shared_preferences stores keys under the "flutter." prefix.
      UserDefaults.standard.set(true, forKey: "flutter.bulb_autoconnect")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}