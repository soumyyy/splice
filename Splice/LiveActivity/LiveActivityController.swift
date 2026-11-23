import ActivityKit
import Foundation
import os

/// Keeps one Live Activity alive that mirrors heart rate and workout state.
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

  var isRunning: Bool { activity?.activityState == .active }

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

  /// Pushes a new state, throttled to keep within iOS update budgets.
  /// Heart rate refreshes every 2 s; workout and connection changes go out immediately.
  func update(_ state: SpliceActivityAttributes.ContentState, force: Bool = false) {
    guard let activity, activity.activityState == .active else { return }
    let structural = lastPushed.map {
      $0.connected != state.connected || $0.workoutStartedAt != state.workoutStartedAt || $0.status != state.status
    } ?? true
    let elapsed = Date().timeIntervalSince(lastPushedAt)
    guard force || structural || (state != lastPushed && elapsed >= 2) else { return }
    lastPushed = state
    lastPushedAt = Date()
    Task {
      await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(30)))
    }
  }

  func end(final state: SpliceActivityAttributes.ContentState? = nil) {
    guard let activity else { return }
    self.activity = nil
    Task {
      await activity.end(state.map { .init(state: $0, staleDate: nil) }, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
    }
  }
}
