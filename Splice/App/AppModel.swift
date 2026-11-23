import Foundation
import SpliceCore

@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  let band = BandClient()
  let history = HistoryStore()
  private(set) var bpm: Int?
  private(set) var recent: [HeartRateSample] = []

  var maxHeartRate: Int {
    didSet {
      UserDefaults.standard.set(maxHeartRate, forKey: "splice.maxHeartRate")
      refreshLiveActivity(force: true)
    }
  }

  /// The single switch in the app: stream heart rate (and broadcast it to Strava) or not.
  var isStreaming: Bool {
    get { band.wantsStream }
    set {
      band.wantsStream = newValue
      if newValue {
        ensureLiveActivity()
      } else {
        bpm = nil
        recent = []
        liveActivity.end()
      }
    }
  }

  var zones: HeartRateZones { HeartRateZones(maxHeartRate: maxHeartRate) }
  var currentZone: Int? { bpm.map { zones.zone(for: $0) } }
  var isLive: Bool { band.status == .streaming && bpm != nil }

  @ObservationIgnored private let liveActivity = LiveActivityController()
  @ObservationIgnored private var ticker: Timer?

  private init() {
    maxHeartRate = UserDefaults.standard.object(forKey: "splice.maxHeartRate") as? Int ?? 190
    band.onReading = { [weak self] reading, receivedAt in self?.handle(reading.bpm, at: receivedAt) }

    // Catches connection changes between readings so the Lock Screen never shows a stale number.
    ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
      MainActor.assumeIsolated { AppModel.shared.refreshLiveActivity() }
    }
  }

  private func handle(_ value: Int, at time: Date) {
    bpm = value
    history.record(bpm: value, at: time)
    recent.append(HeartRateSample(time: time, bpm: value))
    recent.removeAll { time.timeIntervalSince($0.time) > 300 }
    refreshLiveActivity()
  }

  /// Starts the Live Activity if streaming. Must be called while the app is in the foreground.
  func ensureLiveActivity() {
    guard isStreaming else { return }
    liveActivity.start(maxHeartRate: maxHeartRate, state: liveState())
  }

  func appWentToBackground() {
    history.flush()
  }

  /// Shown when the app opens and the band isn't streaming yet.
  var showPairing = false
  @ObservationIgnored private var pairingCheck: Task<Void, Never>?

  func appBecameActive() {
    band.reconnectNow()
    ensureLiveActivity()
    refreshLiveActivity(force: true)
    // Give a normal reconnect a moment before prompting, so the sheet doesn't flash.
    pairingCheck?.cancel()
    pairingCheck = Task {
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled, isStreaming, band.status != .streaming else { return }
      showPairing = true
    }
  }

  private func refreshLiveActivity(force: Bool = false) {
    liveActivity.update(liveState(), force: force)
  }

  private func liveState() -> SpliceActivityAttributes.ContentState {
    .init(bpm: isLive ? bpm : nil, zone: currentZone ?? 0, connected: isLive)
  }
}
