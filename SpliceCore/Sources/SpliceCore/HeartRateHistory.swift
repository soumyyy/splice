import Foundation

/// One minute of heart rate, kept as min / max / sum so it can be merged into longer buckets exactly.
public struct MinuteSummary: Codable, Sendable, Equatable {
  public let start: Date
  public private(set) var min: Int
  public private(set) var max: Int
  public private(set) var sum: Int
  public private(set) var count: Int

  public var average: Double { Double(sum) / Double(count) }

  init(start: Date, bpm: Int) {
    self.start = start
    min = bpm
    max = bpm
    sum = bpm
    count = 1
  }

  mutating func add(_ bpm: Int) {
    min = Swift.min(min, bpm)
    max = Swift.max(max, bpm)
    sum += bpm
    count += 1
  }
}

/// A span of time summarised for charts: the line is the average, the band is min to max.
public struct HeartRateBucket: Sendable, Equatable, Identifiable {
  public let start: Date
  public let min: Int
  public let max: Int
  public let average: Double
  /// Buckets separated by a gap share no segment, so charts don't draw a line across missing time.
  public let segment: Int

  public var id: Date { start }
}

public struct HeartRateStats: Sendable, Equatable {
  public let low: Int
  public let average: Int
  public let high: Int
  /// Minutes spent in each of the five zones, judged by each minute's average.
  public let minutesInZones: [Int]
  public var totalMinutes: Int { minutesInZones.reduce(0, +) }
}

/// Rolling per-minute heart-rate history. Small enough to keep a week on the phone (~10k entries).
public struct HeartRateHistory: Codable, Sendable, Equatable {
  public static let retention: TimeInterval = 7 * 24 * 3600

  public private(set) var minutes: [MinuteSummary] = []

  public init() {}

  public mutating func add(bpm: Int, at time: Date) {
    let start = Self.minuteStart(time)
    if let last = minutes.last, last.start == start {
      minutes[minutes.count - 1].add(bpm)
    } else if let last = minutes.last, last.start > start {
      return // Out-of-order sample from before the latest minute; ignore it.
    } else {
      minutes.append(MinuteSummary(start: start, bpm: bpm))
    }
  }

  public mutating func prune(now: Date) {
    let cutoff = now.addingTimeInterval(-Self.retention)
    if let firstKept = minutes.firstIndex(where: { $0.start >= cutoff }) {
      minutes.removeFirst(firstKept)
    } else {
      minutes.removeAll()
    }
  }

  /// Minutes whose start falls in `[from, to)`.
  public func minutes(from: Date, to: Date) -> ArraySlice<MinuteSummary> {
    let lower = minutes.partitioningIndex { $0.start >= from }
    let upper = minutes.partitioningIndex { $0.start >= to }
    return minutes[lower..<upper]
  }

  /// Merges minutes into fixed-size buckets aligned to `bucketSize`.
  public func buckets(from: Date, to: Date, bucketSize: TimeInterval) -> [HeartRateBucket] {
    var result: [HeartRateBucket] = []
    var current: (start: Date, min: Int, max: Int, sum: Int, count: Int)?
    var segment = 0

    func flush() {
      guard let c = current else { return }
      if let last = result.last, c.start.timeIntervalSince(last.start) > bucketSize * 2.5 {
        segment += 1
      }
      result.append(HeartRateBucket(start: c.start, min: c.min, max: c.max, average: Double(c.sum) / Double(c.count), segment: segment))
    }

    for minute in minutes(from: from, to: to) {
      let start = Date(timeIntervalSince1970: (minute.start.timeIntervalSince1970 / bucketSize).rounded(.down) * bucketSize)
      if let c = current, c.start == start {
        current = (start, Swift.min(c.min, minute.min), Swift.max(c.max, minute.max), c.sum + minute.sum, c.count + minute.count)
      } else {
        flush()
        current = (start, minute.min, minute.max, minute.sum, minute.count)
      }
    }
    flush()
    return result
  }

  public func stats(from: Date, to: Date, zones: HeartRateZones) -> HeartRateStats? {
    let slice = minutes(from: from, to: to)
    guard !slice.isEmpty else { return nil }
    var inZones = Array(repeating: 0, count: 5)
    var sum = 0
    var count = 0
    for minute in slice {
      inZones[zones.zone(for: Int(minute.average.rounded()))] += 1
      sum += minute.sum
      count += minute.count
    }
    return HeartRateStats(
      low: slice.map(\.min).min()!,
      average: Int((Double(sum) / Double(count)).rounded()),
      high: slice.map(\.max).max()!,
      minutesInZones: inZones
    )
  }

  static func minuteStart(_ date: Date) -> Date {
    Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
  }
}

extension Collection {
  /// First index where `predicate` becomes true, for a collection partitioned by it.
  func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
    var low = startIndex
    var count = distance(from: startIndex, to: endIndex)
    while count > 0 {
      let half = count / 2
      let mid = index(low, offsetBy: half)
      if predicate(self[mid]) {
        count = half
      } else {
        low = index(after: mid)
        count -= half + 1
      }
    }
    return low
  }
}
