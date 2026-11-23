import ActivityKit
import Foundation
import os

/// Keeps one Live Activity alive that mirrors the live heart rate.
@MainActor
final class LiveActivityController {
  private var activity: Activity<SpliceActivityAttributes>?
  private var lastPushed: SpliceActivityAttributes.ContentState?
  private var lastPushedAt = Date.distantPast
  private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "live-activity")

  init() {
    // Adopt an activity left over from a previous launch instead of stacking a new one.
    activity = Activity<SpliceActivityAttributes>.activities.first
    for extra in Activity<SpliceActivityAttributes>.activities.dropFirst() {
      Task { await extra.end(nil, dismissalPolicy: .immediate) }
    }
  }

  /// Requests a Live Activity. iOS only allows this while the app is in the foreground.
  func start(maxHeartRate: Int, state: SpliceActivityAttributes.ContentState) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    if let activity, activity.activityState == .active { return }
    do {
      activity = try Activity.request(
        attributes: SpliceActivityAttributes(maxHeartRate: maxHeartRate),
        content: .init(state: state, staleDate: Date().addingTimeInterval(30)),
        pushType: nil
      )
      lastPushed = state
      lastPushedAt = Date()
    } catch {
      log.error("could not start live activity: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Pushes a new state, throttled to one heart-rate update every 2 s; connection changes go out at once.
  func update(_ state: SpliceActivityAttributes.ContentState, force: Bool = false) {
    guard let activity, activity.activityState == .active else { return }
    let connectionChanged = lastPushed?.connected != state.connected
    let elapsed = Date().timeIntervalSince(lastPushedAt)
    guard force || connectionChanged || (state != lastPushed && elapsed >= 2) else { return }
    lastPushed = state
    lastPushedAt = Date()
    Task {
      await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(30)))
    }
  }

  func end() {
    guard let activity else { return }
    self.activity = nil
    lastPushed = nil
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }
}
