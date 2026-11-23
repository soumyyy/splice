import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and Dynamic Island while the band streams heart rate.
struct SpliceActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var bpm: Int?
    var zone: Int
    var connected: Bool
  }

  var maxHeartRate: Int
}

enum ZonePalette {
  /// Recovery, Endurance, Tempo, Threshold, Anaerobic.
  static let hex: [UInt32] = [0x8E8E93, 0x3A8DFF, 0x34C759, 0xFF9F0A, 0xFF375F]
  static let names = ["Recovery", "Endurance", "Tempo", "Threshold", "Anaerobic"]
}
