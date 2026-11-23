import Charts
import SpliceCore
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
  case hour = "1H"
  case today = "Today"
  case week = "7D"

  var id: String { rawValue }

  /// Start of the range relative to `now`.
  func start(now: Date) -> Date {
    switch self {
    case .hour: now.addingTimeInterval(-3600)
    case .today: Calendar.current.startOfDay(for: now)
    case .week: now.addingTimeInterval(-7 * 86400)
    }
  }

  /// Chart resolution: one point per this many seconds.
  var bucketSize: TimeInterval {
    switch self {
    case .hour: 60
    case .today: 5 * 60
    case .week: 3600
    }
  }

  /// How the summary is described, e.g. "Average today".
  var summaryLabel: String {
    switch self {
    case .hour: "Average, last hour"
    case .today: "Average today"
    case .week: "Average, last 7 days"
    }
  }
}

/// Heart rate over time: the range's average first, then the chart, then time in zones.
struct HistoryPanel: View {
  @Environment(AppModel.self) private var model
  @AppStorage("splice.historyRange.v2") private var range: HistoryRange = .today

  var body: some View {
    let now = Date()
    let start = range.start(now: now)
    let history = model.history.snapshot
    let buckets = history.buckets(from: start, to: now, bucketSize: range.bucketSize)
    let stats = history.stats(from: start, to: now, zones: model.zones)

    Panel(padding: 18) {
      HStack(alignment: .firstTextBaseline) {
        Text("History").font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
        Spacer()
        RangeTabs(selection: $range)
      }

      if let stats {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
          VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
              Text("\(stats.average)")
                .font(.bpm(44))
                .monospacedDigit()
                .foregroundStyle(Color.zone(model.zones.zone(for: stats.average)))
              Text("bpm").font(.subheadline.weight(.medium)).foregroundStyle(Color.textPrimary)
            }
            Text(range.summaryLabel).font(.footnote).foregroundStyle(Color.textSecondary)
          }
          Spacer()
          Figure(value: "\(stats.low)", label: "Low").fixedSize()
          Rectangle().fill(Color.hairline).frame(width: 1, height: 34).padding(.horizontal, 16)
          Figure(value: "\(stats.high)", label: "High").fixedSize()
        }
      }

      if buckets.count < 3 {
        VStack(spacing: 6) {
          Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(Color.textSecondary)
          Text(model.isStreaming ? "Recording" : "Nothing recorded").foregroundStyle(Color.textPrimary)
          Text(model.isStreaming
               ? "The chart fills in over the next few minutes."
               : "Switch on streaming to record your heart rate.")
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 180)
      } else {
        HeartRateChart(buckets: buckets, range: range, start: start, end: now, zones: model.zones)
          .frame(height: 200)
      }

      if let stats, stats.totalMinutes > 0 {
        Rectangle().fill(Color.hairline).frame(height: 1)
        HStack {
          Text("Time in zones").font(.subheadline.weight(.medium)).foregroundStyle(Color.textPrimary)
          Spacer()
          Text(ZoneDistribution.format(stats.totalMinutes) + " recorded")
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
        }
        ZoneDistribution(minutes: stats.minutesInZones)
      }
    }
  }
}

/// Text tabs for the range; the selected one sits in a hairline capsule.
private struct RangeTabs: View {
  @Binding var selection: HistoryRange
  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(HistoryRange.allCases) { r in
        Button {
          selection = r
        } label: {
          Text(r.rawValue)
            .font(.footnote.weight(selection == r ? .semibold : .regular))
            .foregroundStyle(selection == r ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
              if selection == r {
                Capsule().strokeBorder(Color.textSecondary.opacity(0.6), lineWidth: 1)
                  .matchedGeometryEffect(id: "tab", in: namespace)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == r ? .isSelected : [])
      }
    }
    .animation(.snappy(duration: 0.25), value: selection)
  }
}

private struct HeartRateChart: View {
  let buckets: [HeartRateBucket]
  let range: HistoryRange
  let start: Date
  let end: Date
  let zones: HeartRateZones

  var body: some View {
    let low = (Double(buckets.map(\.min).min() ?? 40) - 8).rounded(.down)
    let high = (Double(buckets.map(\.max).max() ?? 180) + 8).rounded(.up)
    let bounds = zones.thresholds.map(Double.init)
    let last = buckets.last!

    Chart {
      // A dashed line at each zone boundary inside the visible range.
      ForEach(1..<5, id: \.self) { i in
        if bounds[i] > low, bounds[i] < high {
          RuleMark(y: .value("Zone \(i + 1)", bounds[i]))
            .foregroundStyle(Color.zone(i).opacity(0.55))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
        }
      }
      ForEach(buckets) { b in
        AreaMark(
          x: .value("Time", b.start),
          yStart: .value("Floor", low),
          yEnd: .value("bpm", b.average),
          series: .value("Segment", "fill-\(b.segment)")
        )
        .foregroundStyle(LinearGradient(
          colors: [Color.textPrimary.opacity(0.22), Color.textPrimary.opacity(0)],
          startPoint: .top, endPoint: .bottom
        ))
        .interpolationMethod(.monotone)

        LineMark(
          x: .value("Time", b.start),
          y: .value("bpm", b.average),
          series: .value("Segment", "line-\(b.segment)")
        )
        .foregroundStyle(Color.textPrimary)
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .interpolationMethod(.monotone)
      }
      // The latest reading.
      PointMark(x: .value("Time", last.start), y: .value("bpm", last.average))
        .symbolSize(70)
        .foregroundStyle(Color.zone(zones.zone(for: Int(last.average.rounded()))))
      PointMark(x: .value("Time", last.start), y: .value("bpm", last.average))
        .symbolSize(220)
        .foregroundStyle(Color.zone(zones.zone(for: Int(last.average.rounded()))).opacity(0.25))
    }
    .chartXScale(domain: start...end)
    .chartYScale(domain: low...high)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisValueLabel(format: xFormat).foregroundStyle(Color.textSecondary)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
        AxisValueLabel().foregroundStyle(Color.textSecondary)
      }
    }
    .chartPlotStyle { plot in
      plot.overlay(alignment: .bottom) {
        Rectangle().fill(Color.hairline).frame(height: 1)
      }
    }
  }

  private var xFormat: Date.FormatStyle {
    switch range {
    case .hour: .dateTime.hour().minute()
    case .today: .dateTime.hour()
    case .week: .dateTime.weekday(.abbreviated)
    }
  }
}
