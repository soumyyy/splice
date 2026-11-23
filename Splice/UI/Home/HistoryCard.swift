import Charts
import SpliceCore
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
  case live = "Live"
  case hour = "1H"
  case today = "Today"
  case week = "7D"

  var id: String { rawValue }

  /// Start of the range relative to `now`.
  func start(now: Date) -> Date {
    switch self {
    case .live: now.addingTimeInterval(-5 * 60)
    case .hour: now.addingTimeInterval(-3600)
    case .today: Calendar.current.startOfDay(for: now)
    case .week: now.addingTimeInterval(-7 * 86400)
    }
  }

  /// Chart resolution: one point per this many seconds.
  var bucketSize: TimeInterval {
    switch self {
    case .live: 1
    case .hour: 60
    case .today: 5 * 60
    case .week: 3600
    }
  }
}

/// Heart rate over time with low / average / high and time in zones.
struct HistoryCard: View {
  @Environment(AppModel.self) private var model
  @AppStorage("splice.historyRange") private var range: HistoryRange = .today

  var body: some View {
    let now = Date()
    let start = range.start(now: now)
    let buckets = range == .live ? liveBuckets : model.history.snapshot.buckets(from: start, to: now, bucketSize: range.bucketSize)
    let stats = range == .live ? liveStats : model.history.snapshot.stats(from: start, to: now, zones: model.zones)

    Card(title: "History") {
      Picker("Range", selection: $range) {
        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      if buckets.count < 2 {
        ContentUnavailableView {
          Label("No heart rate yet", systemImage: "waveform.path.ecg")
        } description: {
          Text(model.isStreaming ? "History fills in as your band streams." : "Switch on streaming to start recording.")
        }
        .frame(height: 180)
      } else {
        HeartRateChart(buckets: buckets, range: range, start: start, end: now, zones: model.zones)
          .frame(height: 180)
      }

      if let stats {
        HStack {
          StatTile(title: "Low", value: "\(stats.low)")
          StatTile(title: "Average", value: "\(stats.average)")
          StatTile(title: "High", value: "\(stats.high)")
        }
        if range != .live, stats.totalMinutes > 0 {
          Divider().overlay(Color.white.opacity(0.08))
          Text("Time in zones").font(.caption).foregroundStyle(.secondary)
          ZoneDistribution(minutes: stats.minutesInZones)
        }
      }
    }
  }

  /// The last five minutes at full one-second resolution.
  private var liveBuckets: [HeartRateBucket] {
    model.recent.map {
      HeartRateBucket(start: $0.time, min: $0.bpm, max: $0.bpm, average: Double($0.bpm), segment: 0)
    }
  }

  private var liveStats: HeartRateStats? {
    let values = model.recent.map(\.bpm)
    guard let low = values.min(), let high = values.max() else { return nil }
    let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    return HeartRateStats(low: low, average: average, high: high, minutesInZones: [0, 0, 0, 0, 0])
  }
}

private struct HeartRateChart: View {
  let buckets: [HeartRateBucket]
  let range: HistoryRange
  let start: Date
  let end: Date
  let zones: HeartRateZones

  var body: some View {
    Chart {
      ForEach(buckets) { b in
        if range != .live {
          AreaMark(
            x: .value("Time", b.start),
            yStart: .value("Low", b.min),
            yEnd: .value("High", b.max),
            series: .value("Segment", "range-\(b.segment)")
          )
          .foregroundStyle(Color.spliceAccent.opacity(0.18))
          .interpolationMethod(.monotone)
        }
        LineMark(
          x: .value("Time", b.start),
          y: .value("bpm", b.average),
          series: .value("Segment", "avg-\(b.segment)")
        )
        .foregroundStyle(Color.spliceAccent)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
        .interpolationMethod(.monotone)
      }
    }
    .chartXScale(domain: start...end)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
        AxisValueLabel(format: xFormat)
      }
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
        AxisValueLabel()
      }
    }
  }

  private var xFormat: Date.FormatStyle {
    switch range {
    case .live, .hour: .dateTime.hour().minute()
    case .today: .dateTime.hour()
    case .week: .dateTime.weekday(.abbreviated)
    }
  }
}
