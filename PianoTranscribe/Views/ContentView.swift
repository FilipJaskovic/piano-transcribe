import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            header

            DropZoneView(
                isTargeted: model.isDropTargeted,
                isEnabled: !model.isRunning,
                chooseAudio: model.presentImporter
            )
                .onDrop(
                    of: [UTType.fileURL.identifier],
                    isTargeted: $model.isDropTargeted,
                    perform: model.handleDrop(providers:)
                )

            controlBar

            StatusView(status: model.status, progress: model.progress)

            LogView(lines: model.logLines, isExpanded: $model.isLogExpanded)
        }
        .padding(28)
        .frame(minWidth: 660, minHeight: 560)
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: SupportedAudioTypes.importerTypes,
            allowsMultipleSelection: false,
            onCompletion: model.handleImporterResult(_:)
        )
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView(model: model)
        }
        .task {
            model.refreshBenchmarkCheckpointAvailability()
            model.runStartupAutomationIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Piano transcribe")
                    .font(.largeTitle.weight(.semibold))
                Text("Audio in, MIDI out")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                model.presentImporter()
            } label: {
                Label("Choose Audio", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(model.isRunning)

            Picker("Device", selection: $model.selectedDevice) {
                ForEach(TranskunDevice.allCases) { device in
                    Text(device.label).tag(device)
                }
            }
            .labelsHidden()
            .frame(width: 240)
            .disabled(model.isRunning)

            Spacer()

            if model.isRunning {
                Button {
                    model.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .disabled(!model.canCancel)
            }
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
