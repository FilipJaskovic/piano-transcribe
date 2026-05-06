import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            header

            DropZoneView(isTargeted: model.isDropTargeted)
                .onDrop(
                    of: [UTType.fileURL.identifier],
                    isTargeted: $model.isDropTargeted,
                    perform: model.handleDrop(providers:)
                )

            controlBar

            StatusView(status: model.status)

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
        .task {
            model.runStartupAutomationIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "pianokeys")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 3) {
                Text("Piano transcribe")
                    .font(.largeTitle.weight(.semibold))
                Text("Audio in, MIDI out")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                model.presentImporter()
            } label: {
                Label("Choose Audio", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Picker("Device", selection: $model.selectedDevice) {
                ForEach(TranskunDevice.allCases) { device in
                    Text(device.label).tag(device)
                }
            }
            .labelsHidden()
            .frame(width: 240)

            Spacer()

            Button {
                model.cancel()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .disabled(!model.canCancel)
        }
    }
}

#Preview {
    ContentView(model: AppModel())
}
