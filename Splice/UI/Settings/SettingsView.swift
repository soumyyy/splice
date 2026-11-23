import SpliceCore
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var confirmForget = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          Stepper(value: $model.maxHeartRate, in: 140...220) {
            LabeledContent("Max heart rate", value: "\(model.maxHeartRate) bpm")
          }
          ForEach((0..<5).reversed(), id: \.self) { i in
            LabeledContent {
              Text(range(i)).monospacedDigit()
            } label: {
              Label("Z\(i + 1) \(HeartRateZones.names[i])", systemImage: "circle.fill")
                .foregroundStyle(Color.zone(i))
            }
          }
        } header: {
          Text("Zones")
        } footer: {
          Text("Use the same max heart rate as in Strava (Settings → My Performance) so zones match.")
        }

        Section("Band") {
          LabeledContent("Band", value: model.band.hasSavedBand ? model.band.displayName : "Not paired")
          if let serial = model.band.serial {
            LabeledContent("Serial", value: serial)
          }
          if let name = model.band.bandName {
            LabeledContent("Name in Strava", value: name)
          }
          if let battery = model.band.batteryPercent {
            LabeledContent("Battery", value: "\(battery)%")
          }
          if model.band.hasSavedBand {
            Button("Forget band", role: .destructive) { confirmForget = true }
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .confirmationDialog("Forget this band?", isPresented: $confirmForget) {
        Button("Forget", role: .destructive) { model.band.forgetBand() }
      }
    }
  }

  private func range(_ i: Int) -> String {
    let t = model.zones.thresholds
    return i == 4 ? "\(t[4])+ bpm" : "\(i == 0 ? 0 : t[i])–\(t[i + 1] - 1) bpm"
  }
}
