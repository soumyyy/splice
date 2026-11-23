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
          HeartRateHero()
          if model.activeWorkout != nil {
            ActiveWorkoutCard()
          } else {
            StartCard()
          }
          if !model.stravaConnected {
            ConnectStravaCard()
          }
          if let latest = model.workouts.first {
            NavigationLink(value: latest.id) { WorkoutRow(workout: latest) }
              .buttonStyle(.plain)
          }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
      }
      .background(Color.black)
      .navigationTitle("Splice")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink { HistoryView() } label: { Image(systemName: "list.bullet") }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
      }
      .navigationDestination(for: UUID.self) { id in WorkoutDetailView(workoutID: id) }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .task {
        model.requestPermissions()
      }
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
    case .connected: "Connected, starting heart rate…"
    case .streaming: model.band.bandName ?? "Band"
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
            .foregroundStyle(zoneColor)
            .symbolEffect(.pulse, isActive: model.band.status == .streaming)
          Text(model.band.status == .streaming ? model.bpm.map(String.init) ?? "--" : "--")
            .font(.system(size: 88, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: model.bpm)
          Text("bpm").font(.title3).foregroundStyle(.secondary)
        }
        if let zone = model.currentZone, model.band.status == .streaming {
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

  private var zoneColor: Color {
    model.currentZone.map(Color.zone) ?? .secondary
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

struct StartCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Card {
      VStack(alignment: .leading, spacing: 14) {
        Picker("Sport", selection: $model.sport) {
          ForEach(Sport.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Button {
          model.startWorkout()
        } label: {
          Label("Start \(model.sport.title)", systemImage: "play.fill")
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        Text(model.stravaConnected
             ? "Uploads to Strava with heart rate when you finish."
             : "Connect Strava below to upload automatically.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct ActiveWorkoutCard: View {
  @Environment(AppModel.self) private var model
  @State private var confirmDiscard = false

  var body: some View {
    if let workout = model.activeWorkout {
      Card {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text(workout.sport.title.uppercased())
              .font(.caption.weight(.bold))
              .foregroundStyle(Color.spliceAccent)
            Spacer()
            Text(workout.startedAt, style: .timer)
              .font(.title2.weight(.semibold))
              .monospacedDigit()
          }
          HStack {
            Stat(title: "Avg HR", value: workout.averageHeartRate.map { "\($0)" } ?? "--")
            Stat(title: "Max HR", value: workout.maxHeartRate.map { "\($0)" } ?? "--")
            if workout.sport.usesGPS {
              Stat(title: "Distance", value: model.activeDistance.kilometers)
            }
          }
          Button {
            model.endWorkout()
          } label: {
            Label("Finish & Upload", systemImage: "stop.fill")
              .font(.title3.weight(.semibold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          Button("Discard", role: .destructive) { confirmDiscard = true }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
      }
      .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard) {
        Button("Discard", role: .destructive) { model.discardWorkout() }
      }
    }
  }
}

struct Stat: View {
  let title: String
  let value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ConnectStravaCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        Label("Connect Strava", systemImage: "arrow.up.forward.app")
          .font(.headline)
        Text("Finished workouts upload with heart rate and zones, no taps needed.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if model.stravaConfigured {
          Button("Connect") { Task { await model.connectStrava() } }
            .buttonStyle(.borderedProminent)
            .tint(Color.stravaOrange)
        } else {
          Text("This build has no Strava API keys yet.")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
        if let error = model.stravaError {
          Text(error).font(.footnote).foregroundStyle(.red)
        }
      }
    }
  }
}
