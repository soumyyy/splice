import SpliceCore
import SwiftUI

/// Big live heart rate with the current zone.
struct LiveCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "heart.fill")
          .font(.title)
          .foregroundStyle(model.currentZone.map(Color.zone) ?? .secondary)
          .symbolEffect(.pulse, isActive: model.isLive)
        Text(model.isLive ? model.bpm.map(String.init) ?? "--" : "--")
          .font(.system(size: 84, weight: .bold, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(.snappy, value: model.bpm)
        Text("bpm").font(.title3).foregroundStyle(.secondary)
        Spacer()
      }
      ZoneBar(active: model.isLive ? model.currentZone : nil)
      if let zone = model.currentZone, model.isLive {
        Text("Zone \(zone + 1) · \(HeartRateZones.names[zone])")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.zone(zone))
      } else {
        Text("Waiting for heart rate…")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}
