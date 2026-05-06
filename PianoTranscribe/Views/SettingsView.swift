import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var futureSeparationEnabled = false

    var body: some View {
        Form {
            Picker("Device", selection: $model.selectedDevice) {
                ForEach(TranskunDevice.allCases) { device in
                    Text(device.label).tag(device)
                }
            }

            Toggle("Separate piano from orchestra", isOn: $futureSeparationEnabled)
                .disabled(true)

            Text("Coming later")
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
