import AVFoundation
import Flutter
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Mirrored in `lib/features/import_export/data/incoming_file_service.dart`.
  private static let filesChannelName = "velorki/files"
  private static let openedFileMethod = "opened"

  /// Mirrored in `lib/features/sensors/data/watch_gateway.dart`.
  private static let watchChannelName = "velorki/watch"
  private static let launchWorkoutMethod = "launchWorkout"
  /// One store for the app: a temporary would be gone before watchOS answers.
  private static let healthStore = HKHealthStore()

  /// Mirrored in `lib/core/files/backup_exclusion.dart`.
  private static let backupChannelName = "app.velorki/backup"
  private static let excludeFromBackupMethod = "excludeFromBackup"

  /// Mirrored in `lib/features/navigation/data/navigation_audio.dart`.
  private static let audioChannelName = "app.velorki/audio"
  private static let playLeadInMethod = "playLeadIn"
  private static let deactivateSessionMethod = "deactivateSession"

  private var filesChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  private var audioChannel: FlutterMethodChannel?
  private var watchChannel: FlutterMethodChannel?

  /// The silence played just before a spoken turn cue.
  private let leadIn = LeadInPlayer()

  /// Files that arrived before the Dart side was listening.
  private var pendingPaths: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: AppDelegate.filesChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    filesChannel = channel

    let backup = FlutterMethodChannel(
      name: AppDelegate.backupChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    backup.setMethodCallHandler { call, result in
      AppDelegate.handleBackupCall(call, result: result)
    }
    backupChannel = backup

    let audio = FlutterMethodChannel(
      name: AppDelegate.audioChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    audio.setMethodCallHandler { [weak self] call, result in
      self?.handleAudioCall(call, result: result)
    }
    audioChannel = audio

    let watch = FlutterMethodChannel(
      name: AppDelegate.watchChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    watch.setMethodCallHandler { call, result in
      AppDelegate.handleWatchCall(call, result: result)
    }
    watchChannel = watch

    flushPendingPaths()
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

  /// The audio a guided ride needs and `flutter_tts` does not offer.
  ///
  /// `playLeadIn` plays `assets/audio/silence.wav` and answers when it has
  /// finished; `deactivateSession` hands the audio session back to whatever
  /// was playing before the ride. See
  /// `lib/features/navigation/data/navigation_audio.dart`.
  private func handleAudioCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case AppDelegate.playLeadInMethod:
      leadIn.play(result: result)
    case AppDelegate.deactivateSessionMethod:
      leadIn.stop()
      do {
        try AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "deactivate_failed",
            message: "could not give the audio session back",
            details: error.localizedDescription
          )
        )
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// "Open in Velorki" from Files, Mail, Safari or another app.
  ///
  /// iOS hands over a security-scoped URL that is only readable inside a
  /// matching start/stop pair and only until this method returns, so the file
  /// is copied into the app's own tmp directory first and Dart is told about
  /// the copy. Velorki has no Share Extension yet — see
  /// `lib/features/import_export/README.md` — so this is the whole iOS intake.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL else {
      // Custom schemes (velorki://) belong to app_links and the OAuth plugin.
      return super.application(app, open: url, options: options)
    }

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
    guard let channel = filesChannel else {
      // The engine is not up yet (cold start through "open with"); hold on to
      // the path and deliver it as soon as the channel exists.
      pendingPaths.append(path)
      return
    }
    channel.invokeMethod(AppDelegate.openedFileMethod, arguments: path)
  }

  private func flushPendingPaths() {
    guard let channel = filesChannel, !pendingPaths.isEmpty else { return }
    let paths = pendingPaths
    pendingPaths.removeAll()
    for path in paths {
      channel.invokeMethod(AppDelegate.openedFileMethod, arguments: path)
    }
  }
}

/// Plays the bundled silence that goes before a spoken turn cue.
///
/// A Bluetooth headset lets its A2DP link go idle when nothing is playing and
/// takes about a second to bring it back up; a cue started into that gap
/// arrives scrambled or without its first syllables. The silence wakes the
/// link, so the voice starts into a stream that is already open. It is played
/// per cue rather than looped for the whole ride: a link held open all ride
/// costs the rider battery for nothing.
///
/// It lives here rather than in a file of its own so the Runner target needs
/// no new entry in `project.pbxproj`; the file itself is a Flutter asset, so
/// it needs none either.
final class LeadInPlayer: NSObject, AVAudioPlayerDelegate {
  /// Where the silence lives, as `pubspec.yaml` declares it.
  private static let asset = "assets/audio/silence.wav"

  private var player: AVAudioPlayer?

  /// The Dart call waiting for the silence to finish, if there is one.
  private var pending: FlutterResult?

  /// Plays the silence and answers [result] when it has finished.
  ///
  /// Answers straight away when there is nothing to play, so a cue is never
  /// held up by a missing or unreadable file. Dart caps the wait as well.
  func play(result: @escaping FlutterResult) {
    // A cue that comes in while the last lead-in is still playing takes the
    // player over; the call it interrupts is answered rather than left
    // hanging.
    answerPending()
    guard let player = player ?? load() else {
      result(nil)
      return
    }
    self.player = player
    // The session is the one `flutter_tts` set up (playback, voicePrompt).
    // Activating it again is what brings it back after an interruption — a
    // phone call — has taken it away.
    try? AVAudioSession.sharedInstance().setActive(true)
    player.currentTime = 0
    pending = result
    if !player.play() {
      pending = nil
      result(nil)
    }
  }

  /// Stops the silence, answering whatever was waiting on it.
  func stop() {
    player?.stop()
    answerPending()
  }

  private func load() -> AVAudioPlayer? {
    let key = FlutterDartProject.lookupKey(forAsset: LeadInPlayer.asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      NSLog("velorki: the silent lead-in is not in the bundle")
      return nil
    }
    do {
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player.delegate = self
      // Low rather than zero: a player at zero volume is not guaranteed to
      // render anything, and rendering is the whole point of this file.
      player.volume = 0.01
      player.prepareToPlay()
      return player
    } catch {
      NSLog("velorki: could not open the silent lead-in: \(error)")
      return nil
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    answerPending()
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    answerPending()
  }

  private func answerPending() {
    guard let waiting = pending else { return }
    pending = nil
    waiting(nil)
  }
}
