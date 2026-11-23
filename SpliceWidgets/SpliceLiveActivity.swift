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
        .activityBackgroundTint(Color.black)
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
        Image(systemName: "heart.fill").foregroundStyle(state.bpm == nil ? Color(hex: 0x8E8E93) : Color.zone(state.zone))
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
      HStack(alignment: .lastTextBaseline) {
        BPMLabel(state: state, size: 54)
        Spacer()
        Text(state.bpm == nil ? "Band not streaming" : "Zone \(state.zone + 1), \(ZonePalette.names[state.zone])")
          .font(.subheadline)
          .foregroundStyle(Color(hex: 0x8E8E93))
          .padding(.bottom, 6)
      }
      ZoneStrip(zone: state.zone, live: state.bpm != nil)
    }
    .padding(16)
    .foregroundStyle(Color(hex: 0xF5F5F7))
  }
}

private struct BPMLabel: View {
  let state: SpliceActivityAttributes.ContentState
  let size: CGFloat

  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 5) {
      Text(state.bpm.map(String.init) ?? "--")
        .font(.system(size: size, weight: .semibold).width(.compressed))
        .monospacedDigit()
        .foregroundStyle(state.bpm == nil ? Color(hex: 0x8E8E93) : Color.zone(state.zone))
        .contentTransition(.numericText())
      Text("bpm").font(.subheadline.weight(.medium))
    }
  }
}

private struct ZoneStrip: View {
  let zone: Int
  let live: Bool

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<5) { i in
        Rectangle()
          .fill(Color.zone(i).opacity(live && i == zone ? 1 : 0.35))
          .frame(height: live && i == zone ? 4 : 2)
      }
    }
    .frame(height: 4)
  }
}
