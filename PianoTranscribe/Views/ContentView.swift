import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            audioArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 180)
                .background(.background)
                .contentShape(Rectangle())
                .onDrop(
                    of: [UTType.fileURL.identifier],
                    isTargeted: $model.isDropTargeted,
                    perform: model.handleDrop(providers:)
                )
                .overlay {
                    if model.isDropTargeted && !model.isRunning {
                        Rectangle().stroke(.tint, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }

            Divider()

            options
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    StatusView(status: model.status, progress: model.progress)

                    if model.isRunning {
                        Button("Cancel", action: model.cancel)
                            .disabled(!model.canCancel)
                    } else if case .completed(let url) = model.status {
                        Button("Show in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }

                if !model.logLines.isEmpty {
                    LogView(lines: model.logLines, isExpanded: $model.isLogExpanded)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: model.isLogExpanded && !model.logLines.isEmpty ? 600 : 460)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Choose Audio...", systemImage: "folder.badge.plus") {
                    model.presentImporter()
                }
                .disabled(model.isRunning)
                .help("Choose an audio file")
            }
            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: SupportedAudioTypes.importerTypes,
            allowsMultipleSelection: false,
            onCompletion: model.handleImporterResult(_:)
        )
        .task {
            model.refreshBenchmarkCheckpointAvailability()
            model.runStartupAutomationIfNeeded()
        }
    }

    @ViewBuilder
    private var audioArea: some View {
        if let url = model.sourceURL, !model.isDropTargeted || model.isRunning {
            VStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)

                Text(url.lastPathComponent)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(url.path)

                Label(url.deletingLastPathComponent().lastPathComponent, systemImage: "folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(24)
            .contextMenu {
                Button("Show Audio in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } else {
            DropZoneView(isTargeted: model.isDropTargeted, chooseAudio: model.presentImporter)
        }
    }

    private var options: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Model")
                    .gridColumnAlignment(.trailing)
                Picker("Model", selection: $model.selectedCheckpoint) {
                    Text(TranskunCheckpoint.packagedDefault.label)
                        .tag(TranskunCheckpoint.packagedDefault)
                    Text(TranskunCheckpoint.benchmarkV2.label)
                        .tag(TranskunCheckpoint.benchmarkV2)
                        .disabled(!model.isBenchmarkCheckpointAvailable)
                }
                .labelsHidden()
                .frame(width: 280, alignment: .leading)
            }

            GridRow {
                Text("Save MIDI to")
                Picker("Save MIDI to", selection: $model.outputDestinationMode) {
                    ForEach(OutputDestinationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 280, alignment: .leading)
            }

            if model.outputDestinationMode == .customFolder {
                GridRow {
                    Text("Folder")
                    HStack(spacing: 8) {
                        Text(model.customOutputFolderURL?.lastPathComponent ?? "Not selected")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(model.customOutputFolderPath)
                        Button("Choose...", systemImage: "folder") {
                            model.chooseCustomOutputFolder()
                        }
                    }
                    .frame(width: 280)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(model.isRunning)
    }
}

#Preview {
    ContentView(model: AppModel())
}
