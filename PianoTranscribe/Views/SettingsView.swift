import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker("Device", selection: $model.selectedDevice) {
                ForEach(TranskunDevice.allCases) { device in
                    Text(device.label).tag(device)
                }
            }

            Toggle("Separate piano from orchestra", isOn: $model.isPianoSeparationEnabled)

            Text("Requires the separate pc-separation backend and downloaded weights.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView(model: AppModel())
}
