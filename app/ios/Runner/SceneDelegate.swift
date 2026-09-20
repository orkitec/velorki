import Flutter
import UIKit

/// The one scene of the app.
///
/// Files opened with Velorki arrive here, not at the app delegate: a scene
/// based app gets `scene(_:openURLContexts:)` while it runs and the URL
/// contexts of the connection options on a cold start. File URLs go to
/// `AppDelegate.openFile`, which copies the file and tells Dart; every other
/// URL (velorki://, universal links) goes on to Flutter and its plugins.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where context.url.isFileURL {
      appDelegate?.openFile(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let files = URLContexts.filter { $0.url.isFileURL }
    for context in files {
      appDelegate?.openFile(context.url)
    }
    let others = URLContexts.subtracting(files)
    if !others.isEmpty {
      super.scene(scene, openURLContexts: others)
    }
  }

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }
}
