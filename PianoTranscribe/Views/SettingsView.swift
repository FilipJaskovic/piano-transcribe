import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Device", selection: $model.selectedDevice) {
                    ForEach(TranskunDevice.allCases) { device in
                        Text(device.label).tag(device)
                    }
                }

                Toggle("Separate piano from orchestra", isOn: $model.isPianoSeparationEnabled)
                    .disabled(!model.isPianoSeparationAvailable)

                Text(model.isPianoSeparationAvailable ? "Uses the bundled HDMC pc-separation model." : model.pianoSeparationAvailabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Output") {
                Picker("Save MIDI to", selection: $model.outputDestinationMode) {
                    ForEach(OutputDestinationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.outputDestinationMode == .customFolder {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(model.customOutputFolderPath)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .font(.caption)
                            .foregroundStyle(model.customOutputFolderURL == nil ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            model.chooseCustomOutputFolder()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                    }

                    Button(role: .destructive) {
                        model.clearCustomOutputFolder()
                    } label: {
                        Label("Clear Custom Folder", systemImage: "xmark.circle")
                    }
                    .disabled(model.customOutputFolderURL == nil)
                } else {
                    Text("MIDI files are saved beside the selected audio file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView(model: AppModel())
}
