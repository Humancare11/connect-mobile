import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Blurs the app's content while it isn't in the foreground (backgrounded,
  // app switcher, an incoming call/notification banner covering it). iOS has
  // no public API to block screenshots/screen recording outright (unlike
  // Android's FLAG_SECURE — see MainActivity.kt), so this closes the other
  // half of that gap: iOS automatically captures a snapshot of whatever is
  // on screen the instant the app resigns active state and shows it in the
  // Recents/App Switcher — this app's screens can carry patient PHI (medical
  // reports, appointment details, chat) almost anywhere, so that snapshot
  // must never contain real content.
  //
  // Hooked via UIApplication-level notifications rather than overriding an
  // AppDelegate/SceneDelegate lifecycle method directly: this app declares a
  // single, non-multi-scene UIApplicationSceneManifest (see Info.plist), so
  // these notifications fire in lockstep with that one scene's lifecycle,
  // without needing to assume which lifecycle methods
  // FlutterAppDelegate/FlutterSceneDelegate already implement internally.
  private var privacyOverlay: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(showPrivacyOverlay),
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(hidePrivacyOverlay),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func showPrivacyOverlay() {
    guard privacyOverlay == nil, let window = currentKeyWindow() else { return }

    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    window.addSubview(blur)
    privacyOverlay = blur
  }

  @objc private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }

  private func currentKeyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
  }
}
