import SwiftUI

/// One bordered row: the band, its state and battery, and the streaming switch.
struct BandRow: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    HStack(spacing: 12) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
        .shadow(color: statusColor.opacity(model.band.status == .streaming ? 0.8 : 0), radius: 4)
      VStack(alignment: .leading, spacing: 1) {
        Text(model.band.displayName).font(.headline).foregroundStyle(Color.textPrimary)
        Text(detail).font(.footnote).foregroundStyle(Color.textSecondary)
      }
      Spacer()
      Toggle("Stream heart rate", isOn: $model.isStreaming)
        .labelsHidden()
        .tint(Color.zone(2))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
    .accessibilityElement(children: .combine)
  }

  private var statusColor: Color {
    switch model.band.status {
    case .streaming: Color.zone(2)
    case .connected, .connecting: Color.zone(3)
    case .searching: model.isStreaming ? Color.zone(3) : Color.textSecondary
    case .bluetoothOff, .unauthorized: Color.zone(4)
    }
  }

  private var detail: String {
    let state: String = switch model.band.status {
    case .bluetoothOff: "Bluetooth is off"
    case .unauthorized: "Bluetooth not allowed"
    case .searching: model.isStreaming ? "Searching" : "Not streaming"
    case .connecting: "Connecting"
    case .connected: model.isStreaming ? "Starting" : "Not streaming"
    case .streaming: "Streaming to Strava"
    }
    guard let battery = model.band.batteryPercent else { return state }
    return "\(state), \(battery)% battery"
  }
}
