import AppKit
import SwiftUI

@main
struct PianoTranscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Piano transcribe", id: "main") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 600, height: 480)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Audio File...") {
                    model.presentImporter()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(model.isRunning)

                Button("Cancel Transcription") {
                    model.cancel()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancel)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 480, height: 380)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var isStopping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isRunning else { return .terminateNow }
        if !isStopping {
            isStopping = true
            Task { @MainActor in
                await model.stop()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
