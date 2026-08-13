import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var protectsContent = false
  private var privacyOverlay: UIView?
  private var protectedContentLanguage: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let privacyChannel = FlutterMethodChannel(
      name: "com.starforge.staff/privacy",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    privacyChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setProtected" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let arguments = call.arguments as? [String: Any]
      self?.protectsContent = arguments?["enabled"] as? Bool ?? false
      self?.protectedContentLanguage = self?.supportedLanguage(
        arguments?["language"] as? String
      )
      self?.updatePrivacyOverlay()
      result(nil)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    protectApplicationSnapshot()
    super.applicationWillResignActive(application)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    refreshContentProtection()
    super.applicationDidBecomeActive(application)
  }

  func protectApplicationSnapshot() {
    // Always cover staff information while iOS captures the app-switcher
    // snapshot. In-app capture remains blocked only for protected resources.
    showPrivacyOverlay()
  }

  func refreshContentProtection() {
    updatePrivacyOverlay()
  }

  @objc private func screenCaptureChanged() {
    updatePrivacyOverlay()
  }

  private func updatePrivacyOverlay() {
    if protectsContent && UIScreen.main.isCaptured {
      showPrivacyOverlay()
    } else {
      hidePrivacyOverlay()
    }
  }

  private func activeWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func showPrivacyOverlay() {
    guard privacyOverlay == nil, let window = activeWindow() else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.11, alpha: 1)

    let icon = UIImageView(image: UIImage(systemName: "shield.lefthalf.filled"))
    icon.tintColor = UIColor(red: 0.45, green: 0.41, blue: 0.93, alpha: 1)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = privacyOverlayMessage()
    label.textColor = .white
    label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    overlay.addSubview(icon)
    overlay.addSubview(label)
    NSLayoutConstraint.activate([
      icon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -20),
      icon.widthAnchor.constraint(equalToConstant: 42),
      icon.heightAnchor.constraint(equalToConstant: 42),
      label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 14),
      label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 28),
      label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -28),
    ])
    window.addSubview(overlay)
    privacyOverlay = overlay
  }

  private func privacyOverlayMessage() -> String {
    // SharedPreferences stores the explicit in-app language under the
    // `flutter.` prefix. This avoids an English/Russian/Uzbek mismatch when
    // the app language differs from the device language.
    let selectedLanguage = UserDefaults.standard.string(forKey: "flutter.locale")
    let localeIdentifier = protectedContentLanguage
      ?? selectedLanguage
      ?? Locale.preferredLanguages.first
      ?? "uz"
    let language = supportedLanguage(localeIdentifier) ?? "uz"
    switch language {
    case "ru":
      return "Ваше рабочее пространство защищено"
    case "en":
      return "Your workspace is protected"
    default:
      return "Ish joyingiz himoyalangan"
    }
  }

  private func supportedLanguage(_ localeIdentifier: String?) -> String? {
    guard let localeIdentifier else { return nil }
    guard let language = localeIdentifier
      .split(whereSeparator: { $0 == "-" || $0 == "_" })
      .first?
      .lowercased()
    else { return nil }
    return ["uz", "ru", "en"].contains(language) ? language : nil
  }

  private func hidePrivacyOverlay() {
    privacyOverlay?.removeFromSuperview()
    privacyOverlay = nil
  }
}
