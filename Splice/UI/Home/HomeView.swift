import SwiftUI

/// The only screen: the band and its switch, live heart rate, and history.
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var showSettings = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          BandCard()
          if model.isStreaming {
            LiveCard()
          }
          HistoryCard()
          StravaTip()
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
      }
      .background(Color.black)
      .navigationTitle("Splice")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("Settings")
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .sheet(isPresented: $model.showPairing) { PairingSheet() }
    }
  }
}

/// Collapsible reminder of how to pair the band in Strava.
struct StravaTip: View {
  @Environment(AppModel.self) private var model
  @AppStorage("splice.stravaTipExpanded") private var expanded = true

  var body: some View {
    Card {
      DisclosureGroup(isExpanded: $expanded) {
        VStack(alignment: .leading, spacing: 6) {
          step(1, "In Strava, tap Record.")
          step(2, "Tap the sensor icon, then Heart Rate.")
          step(3, "Pick \(model.band.bandName ?? "your WHOOP"). Strava reconnects by itself after the first time.")
        }
        .padding(.top, 8)
      } label: {
        Label("Use with Strava", systemImage: "sensor.tag.radiowaves.forward")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
      }
    }
  }

  private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(Color.spliceAccent)
      Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
  }
}
