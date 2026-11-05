import Flutter
import UIKit
import Network

private final class RecapNetworkPath: NSObject, FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    monitor?.cancel()
    let active = NWPathMonitor()
    monitor = active
    active.pathUpdateHandler = { [weak self, weak active] path in
      DispatchQueue.main.async {
        guard let active = active, self?.monitor === active else { return }
        events(path.status == .satisfied)
      }
    }
    active.start(queue: DispatchQueue(label: "zhidu.recap.network"))
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    monitor?.cancel()
    monitor = nil
    return nil
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "ZhiduRecapNetworkPath") {
      FlutterEventChannel(name: "zhidu/recap_network_path", binaryMessenger: registrar.messenger())
        .setStreamHandler(RecapNetworkPath())
    }
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
