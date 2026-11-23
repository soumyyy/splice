import Charts
import SpliceCore
import SwiftUI

struct HistoryView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      ForEach(model.workouts) { workout in
        NavigationLink(value: workout.id) { WorkoutRow(workout: workout) }
          .listRowBackground(Color.spliceCard)
      }
      .onDelete { offsets in offsets.map { model.workouts[$0] }.forEach(model.delete) }
    }
    .scrollContentBackground(.hidden)
    .background(Color.black)
    .overlay {
      if model.workouts.isEmpty {
        ContentUnavailableView("No workouts yet", systemImage: "heart.text.square", description: Text("Finished workouts appear here."))
      }
    }
    .navigationTitle("Workouts")
  }
}

struct WorkoutRow: View {
  let workout: Workout

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(workout.sport.title) · \(workout.startedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.subheadline.weight(.semibold))
        Text(summary).font(.footnote).foregroundStyle(.secondary)
      }
      Spacer()
      UploadBadge(state: workout.upload)
    }
    .padding(.vertical, 4)
  }

  private var summary: String {
    var parts = [WorkoutSummary.duration(workout.duration)]
    if let avg = workout.averageHeartRate { parts.append("avg \(avg) bpm") }
    if workout.distanceMeters > 50 { parts.append(workout.distanceMeters.kilometers) }
    return parts.joined(separator: " · ")
  }
}

struct UploadBadge: View {
  let state: UploadState

  var body: some View {
    switch state {
    case .uploaded:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.stravaOrange)
    case .uploading:
      ProgressView()
    case .notUploaded:
      Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }
  }
}

struct WorkoutDetailView: View {
  @Environment(AppModel.self) private var model
  let workoutID: UUID

  var body: some View {
    if let workout = model.workouts.first(where: { $0.id == workoutID }) {
      ScrollView {
        VStack(spacing: 16) {
          Card {
            HStack {
              Stat(title: "Time", value: WorkoutSummary.duration(workout.duration))
              Stat(title: "Avg HR", value: workout.averageHeartRate.map { "\($0)" } ?? "--")
              Stat(title: "Max HR", value: workout.maxHeartRate.map { "\($0)" } ?? "--")
            }
          }
          if !workout.heartRate.isEmpty {
            Card {
              VStack(alignment: .leading) {
                Text("Heart rate").font(.headline)
                Chart(workout.heartRate, id: \.time) { s in
                  LineMark(x: .value("Time", s.time), y: .value("bpm", s.bpm))
                    .foregroundStyle(Color.spliceAccent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
              }
            }
            Card { ZoneBreakdown(workout: workout) }
          }
          Card { UploadSection(workout: workout) }
        }
        .padding()
      }
      .background(Color.black)
      .navigationTitle(workout.sport.title)
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

struct ZoneBreakdown: View {
  let workout: Workout

  var body: some View {
    let times = workout.timeInZones
    let total = max(1, times.reduce(0, +))
    let bounds = workout.zones.thresholds
    VStack(alignment: .leading, spacing: 10) {
      Text("Zones").font(.headline)
      ForEach((0..<5).reversed(), id: \.self) { i in
        HStack(spacing: 10) {
          Text("Z\(i + 1)").font(.caption.weight(.bold)).frame(width: 24, alignment: .leading)
          GeometryReader { geo in
            Capsule().fill(Color.zone(i))
              .frame(width: max(4, geo.size.width * times[i] / total))
          }
          .frame(height: 10)
          Text(WorkoutSummary.duration(times[i])).font(.caption).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .help("\(HeartRateZones.names[i]) from \(bounds[i]) bpm")
      }
    }
  }
}

struct UploadSection: View {
  @Environment(AppModel.self) private var model
  let workout: Workout

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Strava").font(.headline)
      switch workout.upload {
      case .uploaded(let id):
        Button("Open on Strava") { StravaLink.open(activityID: id) }
          .buttonStyle(.borderedProminent)
          .tint(Color.stravaOrange)
      case .uploading:
        Label("Uploading…", systemImage: "arrow.up.circle")
      case .notUploaded:
        Text(model.stravaConnected ? "Waiting to upload. Splice retries automatically." : "Connect Strava to upload.")
          .foregroundStyle(.secondary)
      case .failed(let message):
        Text(message).font(.footnote).foregroundStyle(.orange)
        Button("Try again") { model.retryUpload(workout) }
          .buttonStyle(.bordered)
      }
    }
  }
}
