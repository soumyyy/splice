import Foundation
import os
import SpliceCore

/// Saves each workout as one JSON file. Writes are atomic so a crash never leaves a half-written file.
final class WorkoutStore: Sendable {
  let directory: URL
  private let log = Logger(subsystem: "com.soumyamaheshwari.splice", category: "store")

  init(directory: URL? = nil) {
    let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Workouts", isDirectory: true)
    self.directory = base
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
  }

  private func url(for id: UUID) -> URL {
    directory.appendingPathComponent("\(id.uuidString).json")
  }

  func save(_ workout: Workout) {
    do {
      let data = try JSONEncoder.splice.encode(workout)
      try data.write(to: url(for: workout.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch {
      log.error("save failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func loadAll() -> [Workout] {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { $0.pathExtension == "json" }
      .compactMap { try? JSONDecoder.splice.decode(Workout.self, from: Data(contentsOf: $0)) }
      .sorted { $0.startedAt > $1.startedAt }
  }

  func delete(_ id: UUID) {
    try? FileManager.default.removeItem(at: url(for: id))
  }
}

extension JSONEncoder {
  static var splice: JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .secondsSince1970
    return e
  }
}

extension JSONDecoder {
  static var splice: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .secondsSince1970
    return d
  }
}
