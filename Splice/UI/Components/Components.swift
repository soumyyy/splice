import SpliceCore
import SwiftUI

/// A section outlined by a hairline border. No fill: the background stays true black.
struct Panel<Content: View>: View {
  var padding: CGFloat = 16
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) { content }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
  }
}

/// A scale from 50% to 100% of max heart rate, coloured by zone, with a marker at the current bpm.
struct ZoneScale: View {
  let zones: HeartRateZones
  let bpm: Int?

  private let lowerFraction = 0.5

  var body: some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .leading) {
        HStack(spacing: 2) {
          ForEach(0..<5) { i in
            Rectangle()
              .fill(Color.zone(i).opacity(isActive(i) ? 1 : 0.35))
              .frame(width: max(0, segmentWidth(i, total: width) - 2), height: isActive(i) ? 4 : 2)
          }
        }
        .frame(height: 12)
        if let x = markerX(width: width) {
          Capsule()
            .fill(Color.textPrimary)
            .frame(width: 3, height: 14)
            .offset(x: x - 1.5)
            .animation(.snappy, value: bpm)
        }
      }
    }
    .frame(height: 14)
    .accessibilityElement()
    .accessibilityLabel(bpm.map { "Zone \(zones.zone(for: $0) + 1)" } ?? "No heart rate")
  }

  private func isActive(_ zone: Int) -> Bool {
    bpm.map { zones.zone(for: $0) == zone } ?? false
  }

  /// Zone 1 covers 50–60% on this scale; the rest follow Strava's 10% steps.
  private func segmentWidth(_ zone: Int, total: CGFloat) -> CGFloat {
    total * 0.1 / (1 - lowerFraction)
  }

  private func markerX(width: CGFloat) -> CGFloat? {
    guard let bpm else { return nil }
    let fraction = Double(bpm) / Double(zones.maxHeartRate)
    let clamped = min(1, max(lowerFraction, fraction))
    return width * (clamped - lowerFraction) / (1 - lowerFraction)
  }
}

/// Small figure with its label underneath, e.g. "62 / Low".
struct Figure: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.title2.weight(.semibold).width(.condensed))
        .monospacedDigit()
        .foregroundStyle(Color.textPrimary)
      Text(label).font(.footnote).foregroundStyle(Color.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Time in each zone as one segmented line with durations underneath.
struct ZoneDistribution: View {
  let minutes: [Int]

  var body: some View {
    let total = max(1, minutes.reduce(0, +))
    VStack(alignment: .leading, spacing: 10) {
      GeometryReader { geo in
        HStack(spacing: 2) {
          ForEach((0..<5).filter { minutes[$0] > 0 }, id: \.self) { i in
            Rectangle()
              .fill(Color.zone(i))
              .frame(width: max(3, (geo.size.width - 8) * CGFloat(minutes[i]) / CGFloat(total)))
          }
        }
      }
      .frame(height: 4)
      HStack(spacing: 0) {
        ForEach(0..<5) { i in
          VStack(alignment: .leading, spacing: 2) {
            Text(Self.format(minutes[i]))
              .font(.subheadline.weight(.medium))
              .monospacedDigit()
              .foregroundStyle(minutes[i] > 0 ? Color.textPrimary : Color.textSecondary)
            Text("Zone \(i + 1)").font(.caption2).foregroundStyle(Color.zone(i))
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  static func format(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
}
