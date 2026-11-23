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

  /// Seconds spent in each zone. Each sample holds until the next one, capped at 5 s so gaps don't inflate zones.
  public func timeInZones(_ samples: [HeartRateSample], endedAt: Date?) -> [TimeInterval] {
    var totals = Array(repeating: 0.0, count: 5)
    for (i, sample) in samples.enumerated() {
      let next = i + 1 < samples.count ? samples[i + 1].time : (endedAt ?? sample.time.addingTimeInterval(1))
      let span = min(5, max(0, next.timeIntervalSince(sample.time)))
      totals[zone(for: sample.bpm)] += span
    }
    return totals
  }
}
