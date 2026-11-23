import SwiftUI

/// Shown when Splice opens and the band isn't streaming. Connects automatically and closes itself.
struct PairingSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 20) {
      Spacer(minLength: 8)
      ZStack {
        Circle().strokeBorder(Color.hairline, lineWidth: 1).frame(width: 120, height: 120)
        Image(systemName: model.band.status == .streaming ? "checkmark.circle.fill" : "applewatch.radiowaves.left.and.right")
          .font(.system(size: 48))
          .foregroundStyle(model.band.status == .streaming ? Color.zone(2) : Color.textPrimary)
          .symbolEffect(.variableColor.iterative, isActive: model.band.status != .streaming)
          .contentTransition(.symbolEffect(.replace))
      }
      VStack(spacing: 6) {
        Text(title).font(.title2.weight(.bold))
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(Color.textSecondary)
          .multilineTextAlignment(.center)
      }
      if model.band.searchTimedOut {
        VStack(alignment: .leading, spacing: 8) {
          tip("Keep the band on your wrist and close to the phone.")
          tip("Make sure the band isn't charging or connected to another phone.")
          tip("If it still won't connect, turn Bluetooth off and on.")
        }
        .padding()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
        Button("Try again") { model.band.reconnectNow() }
          .buttonStyle(.bordered)
          .tint(Color.textPrimary)
      } else if model.band.status != .streaming {
        ProgressView()
      }
      Spacer()
      Button("Close") { dismiss() }
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .presentationDetents([.medium])
    .presentationBackground(.black)
    .onChange(of: model.band.status) { _, status in
      guard status == .streaming else { return }
      Task {
        try? await Task.sleep(for: .seconds(1))
        dismiss()
      }
    }
  }

  private var title: String {
    switch model.band.status {
    case .streaming: "Connected"
    case .bluetoothOff: "Turn on Bluetooth"
    case .unauthorized: "Allow Bluetooth"
    case .searching: model.band.hasSavedBand ? "Reconnecting to WHOOP 5" : "Pair your WHOOP 5"
    case .connecting, .connected: "Connecting to WHOOP 5"
    }
  }

  private var subtitle: String {
    switch model.band.status {
    case .streaming: "Heart rate is streaming."
    case .bluetoothOff: "Splice needs Bluetooth to reach your band."
    case .unauthorized: "Open Settings › Splice and allow Bluetooth."
    default: "Splice connects to the band automatically. Keep it nearby."
    }
  }

  private func tip(_ text: String) -> some View {
    Label(text, systemImage: "info.circle")
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
