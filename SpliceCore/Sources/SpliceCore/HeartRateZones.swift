import Foundation

/// Five zones as a percentage of max heart rate, matching Strava's default model.
public struct HeartRateZones: Sendable, Equatable {
  public static let names = ["Recovery", "Endurance", "Tempo", "Threshold", "Anaerobic"]
  public static let lowerBounds: [Double] = [0, 0.6, 0.7, 0.8, 0.9]

  public let maxHeartRate: Int

  public init(maxHeartRate: Int) {
    self.maxHeartRate = max(100, maxHeartRate)
  }

  /// Zone index 0...4 for a bpm value.
  public func zone(for bpm: Int) -> Int {
    let fraction = Double(bpm) / Double(maxHeartRate)
    return Self.lowerBounds.lastIndex { fraction >= $0 } ?? 0
  }

  /// Lower bpm bound of each zone.
  public var thresholds: [Int] {
    Self.lowerBounds.map { Int((Double(maxHeartRate) * $0).rounded()) }
  }
}

public struct HeartRateSample: Sendable, Equatable {
  public let time: Date
  public let bpm: Int

  public init(time: Date, bpm: Int) {
    self.time = time
    self.bpm = bpm
  }
}
