import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Model", selection: $model.selectedCheckpoint) {
                    Text(TranskunCheckpoint.packagedDefault.label)
                        .tag(TranskunCheckpoint.packagedDefault)
                    Text(TranskunCheckpoint.benchmarkV2.label)
                        .tag(TranskunCheckpoint.benchmarkV2)
                        .disabled(!model.isBenchmarkCheckpointAvailable)
                }

                Picker("Device", selection: $model.selectedDevice) {
                    ForEach(TranskunDevice.allCases) { device in
                        Text(device.label).tag(device)
                    }
                }
            }

            Section("Output") {
                Picker("Save MIDI to", selection: $model.outputDestinationMode) {
                    ForEach(OutputDestinationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if model.outputDestinationMode == .customFolder {
                    LabeledContent("Folder") {
                        HStack(spacing: 8) {
                            Text(model.customOutputFolderURL?.lastPathComponent ?? "Not selected")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(model.customOutputFolderPath)
                            Spacer(minLength: 0)
                            Button("Choose...", systemImage: "folder") {
                                model.chooseCustomOutputFolder()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isRunning)
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView(model: AppModel())
        .frame(width: 480, height: 380)
}
