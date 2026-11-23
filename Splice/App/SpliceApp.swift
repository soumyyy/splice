import SwiftUI

@main
struct SpliceApp: App {
  @UIApplicationDelegateAdaptor private var delegate: AppDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = AppModel.shared

  var body: some Scene {
    WindowGroup {
      HomeView()
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(.spliceAccent)
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active: model.appBecameActive()
      case .background: model.appWentToBackground()
      default: break
      }
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Creating the model here means a background relaunch (Bluetooth restore) reconnects the band.
    _ = MainActor.assumeIsolated { AppModel.shared }
    return true
  }
}
