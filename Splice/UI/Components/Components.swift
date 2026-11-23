import SpliceCore
import SwiftUI

/// Rounded dark panel used for every section on the home screen.
struct Card<Content: View>: View {
  var title: String?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title {
        Text(title.uppercased())
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.spliceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

/// Five capsules, one per zone, with the active one highlighted.
struct ZoneBar: View {
  let active: Int?

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<5) { i in
        Capsule()
          .fill(Color.zone(i).opacity(i == active ? 1 : 0.22))
          .frame(height: i == active ? 10 : 6)
      }
    }
    .frame(height: 10)
    .animation(.snappy, value: active)
  }
}

/// Small label-over-value figure, e.g. "Avg / 92".
struct StatTile: View {
  let title: String
  let value: String
  var unit: String? = "bpm"

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        if let unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Horizontal bar split by time in each zone, with a legend.
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
        .clipShape(Capsule())
      }
      .frame(height: 10)
      HStack(spacing: 0) {
        ForEach(0..<5) { i in
          VStack(alignment: .leading, spacing: 2) {
            Text("Z\(i + 1)").font(.caption2.weight(.bold)).foregroundStyle(Color.zone(i))
            Text(Self.format(minutes[i])).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  static func format(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
}
