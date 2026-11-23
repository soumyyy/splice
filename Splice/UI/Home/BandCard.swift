import SwiftUI

/// The band's name, connection state, battery, and the streaming switch.
struct BandCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Card {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(statusColor.opacity(0.18)).frame(width: 44, height: 44)
          Image(systemName: "applewatch.radiowaves.left.and.right")
            .font(.title3)
            .foregroundStyle(statusColor)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(model.band.displayName).font(.headline)
          HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.footnote).foregroundStyle(.secondary)
            if let battery = model.band.batteryPercent {
              Text("·").foregroundStyle(.secondary)
              Label("\(battery)%", systemImage: battery > 20 ? "battery.75percent" : "battery.25percent")
                .font(.footnote)
                .foregroundStyle(battery > 20 ? Color.secondary : Color.orange)
                .labelStyle(.titleAndIcon)
            }
          }
        }
        Spacer()
        Toggle("Stream heart rate", isOn: $model.isStreaming)
          .labelsHidden()
          .tint(.spliceAccent)
      }
      Text(model.isStreaming
           ? "Broadcasting heart rate. Strava and other apps can use your band as a sensor."
           : "Switch on to see your heart rate and broadcast it to Strava.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var statusColor: Color {
    switch model.band.status {
    case .streaming: .green
    case .connected, .connecting: .orange
    case .searching: model.isStreaming ? .orange : .gray
    case .bluetoothOff, .unauthorized: .red
    }
  }

  private var statusText: String {
    switch model.band.status {
    case .bluetoothOff: "Bluetooth is off"
    case .unauthorized: "Bluetooth not allowed"
    case .searching: "Searching…"
    case .connecting: "Connecting…"
    case .connected: model.isStreaming ? "Starting…" : "Connected"
    case .streaming: "Streaming"
    }
  }
}
