import AppKit
import SwiftUI

@main
enum Main {
    private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let args = CommandLine.arguments
        // 개발용: 메뉴바 아이콘 미리보기 PNG 생성
        if let i = args.firstIndex(of: "--export-preview"), i + 1 < args.count {
            IconExport.previews(to: args[i + 1])
            return
        }
        // 진단용: `GitHubActionWidget --check owner/repo` — 최근 run 과 job/step 해석 결과를 출력
        if let i = args.firstIndex(of: "--check"), i + 1 < args.count {
            let repo = args[i + 1]
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await Diagnostics.check(repo)
                done.signal()
            }
            while done.wait(timeout: .now()) == .timedOut {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            return
        }

        let app = NSApplication.shared
        let d = AppDelegate()
        delegate = d
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setup()
        panel = PanelController(store: store, openSettings: { [weak self] in self?.openSettings() })
        statusItem = StatusItemController(
            store: store,
            togglePanel: { [weak self] in self?.panel?.toggle() },
            openSettings: { [weak self] in self?.openSettings() })
        store.start()
        if store.watched.isEmpty { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.panelVisible = true
        return false
    }

    private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(store))
            let w = NSWindow(contentViewController: host)
            w.title = L.t("GitHub Action Widget 설정", "GitHub Action Widget Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

enum IconExport {
    static func previews(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let variants: [(String, NSColor?)] = [("plain", nil), ("running", .systemOrange), ("failing", .systemRed)]
        for (name, badge) in variants {
            try? GitHubMark.previewPNG(badge: badge, background: NSColor(white: 0.12, alpha: 1))?
                .write(to: url.appendingPathComponent("menubar-\(name).png"))
        }
    }
}
