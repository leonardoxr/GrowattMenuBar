import AppKit
import SwiftUI

@main
struct GrowattMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
                .frame(width: 430)
                .padding(16)
        } label: {
            MenuLabel(monitor: monitor)
                .task {
                    monitor.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuLabel: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        Image(systemName: monitor.menuSymbol)
        Text(monitor.menuTitle)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
