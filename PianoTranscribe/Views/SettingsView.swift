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

                Picker("Transkun checkpoint", selection: $model.selectedCheckpoint) {
                    Text(TranskunCheckpoint.packagedDefault.label)
                        .tag(TranskunCheckpoint.packagedDefault)

                    Text(TranskunCheckpoint.benchmarkV2.label)
                        .tag(TranskunCheckpoint.benchmarkV2)
                        .disabled(!model.isBenchmarkCheckpointAvailable)
                }

                Text(model.selectedCheckpoint.detail)
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
        .disabled(model.isRunning)
    }
}

#Preview {
    SettingsView(model: AppModel())
}
