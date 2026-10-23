import SwiftUI
import AppKit

@main
struct InstagramMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Prismgram", id: "main") {
            ContentView(store: store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appSettings) {
                Button("Instagram Ayarları…") { store.isShowingInstagramSettings = true }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
                    .disabled(store.session != .signedIn)
            }

            CommandMenu("Görünüm Modu") {
                Button("Telefon") { store.layoutMode = .phone }
                    .keyboardShortcut("1", modifiers: .control)
                Button("Hibrit") { store.layoutMode = .hybrid }
                    .keyboardShortcut("2", modifiers: .control)
                Button("Masaüstü") { store.layoutMode = .desktop }
                    .keyboardShortcut("3", modifiers: .control)

                Divider()

                Button("Bildirimler Panelini Aç/Kapat") { store.isInspectorShown.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }

            CommandMenu("Gezinme") {
                Button("Ana Sayfa") { store.select(.home) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Keşfet") { store.select(.explore) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Reels") { store.select(.reels) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Bildirimler") { store.select(.activity) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Mesajlar") { store.select(.direct) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Profil") { store.select(.profile) }
                    .keyboardShortcut("6", modifiers: .command)

                Divider()

                Button("Yenile") { Task { await store.refresh(store.tab) } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            PrismgramSettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.alphaValue > 0 {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
