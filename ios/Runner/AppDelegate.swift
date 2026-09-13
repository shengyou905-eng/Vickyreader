import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "ZhiduLocalSyncDiagnostics") {
      let channel = FlutterMethodChannel(
        name: "zhidu/local_sync_diagnostics",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "getAppInfo" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result([
          "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
          "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        ])
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
