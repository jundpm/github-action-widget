import AppKit
import Combine

/// 메뉴바의 GitHub 마크. 실행 중이면 주황 점이 깜빡이고, 실패가 있으면 빨간 점이 붙는다.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: Store
    private let togglePanel: () -> Void
    private let openSettings: () -> Void
    private var bag = Set<AnyCancellable>()
    private var pulse: Timer?
    private var pulseOn = true

    private let plain = GitHubMark.menuBarImage(badge: nil)
    private let failing = GitHubMark.menuBarImage(badge: .systemRed)
    private let runningOn = GitHubMark.menuBarImage(badge: .systemOrange)
    private let runningDim = GitHubMark.menuBarImage(badge: NSColor.systemOrange.withAlphaComponent(0.35))

    init(store: Store, togglePanel: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.store = store
        self.togglePanel = togglePanel
        self.openSettings = openSettings
        super.init()
        item.button?.image = plain
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        store.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &bag)
        updateIcon()
    }

    private func updateIcon() {
        guard let button = item.button else { return }
        switch store.overall {
        case .running(let n):
            startPulse()
            button.title = n > 1 ? " \(n)" : ""
            button.toolTip = L.t("GitHub Actions — \(n)개 실행 중", "GitHub Actions — \(n) running")
        case .failing(let n):
            stopPulse()
            button.image = failing
            button.title = ""
            button.toolTip = L.t("GitHub Actions — 최근 실패 \(n)개 레포", "GitHub Actions — \(n) repos failing")
        case .ok, .idle:
            stopPulse()
            button.image = plain
            button.title = ""
            button.toolTip = L.t("GitHub Actions — 모두 정상", "GitHub Actions — all good")
        }
    }

    private func startPulse() {
        guard pulse == nil else { return }
        pulseOn = true
        item.button?.image = runningOn
        pulse = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pulseOn.toggle()
                self.item.button?.image = self.pulseOn ? self.runningOn : self.runningDim
            }
        }
    }

    private func stopPulse() {
        pulse?.invalidate()
        pulse = nil
    }

    // MARK: 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let active = store.activeRuns
        if active.isEmpty {
            menu.addItem(disabled(store.watched.isEmpty ? L.t("볼 레포를 선택하세요", "Choose repositories") : L.t("실행 중인 Actions 없음", "No runs in progress")))
        } else {
            menu.addItem(disabled(L.t("실행 중 \(active.count)개", "\(active.count) running")))
            for (repo, run) in active {
                let elapsed = Format.duration(Date().timeIntervalSince(run.startDate))
                let title = "\(Format.shortName(repo)) · \(run.workflowName) · \(run.headBranch ?? "-") · \(elapsed)"
                let mi = NSMenuItem(title: title, action: #selector(openURL(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = run.htmlUrl
                mi.image = NSImage(systemSymbolName: run.visual == .running ? "circle.dotted" : "clock",
                                   accessibilityDescription: nil)
                menu.addItem(mi)
            }
        }

        let failingRepos = store.watched.filter { store.repoStates[$0]?.isFailing == true }
        if !failingRepos.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled(L.t("최근 실패", "Recent failures")))
            for repo in failingRepos {
                guard let run = store.repoStates[repo]?.latestPerWorkflow.first(where: { $0.visual == .failure }) else { continue }
                let mi = NSMenuItem(title: "\(Format.shortName(repo)) · \(run.workflowName) · \(Format.ago(run.updatedAt))",
                                    action: #selector(openURL(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = run.htmlUrl
                mi.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        menu.addItem(action(store.panelVisible ? L.t("패널 숨기기", "Hide panel") : L.t("패널 보이기", "Show panel"), #selector(togglePanelAction), "p"))
        menu.addItem(action(L.t("지금 새로고침", "Refresh now"), #selector(refreshAction), "r"))
        menu.addItem(action(L.t("설정…", "Settings…"), #selector(settingsAction), ","))
        menu.addItem(.separator())
        menu.addItem(action(L.t("GitHub Action Widget 종료", "Quit GitHub Action Widget"), #selector(quitAction), "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    private func action(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func openURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func togglePanelAction() { togglePanel() }
    @objc private func refreshAction() { store.refreshNow() }
    @objc private func settingsAction() { openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
