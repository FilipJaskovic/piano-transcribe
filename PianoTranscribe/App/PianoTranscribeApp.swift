import AppKit
import SwiftUI

@main
struct PianoTranscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Choose Audio File...") {
                    model.presentImporter()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Cancel Transcription") {
                    model.cancel()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canCancel)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 420)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
