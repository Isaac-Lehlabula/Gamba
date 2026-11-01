import Flutter
import UIKit

#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var blocker: BlockerChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReclaimBlocker") {
      blocker = BlockerChannel(messenger: registrar.messenger())
    }
  }
}

// MARK: - Gambling-site blocking (Screen Time API)
//
// UNVERIFIED: written without access to a Mac, Xcode or a device; see docs/BLOCKING.md.
// Before this can be used:
//   1. Add the Family Controls capability in Xcode (it uses Runner/Runner.entitlements).
//   2. Request Apple's Family Controls *distribution* entitlement for the bundle id.
//   3. Build and test on a real device, then build the Flutter app with
//      --dart-define=RECLAIM_IOS_SCREEN_TIME=true so the Dart side starts using this channel.
// Mirrors the Android channel in android/app/src/main/kotlin/.../blocker/BlockerChannel.kt.

final class BlockerChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "za.reclaim/blocker", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    guard #available(iOS 16.0, *) else { return result(call.method == "isSupported" ? false : nil) }
    let blocker = ScreenTimeBlocker.shared
    switch call.method {
    case "isSupported":
      result(true)
    case "isRunning":
      result(blocker.isEnabled)
    case "requestPermission":
      Task { result(await blocker.requestAuthorization()) }
    case "start":
      result(blocker.start())
    case "stop":
      blocker.stop()
      result(nil)
    case "setBlocklist":
      let domains = (call.arguments as? [String: Any])?["domains"] as? [String] ?? []
      blocker.setBlocklist(domains)
      result(nil)
    case "blockedLog":
      // iOS doesn't tell apps which sites were blocked.
      result([String]())
    case "clearBlockedLog", "openVpnSettings":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
    #else
    result(call.method == "isSupported" ? false : FlutterMethodNotImplemented)
    #endif
  }
}

#if canImport(FamilyControls) && canImport(ManagedSettings)
/// Blocks web domains in Safari and every other WebKit browser via ManagedSettings, using
/// `.individual` Family Controls authorization (the device owner's own consent).
@available(iOS 16.0, *)
final class ScreenTimeBlocker {
  static let shared = ScreenTimeBlocker()

  private let store = ManagedSettingsStore()
  private let defaults = UserDefaults.standard
  private let enabledKey = "reclaim.blocker.enabled"
  private let domainsKey = "reclaim.blocker.domains"

  var isEnabled: Bool { defaults.bool(forKey: enabledKey) && AuthorizationCenter.shared.authorizationStatus == .approved }

  func requestAuthorization() async -> Bool {
    if AuthorizationCenter.shared.authorizationStatus == .approved { return true }
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      return AuthorizationCenter.shared.authorizationStatus == .approved
    } catch {
      return false
    }
  }

  func setBlocklist(_ domains: [String]) {
    defaults.set(domains, forKey: domainsKey)
    if defaults.bool(forKey: enabledKey) { apply() }
  }

  func start() -> Bool {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else { return false }
    defaults.set(true, forKey: enabledKey)
    apply()
    return true
  }

  func stop() {
    defaults.set(false, forKey: enabledKey)
    store.webContent.blockedByFilter = nil
  }

  private func apply() {
    // Apple caps how many domains one policy may list (believed to be 50; verify on a device).
    // Beyond the cap this applies the first 50 alphabetically, so a longer list needs a
    // priority order from the backend before shipping.
    let domains = (defaults.stringArray(forKey: domainsKey) ?? []).prefix(50)
    store.webContent.blockedByFilter = .specific(Set(domains.map { WebDomain(domain: $0) }))
  }
}
#endif
