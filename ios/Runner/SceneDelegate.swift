import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.protectApplicationSnapshot()
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.refreshContentProtection()
  }
}
