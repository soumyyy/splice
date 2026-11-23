import Charts
import SpliceCore
import SwiftUI

/// The live heart rate, open on black: the one loud thing on the screen.
struct LiveHeartRate: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let zone = model.isLive ? model.currentZone : nil
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .lastTextBaseline, spacing: 10) {
        Text(model.isLive ? model.bpm.map(String.init) ?? "--" : "--")
          .font(.bpm(150))
          .monospacedDigit()
          .foregroundStyle(zone.map(Color.zone) ?? Color.textSecondary)
          .contentTransition(.numericText())
          .animation(.snappy, value: model.bpm)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        VStack(alignment: .leading, spacing: 2) {
          Text("bpm").font(.title3.weight(.medium)).foregroundStyle(Color.textPrimary)
          Text(zone.map { HeartRateZones.names[$0] } ?? "Waiting")
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.bottom, 18)
      }
      ZoneScale(zones: model.zones, bpm: model.isLive ? model.bpm : nil)
      if model.recent.count > 5 {
        LiveTrace(samples: model.recent, color: zone.map(Color.zone) ?? Color.textSecondary)
          .frame(height: 44)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(model.isLive ? "\(model.bpm ?? 0) beats per minute" : "Waiting for heart rate")
  }
}

/// The last five minutes as a quiet line under the number.
private struct LiveTrace: View {
  let samples: [HeartRateSample]
  let color: Color

  /// Stretch to whatever has been recorded until there are five full minutes.
  private var domainStart: Date {
    max(Date().addingTimeInterval(-300), samples.first?.time ?? Date())
  }

  private var isFullWindow: Bool {
    (samples.first?.time ?? Date()) <= Date().addingTimeInterval(-290)
  }

  var body: some View {
    let values = samples.map(\.bpm)
    let low = Double(values.min() ?? 60) - 3
    let high = Double(values.max() ?? 120) + 3
    Chart(samples, id: \.time) { s in
      LineMark(x: .value("Time", s.time), y: .value("bpm", s.bpm))
        .foregroundStyle(color.opacity(0.8))
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .interpolationMethod(.monotone)
    }
    .chartXScale(domain: domainStart...Date())
    .chartYScale(domain: low...high)
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .overlay(alignment: .bottomTrailing) {
      Text(isFullWindow ? "Last 5 min" : "Live").font(.caption2).foregroundStyle(Color.textSecondary).offset(y: 14)
    }
  }
}
