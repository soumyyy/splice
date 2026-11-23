import SwiftUI

/// The only screen: the band and its switch, live heart rate, and history.
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var showSettings = false
  @State private var showStravaHelp = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          BandRow()
          if model.isStreaming {
            LiveHeartRate()
          }
          HistoryPanel()
          VStack(spacing: 0) {
            PlainRow(title: "Use your band in Strava") { showStravaHelp = true }
            PlainRow(title: "Settings") { showSettings = true }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 32)
      }
      .scrollIndicators(.hidden)
      .background(Color.black)
      .toolbar(.hidden, for: .navigationBar)
      // Keep scrolled content from showing behind the clock and battery.
      .overlay(alignment: .top) {
        Color.black
          .ignoresSafeArea(edges: .top)
          .frame(height: 0)
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .sheet(isPresented: $model.showPairing) { PairingSheet() }
      .sheet(isPresented: $showStravaHelp) { StravaHelpSheet() }
    }
  }
}

/// A full-width line with a hairline above it, used for the links at the bottom.
private struct PlainRow: View {
  let title: String
  let action: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Rectangle().fill(Color.hairline).frame(height: 1)
      Button(action: action) {
        HStack {
          Text(title).foregroundStyle(Color.textPrimary)
          Spacer()
          Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }
}

private struct StravaHelpSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Use your band in Strava").font(.title3.weight(.semibold))
      step(1, "Keep streaming switched on in Splice.")
      step(2, "In Strava, tap Record, then the sensor icon, then Heart Rate.")
      step(3, "Pick \(model.band.bandName ?? "your WHOOP"). After the first time, Strava connects by itself.")
      Spacer()
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .presentationDetents([.medium])
    .presentationBackground(.black)
  }

  private func step(_ n: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(n)")
        .font(.subheadline.weight(.semibold))
        .frame(width: 26, height: 26)
        .overlay(Circle().strokeBorder(Color.hairline))
      Text(text).foregroundStyle(Color.textSecondary)
    }
  }
}
