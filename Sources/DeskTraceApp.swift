import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DeskTraceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = DeskModel()
    var body: some Scene {
        Window("자리기록", id: "library") {
            LibraryView(model: model)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
        .defaultSize(width: 930, height: 620)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            Image(systemName: model.active ? "viewfinder.circle.fill" : "viewfinder")
                .accessibilityLabel("자리기록 · " + model.status)
        }
    }
}

struct StatusMenu: View {
    @ObservedObject var model: DeskModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("자리기록 · " + model.status)
        Button("기록 보기") { openWindow(id: "library"); NSApp.activate(ignoringOtherApps: true) }
        if model.active { Button("감지 끄기") { model.stop() } }
        Divider()
        Button("자리기록 종료") { model.stop(); NSApp.terminate(nil) }
    }
}
