import Charts
import SpliceCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var showSettings = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          BandStatusRow()
          StreamToggle()
          if model.isStreaming {
            HeartRateHero()
            StravaHint()
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
      }
      .background(Color.black)
      .navigationTitle("Splice")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
    }
  }
}

struct BandStatusRow: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text).font(.subheadline.weight(.medium))
      Spacer()
      if let battery = model.band.batteryPercent {
        Label("\(battery)%", systemImage: battery > 20 ? "battery.75percent" : "battery.25percent")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var color: Color {
    switch model.band.status {
    case .streaming: .green
    case .connected, .connecting: .orange
    default: .red
    }
  }

  private var text: String {
    switch model.band.status {
    case .bluetoothOff: "Bluetooth is off"
    case .unauthorized: "Allow Bluetooth in Settings"
    case .searching: "Looking for your band…"
    case .connecting: "Connecting to \(model.band.bandName ?? "band")…"
    case .connected: model.isStreaming ? "Connected, starting heart rate…" : "Connected"
    case .streaming: model.band.bandName ?? "Band"
    }
  }
}

struct StreamToggle: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Card {
      Toggle(isOn: $model.isStreaming) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Stream heart rate").font(.headline)
          Text(model.isStreaming
               ? "Your band is broadcasting. Strava can use it as a sensor."
               : "Turn on to see your heart rate and broadcast it to Strava.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .tint(.spliceAccent)
    }
  }
}

struct HeartRateHero: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "heart.fill")
            .font(.title)
            .foregroundStyle(model.currentZone.map(Color.zone) ?? .secondary)
            .symbolEffect(.pulse, isActive: model.isLive)
          Text(model.isLive ? model.bpm.map(String.init) ?? "--" : "--")
            .font(.system(size: 88, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: model.bpm)
          Text("bpm").font(.title3).foregroundStyle(.secondary)
        }
        if let zone = model.currentZone, model.isLive {
          ZoneBar(active: zone)
          Text("Zone \(zone + 1) · \(HeartRateZones.names[zone])")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.zone(zone))
        }
        if model.recent.count > 3 {
          Chart(model.recent, id: \.time) { s in
            LineMark(x: .value("Time", s.time), y: .value("bpm", s.bpm))
              .interpolationMethod(.monotone)
              .foregroundStyle(Color.spliceAccent)
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis(.hidden)
          .frame(height: 90)
        }
      }
    }
  }
}

struct ZoneBar: View {
  let active: Int
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<5) { i in
        Capsule()
          .fill(Color.zone(i).opacity(i == active ? 1 : 0.25))
          .frame(height: i == active ? 10 : 6)
      }
    }
    .animation(.snappy, value: active)
  }
}

struct StravaHint: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 8) {
        Label("Use it in Strava", systemImage: "sensor.tag.radiowaves.forward")
          .font(.headline)
        Text("In Strava, tap Record, then the sensor icon, then Heart Rate, and pick \(model.band.bandName ?? "your WHOOP"). Pair once; Strava reconnects on its own after that.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}
