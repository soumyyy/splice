import ActivityKit
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
          if state.bpm != nil {
            Text(ZonePalette.names[state.zone])
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.zone(state.zone))
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          ZoneStrip(zone: state.zone, live: state.bpm != nil)
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
        if state.bpm != nil {
          Text("Zone \(state.zone + 1) · \(ZonePalette.names[state.zone])")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.zone(state.zone))
        } else {
          Text("Band not streaming").font(.caption).foregroundStyle(.secondary)
        }
      }
      ZoneStrip(zone: state.zone, live: state.bpm != nil)
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
