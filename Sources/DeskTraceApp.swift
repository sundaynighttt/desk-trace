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
            library
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 276)
        .windowResizability(.contentSize)
        MenuBarExtra {
            StatusMenu(model: model)
        } label: {
            Image(systemName: model.active ? "viewfinder.circle.fill" : "viewfinder")
                .accessibilityLabel("자리기록 · " + model.status)
        }
    }
    @ViewBuilder
    private var library: some View {
        if #available(macOS 15, *) {
            LibraryView(model: model).containerBackground(.clear, for: .window)
        } else {
            LibraryView(model: model)
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
