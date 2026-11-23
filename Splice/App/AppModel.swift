import AuthenticationServices
import Foundation
import Network
import os
import SpliceCore
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  // MARK: State

  let band = BandClient()
  private(set) var bpm: Int?
  private(set) var recent: [HeartRateSample] = []
  private(set) var activeWorkout: Workout?
  /// Running GPS distance of the active workout, kept incrementally.
  private(set) var activeDistance: Double = 0
  private(set) var workouts: [Workout] = []
  private(set) var stravaAthlete: String?
  private(set) var stravaError: String?

  var maxHeartRate: Int {
    didSet { defaults.set(maxHeartRate, forKey: Keys.maxHeartRate); refreshLiveActivity(force: true) }
  }
  var sport: Sport {
    didSet { defaults.set(sport.rawValue, forKey: Keys.sport) }
  }

  var zones: HeartRateZones { HeartRateZones(maxHeartRate: maxHeartRate) }
  var currentZone: Int? { bpm.map { zones.zone(for: $0) } }
  var stravaConnected: Bool { auth.tokens != nil }
  var stravaConfigured: Bool { auth.hasAppCredentials }

  // MARK: Dependencies

  @ObservationIgnored private let defaults = UserDefaults.standard
  @ObservationIgnored private let store = WorkoutStore()
  @ObservationIgnored private let location = LocationRecorder()
  @ObservationIgnored private let liveActivity = LiveActivityController()
  @ObservationIgnored private let auth = StravaAuth()
  @ObservationIgnored private lazy var uploader = StravaUploader(auth: auth)
  @ObservationIgnored private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "app")
  @ObservationIgnored private var lastCheckpoint = Date.distantPast
  @ObservationIgnored private var uploading = false
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  @ObservationIgnored private let network = NWPathMonitor()
  @ObservationIgnored private var lastAccurateLocation: LocationSample?
  @ObservationIgnored private var ticker: Timer?

  private enum Keys {
    static let maxHeartRate = "splice.maxHeartRate"
    static let sport = "splice.sport"
  }

  private init() {
    maxHeartRate = defaults.object(forKey: Keys.maxHeartRate) as? Int ?? 190
    sport = Sport(rawValue: defaults.string(forKey: Keys.sport) ?? "") ?? .run
    stravaAthlete = auth.tokens?.athleteName

    band.onReading = { [weak self] reading, receivedAt in self?.handle(reading, at: receivedAt) }
    location.onLocation = { [weak self] sample in self?.addLocation(sample) }
    SpliceIntentRouter.handler = { [weak self] action in
      switch action {
      case .startWorkout: self?.startWorkout()
      case .endWorkout: self?.endWorkout()
      }
    }

    workouts = store.loadAll()
    recoverUnfinishedWorkout()

    network.pathUpdateHandler = { path in
      guard path.status == .satisfied else { return }
      Task { @MainActor in AppModel.shared.processUploads() }
    }
    network.start(queue: .main)

    // Catches connection changes between readings so the Lock Screen never shows a stale number.
    ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
      MainActor.assumeIsolated { AppModel.shared.refreshLiveActivity() }
    }
  }

  private func addLocation(_ sample: LocationSample) {
    guard activeWorkout != nil else { return }
    activeWorkout?.locations.append(sample)
    guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= Geo.maxAccuracy else { return }
    if let last = lastAccurateLocation { activeDistance += Geo.distance(last, sample) }
    lastAccurateLocation = sample
  }

  // MARK: Heart rate

  private func handle(_ reading: HeartRateReading, at time: Date) {
    bpm = reading.bpm
    let sample = HeartRateSample(time: time, bpm: reading.bpm)
    recent.append(sample)
    if let first = recent.first, time.timeIntervalSince(first.time) > 300 {
      recent.removeAll { time.timeIntervalSince($0.time) > 300 }
    }
    if activeWorkout != nil {
      activeWorkout?.heartRate.append(sample)
      if time.timeIntervalSince(lastCheckpoint) >= 15 { checkpoint() }
    }
    refreshLiveActivity()
  }

  // MARK: Workouts

  func startWorkout() {
    guard activeWorkout == nil else { return }
    activeWorkout = Workout(sport: sport, startedAt: Date(), maxHeartRateSetting: maxHeartRate)
    activeDistance = 0
    lastAccurateLocation = nil
    if sport.usesGPS { location.start() }
    checkpoint()
    ensureLiveActivity()
    refreshLiveActivity(force: true)
  }

  /// Ends the workout, saves it, and uploads it to Strava without any further input.
  func endWorkout() {
    guard var workout = activeWorkout else { return }
    location.stop()
    workout.endedAt = Date()
    activeWorkout = nil
    if workout.heartRate.isEmpty && workout.locations.isEmpty {
      store.delete(workout.id)
      refreshLiveActivity(force: true)
      return
    }
    store.save(workout)
    workouts.insert(workout, at: 0)
    refreshLiveActivity(force: true)
    processUploads()
  }

  func discardWorkout() {
    guard let workout = activeWorkout else { return }
    location.stop()
    activeWorkout = nil
    store.delete(workout.id)
    refreshLiveActivity(force: true)
  }

  func delete(_ workout: Workout) {
    store.delete(workout.id)
    workouts.removeAll { $0.id == workout.id }
  }

  private func checkpoint() {
    guard let activeWorkout else { return }
    lastCheckpoint = Date()
    store.save(activeWorkout)
  }

  /// After a crash or a relaunch, resume a workout that was still going, or close one that went quiet.
  private func recoverUnfinishedWorkout() {
    guard let unfinished = workouts.first(where: { $0.endedAt == nil }) else { return }
    workouts.removeAll { $0.id == unfinished.id }
    let lastActivity = [unfinished.heartRate.last?.time, unfinished.locations.last?.time, unfinished.startedAt]
      .compactMap { $0 }.max()!
    if Date().timeIntervalSince(lastActivity) < 10 * 60 {
      activeWorkout = unfinished
      activeDistance = unfinished.distanceMeters
      lastAccurateLocation = unfinished.locations.last { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= Geo.maxAccuracy }
      if unfinished.sport.usesGPS { location.start() }
      log.info("resumed workout after relaunch")
    } else {
      var closed = unfinished
      closed.endedAt = lastActivity
      store.save(closed)
      workouts.insert(closed, at: 0)
      log.info("closed workout left open by a crash")
    }
  }

  // MARK: Strava

  func connectStrava() async {
    do {
      try await auth.connect()
      stravaAthlete = auth.tokens?.athleteName
      stravaError = nil
      processUploads()
    } catch {
      let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
      stravaError = cancelled ? nil : error.localizedDescription
    }
  }

  func disconnectStrava() {
    auth.disconnect()
    stravaAthlete = nil
  }

  func retryUpload(_ workout: Workout) {
    update(workout.id) { $0.upload = .notUploaded }
    processUploads()
  }

  /// Uploads every finished workout that isn't on Strava yet, oldest first.
  func processUploads() {
    guard !uploading, stravaConnected else { return }
    let pending = workouts.filter {
      guard $0.endedAt != nil else { return false }
      if case .uploaded = $0.upload { return false }
      return true
    }.reversed()
    guard let next = pending.first else { return }

    uploading = true
    update(next.id) { $0.upload = .uploading }
    let background = UIApplication.shared.beginBackgroundTask(withName: "strava-upload")
    Task {
      defer {
        uploading = false
        UIApplication.shared.endBackgroundTask(background)
      }
      do {
        let activityID = try await uploader.upload(next)
        update(next.id) { $0.upload = .uploaded(activityID: activityID) }
        debugTrace("uploaded to strava activity \(activityID)")
        notify(title: "On Strava", body: uploadedMessage(next), activityID: activityID)
        refreshLiveActivity(force: true, status: "Uploaded to Strava")
        processUploads()
      } catch let error as StravaError where error.isTransient {
        update(next.id) { $0.upload = .notUploaded }
        scheduleRetry()
      } catch let error as URLError {
        log.info("upload offline: \(error.localizedDescription, privacy: .public)")
        update(next.id) { $0.upload = .notUploaded }
        scheduleRetry()
      } catch {
        update(next.id) { $0.upload = .failed(message: error.localizedDescription) }
        debugTrace("upload failed: \(error.localizedDescription)")
        notify(title: "Strava upload failed", body: error.localizedDescription, activityID: nil)
      }
    }
  }

  private func scheduleRetry() {
    retryTask?.cancel()
    retryTask = Task {
      try? await Task.sleep(for: .seconds(60))
      guard !Task.isCancelled else { return }
      processUploads()
    }
  }

  private func update(_ id: UUID, _ change: (inout Workout) -> Void) {
    guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
    change(&workouts[index])
    store.save(workouts[index])
  }

  private func uploadedMessage(_ w: Workout) -> String {
    var parts = [w.sport.title, WorkoutSummary.duration(w.duration)]
    if let avg = w.averageHeartRate { parts.append("avg \(avg) bpm") }
    return parts.joined(separator: " · ")
  }

  // MARK: Notifications

  /// Asked once on first launch so later workouts, including Lock Screen starts, need no prompts.
  func requestPermissions() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    location.requestPermission()
  }

  private func notify(title: String, body: String, activityID: Int64?) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if let activityID { content.userInfo = ["stravaActivityID": activityID] }
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
  }

  // MARK: Live Activity

  /// Starts the Live Activity if possible. Must be called while the app is in the foreground.
  func ensureLiveActivity() {
    liveActivity.start(maxHeartRate: maxHeartRate, state: liveState())
  }

  private func refreshLiveActivity(force: Bool = false, status: String? = nil) {
    liveActivity.update(liveState(status: status), force: force)
  }

  private func liveState(status: String? = nil) -> SpliceActivityAttributes.ContentState {
    let streaming = band.status == .streaming
    return .init(
      bpm: streaming ? bpm : nil,
      zone: currentZone ?? 0,
      connected: streaming,
      workoutStartedAt: activeWorkout?.startedAt,
      sportTitle: activeWorkout?.sport.title ?? sport.title,
      distanceMeters: activeWorkout == nil ? 0 : activeDistance,
      averageBPM: activeWorkout?.averageHeartRate,
      status: status
    )
  }

  func appBecameActive() {
    ensureLiveActivity()
    refreshLiveActivity(force: true)
    processUploads()
  }
}
