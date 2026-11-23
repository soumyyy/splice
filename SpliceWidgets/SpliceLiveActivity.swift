import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SpliceWidgetsBundle: WidgetBundle {
  var body: some Widget {
    SpliceLiveActivity()
  }
}

struct SpliceLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SpliceActivityAttributes.self) { context in
      LockScreenView(state: context.state)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let state = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          BPMLabel(state: state, size: 36)
        }
        DynamicIslandExpandedRegion(.trailing) {
          if let start = state.workoutStartedAt {
            Text(start, style: .timer)
              .font(.title3.weight(.semibold))
              .monospacedDigit()
              .multilineTextAlignment(.trailing)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            ZoneStrip(zone: state.zone, live: state.bpm != nil)
            WorkoutButton(state: state)
          }
        }
      } compactLeading: {
        Image(systemName: "heart.fill").foregroundStyle(state.bpm == nil ? .gray : Color.zone(state.zone))
      } compactTrailing: {
        Text(state.bpm.map(String.init) ?? "--")
          .font(.body.weight(.semibold))
          .monospacedDigit()
          .contentTransition(.numericText())
      } minimal: {
        Text(state.bpm.map(String.init) ?? "--")
          .font(.caption.weight(.bold))
          .foregroundStyle(state.bpm == nil ? .gray : Color.zone(state.zone))
      }
    }
  }
}

private struct LockScreenView: View {
  let state: SpliceActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center) {
        BPMLabel(state: state, size: 44)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          if let start = state.workoutStartedAt {
            Text(state.sportTitle?.uppercased() ?? "WORKOUT")
              .font(.caption2.weight(.bold))
              .foregroundStyle(Color.spliceAccent)
            Text(start, style: .timer)
              .font(.title2.weight(.semibold))
              .monospacedDigit()
              .multilineTextAlignment(.trailing)
            if state.distanceMeters > 0 {
              Text(String(format: "%.2f km", state.distanceMeters / 1000))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } else if let status = state.status {
            Text(status).font(.caption).foregroundStyle(Color.stravaOrange)
          } else if !state.connected {
            Text("Band not streaming").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      ZoneStrip(zone: state.zone, live: state.bpm != nil)
      WorkoutButton(state: state)
    }
    .padding(16)
    .foregroundStyle(.white)
  }
}

private struct BPMLabel: View {
  let state: SpliceActivityAttributes.ContentState
  let size: CGFloat

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Image(systemName: "heart.fill")
        .font(.system(size: size * 0.5))
        .foregroundStyle(state.bpm == nil ? .gray : Color.zone(state.zone))
      Text(state.bpm.map(String.init) ?? "--")
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
      Text("bpm").font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct ZoneStrip: View {
  let zone: Int
  let live: Bool

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<5) { i in
        Capsule()
          .fill(Color.zone(i).opacity(live && i == zone ? 1 : 0.25))
          .frame(height: live && i == zone ? 7 : 4)
      }
    }
  }
}

private struct WorkoutButton: View {
  let state: SpliceActivityAttributes.ContentState

  var body: some View {
    if state.workoutStartedAt != nil {
      Button(intent: EndWorkoutIntent()) {
        Label("Finish & upload to Strava", systemImage: "stop.fill")
          .font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity)
      }
      .tint(.red)
    } else {
      Button(intent: StartWorkoutIntent()) {
        Label("Start \(state.sportTitle ?? "workout")", systemImage: "play.fill")
          .font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity)
      }
      .tint(Color.spliceAccent)
    }
  }
}
