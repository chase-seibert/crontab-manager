import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CrontabManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CrontabStore()
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some Scene {
        WindowGroup("Crontab Manager") {
            ContentView(store: store)
                .frame(minWidth: DetailPaneWindowSizing.minimumListWidth, minHeight: DetailPaneWindowSizing.minimumHeight)
        }
        .commands {
            CommandMenu("Crontab") {
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Run Selected Job") {
                    Task { await store.runSelectedJobNow() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.selectedJob == nil)

                Divider()

                Button("Increase Text Size") {
                    appTextFontSize = AppTextSizing.increased(from: appTextFontSize)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Text Size") {
                    appTextFontSize = AppTextSizing.decreased(from: appTextFontSize)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Text Size") {
                    appTextFontSize = AppTextSizing.defaultSize
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
    }
}
