import Flutter
import HealthKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Mirrored in `lib/features/import_export/data/incoming_file_service.dart`.
  private static let filesChannelName = "velorki/files"
  private static let openedFileMethod = "opened"

  /// Mirrored in `lib/features/sensors/data/watch_gateway.dart`.
  private static let watchChannelName = "velorki/watch"
  private static let orientationChannelName = "velorki/orientation"
  private static let launchWorkoutMethod = "launchWorkout"
  private static let notifyRideStartedMethod = "notifyRideStarted"
  private static let rideStartedNotificationId = "velorki-watch-ride"
  /// One store for the app: a temporary would be gone before watchOS answers.
  private static let healthStore = HKHealthStore()

  /// Mirrored in `lib/core/files/backup_exclusion.dart`.
  private static let backupChannelName = "app.velorki/backup"

  /// Dart's way of collecting the files that arrived before it listened:
  /// mirrored in `lib/features/import_export/data/incoming_file_service.dart`.
  private static let takePendingMethod = "takePending"

  /// Whether Dart has asked for the pending paths, which is the moment it is
  /// listening for `opened` too. Before that every path waits here: a call
  /// pushed at the engine's start reaches no handler and is simply lost,
  /// which is what a cold start through "Open in Velorki" looked like.
  private var dartListening = false
  private static let excludeFromBackupMethod = "excludeFromBackup"

  private var filesChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  private var watchChannel: FlutterMethodChannel?
  private var orientationChannel: FlutterMethodChannel?
  private var powerSaveChannel: FlutterMethodChannel?

  /// iCloud sync of the library and settings; idle until Dart starts it.
  private var cloudSync: CloudSync?

  /// Mirrored in `lib/core/power/system_power_save.dart`.
  private static let powerSaveChannelName = "velorki/power_save"

  /// Watches the scene's geometry, so a turn from one landscape straight to
  /// the other, which changes no size Flutter sees, still reaches Dart.
  private var geometryObservation: NSKeyValueObservation?

  /// Files that arrived before the Dart side was listening.
  private var pendingPaths: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // CloudKit's silent pushes, which CKSyncEngine turns into fetches while
    // the app runs. No alert, badge or sound is ever asked for.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: AppDelegate.filesChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    filesChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == AppDelegate.takePendingMethod else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.dartListening = true
      let paths = self.pendingPaths
      self.pendingPaths.removeAll()
      result(paths)
    }

    let backup = FlutterMethodChannel(
      name: AppDelegate.backupChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backup.setMethodCallHandler { call, result in
      AppDelegate.handleBackupCall(call, result: result)
    }
    backupChannel = backup

    let watch = FlutterMethodChannel(
      name: AppDelegate.watchChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    watch.setMethodCallHandler { call, result in
      AppDelegate.handleWatchCall(call, result: result)
    }
    watchChannel = watch

    let orientation = FlutterMethodChannel(
      name: AppDelegate.orientationChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    orientation.setMethodCallHandler { [weak self] call, result in
      guard call.method == "side" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.observeGeometry()
      result(AppDelegate.bottomEdgeSide())
    }
    orientationChannel = orientation

    // Low Power Mode: `isOn` answers it, `changed` reports every switch.
    let powerSave = FlutterMethodChannel(
      name: AppDelegate.powerSaveChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    powerSave.setMethodCallHandler { call, result in
      guard call.method == "isOn" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
    powerSaveChannel = powerSave
    cloudSync = CloudSync(messenger: engineBridge.applicationRegistrar.messenger())
    NotificationCenter.default.addObserver(
      forName: Notification.Name.NSProcessInfoPowerStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.powerSaveChannel?.invokeMethod(
        "changed", arguments: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
  }

  /// The scene the app draws in; there is only one.
  private static var windowScene: UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  }

  /// Which side of the screen the phone's bottom edge is on: `left` or
  /// `right` in landscape, `nil` upright. Mirrored in
  /// `lib/app/shell_layout.dart`.
  private static func bottomEdgeSide() -> String? {
    let orientation: UIInterfaceOrientation?
    if #available(iOS 16.0, *) {
      orientation = windowScene?.effectiveGeometry.interfaceOrientation
    } else {
      orientation = windowScene?.interfaceOrientation
    }
    switch orientation {
    // The interface's landscape left has the home button, the bottom edge,
    // on the left.
    case .landscapeLeft: return "left"
    case .landscapeRight: return "right"
    default: return nil
    }
  }

  /// Starts telling Dart about turns, once there is a scene to watch: Dart
  /// asks for the side after its first frame, when the scene is there.
  private func observeGeometry() {
    guard !observingGeometry, let scene = AppDelegate.windowScene else { return }
    observingGeometry = true
    if #available(iOS 16.0, *) {
      geometryObservation = scene.observe(\.effectiveGeometry) { [weak self] _, _ in
        DispatchQueue.main.async { self?.sendSide() }
      }
    } else {
      // Before iOS 16 the scene's geometry cannot be watched; the device
      // turning is the nearest signal, and the interface follows it a
      // moment later.
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      NotificationCenter.default.addObserver(
        forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.sendSide() }
      }
    }
  }

  private var observingGeometry = false

  private func sendSide() {
    orientationChannel?.invokeMethod("sideChanged", arguments: AppDelegate.bottomEdgeSide())
  }

  /// Launches the watch app into a cycling workout, the way HealthKit offers
  /// it: a watch app that is not running cannot be sent a message, so this is
  /// how a ride started on the phone starts the measuring on the wrist. The
  /// watch app picks the configuration up in its `WKApplicationDelegate`.
  ///
  /// Answers true when watchOS took the request; false when there is no
  /// paired watch, the app is not installed there, or HealthKit is unavailable.
  private static func handleWatchCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    if call.method == notifyRideStartedMethod {
      notifyRideStarted(call.arguments as? [String: Any], result: result)
      return
    }
    guard call.method == launchWorkoutMethod else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard HKHealthStore.isHealthDataAvailable() else {
      result(false)
      return
    }
    let configuration = HKWorkoutConfiguration()
    configuration.activityType = .cycling
    configuration.locationType = .outdoor
    healthStore.startWatchApp(with: configuration) { launched, error in
      if let error = error {
        NSLog("velorki: could not launch the watch app: \(error)")
      } else {
        NSLog("velorki: watch app launched for a workout: \(launched)")
      }
      DispatchQueue.main.async { result(launched) }
    }
  }

  /// Tells a phone in a pocket that the watch has started a ride, so a tap
  /// brings the app up: a watch message launches the app in the background
  /// only, and iOS gives a background-launched app no location until it has
  /// been in front. Nothing is posted while the app is on screen, and
  /// nothing without the notification permission, which Settings asks for
  /// when the watch is switched on.
  private static func notifyRideStarted(
    _ arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard UIApplication.shared.applicationState != .active,
      let title = arguments?["title"] as? String,
      let body = arguments?["body"] as? String
    else {
      result(false)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        break
      default:
        DispatchQueue.main.async { result(false) }
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: rideStartedNotificationId,
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        if let error = error {
          NSLog("velorki: could not post the ride notification: \(error)")
        }
        DispatchQueue.main.async { result(error == nil) }
      }
    }
  }

  /// The ride notification has done its job once the app is in front.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: [AppDelegate.rideStartedNotificationId]
    )
  }

  /// Marks a directory `NSURLIsExcludedFromBackupKey`, which Apple's data
  /// storage guidelines require for anything the app can download again —
  /// here `<appSupport>/brouter` with its tiles, gazetteers and profiles.
  ///
  /// Answers true when the flag is set, false when there is nothing at the
  /// path, and a `FlutterError` when iOS refused.
  private static func handleBackupCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == excludeFromBackupMethod else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let path = call.arguments as? String, !path.isEmpty else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "\(excludeFromBackupMethod) expects a non-empty path",
          details: nil
        )
      )
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      result(false)
      return
    }
    var url = URL(fileURLWithPath: path, isDirectory: true)
    do {
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      result(true)
    } catch {
      result(
        FlutterError(
          code: "exclude_failed",
          message: "could not exclude \(path) from the backup",
          details: error.localizedDescription
        )
      )
    }
  }

  /// "Open in Velorki" from Files, Mail, Safari or another app: the app's
  /// own row in the share sheet, as opposed to the Share Extension
  /// (`VelorkiShare`), which goes through receive_sharing_intent.
  ///
  /// iOS hands over a security-scoped URL that is only readable inside a
  /// matching start/stop pair and only until this method returns, so the file
  /// is copied into the app's own tmp directory first and Dart is told about
  /// the copy.
  /// The app runs under UIScene, so the URL arrives at `SceneDelegate` —
  /// `scene(_:openURLContexts:)` while the app runs, the connection options
  /// on a cold start — and never at `application(_:open:options:)`, which is
  /// why the scene delegate hands file URLs here. Custom schemes stay with
  /// the plugins. Returns whether the file was taken.
  @discardableResult
  func openFile(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }

    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard let copy = copyIntoTemporaryDirectory(url) else {
      return false
    }
    send(path: copy.path)
    return true
  }

  /// Copies [url] into `tmp/incoming/`, replacing an earlier copy of the same
  /// name. Returns nil when the copy fails.
  private func copyIntoTemporaryDirectory(_ url: URL) -> URL? {
    let manager = FileManager.default
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("incoming", isDirectory: true)
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(url.lastPathComponent)
      if manager.fileExists(atPath: destination.path) {
        try manager.removeItem(at: destination)
      }
      try manager.copyItem(at: url, to: destination)
      return destination
    } catch {
      NSLog("velorki: could not copy \(url.lastPathComponent): \(error)")
      return nil
    }
  }

  private func send(path: String) {
    guard let channel = filesChannel, dartListening else {
      // A cold start through "Open in Velorki": the engine, or Dart's
      // listener, is not up yet. The path waits until Dart collects it.
      pendingPaths.append(path)
      return
    }
    channel.invokeMethod(AppDelegate.openedFileMethod, arguments: path)
  }
}
