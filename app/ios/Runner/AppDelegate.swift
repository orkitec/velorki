import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Mirrored in `lib/features/import_export/data/incoming_file_service.dart`.
  private static let filesChannelName = "velorki/files"
  private static let openedFileMethod = "opened"

  private var filesChannel: FlutterMethodChannel?

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
    flushPendingPaths()
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
