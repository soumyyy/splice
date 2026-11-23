import Foundation
import os
import SpliceCore

/// Keeps the 7-day heart-rate history on disk and publishes a fresh snapshot once a minute.
@MainActor
@Observable
final class HistoryStore {
  /// What the UI reads. Updated when a minute completes, not on every sample, so charts stay cheap.
  private(set) var snapshot = HeartRateHistory()

  @ObservationIgnored private var working = HeartRateHistory()
  @ObservationIgnored private var dirty = false
  @ObservationIgnored private let url: URL
  @ObservationIgnored private let writer = DispatchQueue(label: "com.soumyamaheshwari.splice.history", qos: .utility)
  @ObservationIgnored private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "history")

  init(url: URL? = nil) {
    self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("heart-rate-history.json")
    if let data = try? Data(contentsOf: self.url),
       let saved = try? JSONDecoder().decode(HeartRateHistory.self, from: data) {
      working = saved
    }
    working.prune(now: Date())
    snapshot = working
  }

  func record(bpm: Int, at time: Date) {
    let minutesBefore = working.minutes.count
    working.add(bpm: bpm, at: time)
    dirty = true
    // A new minute started: publish the finished one and save.
    if working.minutes.count != minutesBefore {
      publishAndSave()
    }
  }

  /// Saves now, e.g. when the app goes to the background.
  func flush() {
    guard dirty else { return }
    publishAndSave()
  }

  private func publishAndSave() {
    working.prune(now: Date())
    snapshot = working
    dirty = false
    let copy = working
    let url = url
    writer.async { [log] in
      do {
        let data = try JSONEncoder().encode(copy)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        log.error("history save failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
