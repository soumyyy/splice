import SwiftUI
import UserNotifications

@main
struct SpliceApp: App {
  @UIApplicationDelegateAdaptor private var delegate: AppDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = AppModel.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(.spliceAccent)
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.appBecameActive() }
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    // Creating the model here means a background relaunch (Bluetooth restore) reconnects the band.
    _ = MainActor.assumeIsolated { AppModel.shared }
    return true
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard let id = response.notification.request.content.userInfo["stravaActivityID"] as? Int64 else { return }
    await MainActor.run { StravaLink.open(activityID: id) }
  }
}

enum StravaLink {
  /// The https link opens the Strava app when it's installed.
  @MainActor static func open(activityID: Int64) {
    if let url = URL(string: "https://www.strava.com/activities/\(activityID)") {
      UIApplication.shared.open(url)
    }
  }
}
