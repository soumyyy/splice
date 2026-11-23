import ActivityKit
import AppIntents
import Foundation

/// Live Activity shown on the Lock Screen and Dynamic Island while the band streams heart rate.
struct SpliceActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var bpm: Int?
    var zone: Int
    var connected: Bool
    var workoutStartedAt: Date?
    var sportTitle: String?
    var distanceMeters: Double
    var averageBPM: Int?
    var status: String?
  }

  var maxHeartRate: Int
}

/// Actions triggered from Live Activity buttons. They run inside the app process.
enum SpliceIntentAction: Sendable {
  case startWorkout
  case endWorkout
}

@MainActor
enum SpliceIntentRouter {
  static var handler: ((SpliceIntentAction) async -> Void)?
}

struct StartWorkoutIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Start Workout"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await SpliceIntentRouter.handler?(.startWorkout)
    return .result()
  }
}

struct EndWorkoutIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "End Workout"
  static let isDiscoverable = false

  func perform() async throws -> some IntentResult {
    await SpliceIntentRouter.handler?(.endWorkout)
    return .result()
  }
}

enum ZonePalette {
  /// Recovery, Endurance, Tempo, Threshold, Anaerobic.
  static let hex: [UInt32] = [0x8E8E93, 0x3A8DFF, 0x34C759, 0xFF9F0A, 0xFF375F]
  static let names = ["Recovery", "Endurance", "Tempo", "Threshold", "Anaerobic"]
}
