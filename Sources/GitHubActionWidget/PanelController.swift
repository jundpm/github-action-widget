import AppKit
import Combine
import SwiftUI

/// 다른 앱을 쓰는 중에도 포커스를 뺏지 않고 떠 있는 패널.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(b)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private static let frameName = "GitHubActionWidgetPanel"
    private static let expandedHeightKey = "panelExpandedHeight"
    private static let collapsedHeight: CGFloat = 40

    let panel: FloatingPanel
    private let store: Store
    private var bag = Set<AnyCancellable>()

    init(store: Store, openSettings: @escaping () -> Void) {
        self.store = store
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300))
        weak let weakStore = store
        let root = PanelView(openSettings: openSettings,
                             hidePanel: { weakStore?.panelVisible = false })
            .environmentObject(store)
        panel.contentView = NSHostingView(rootView: root)

        if !panel.setFrameUsingName(Self.frameName), let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - 340 - 16, y: v.maxY - 300 - 16))
        }
        panel.setFrameAutosaveName(Self.frameName)
        applyCollapsed(store.collapsed, animate: false)

        store.$alwaysOnTop
            .sink { [weak self] on in self?.panel.level = on ? .floating : .normal }
            .store(in: &bag)
        store.$collapsed.dropFirst().removeDuplicates()
            .sink { [weak self] c in self?.applyCollapsed(c, animate: true) }
            .store(in: &bag)
        store.$panelVisible.removeDuplicates()
            .sink { [weak self] visible in
                guard let self else { return }
                if visible { self.panel.orderFrontRegardless() } else { self.panel.orderOut(nil) }
            }
            .store(in: &bag)
    }

    func toggle() { store.panelVisible.toggle() }

    private func applyCollapsed(_ collapsed: Bool, animate: Bool) {
        var f = panel.frame
        let top = f.maxY
        let defaults = UserDefaults.standard
        if collapsed {
            if f.height > Self.collapsedHeight + 20 { defaults.set(f.height, forKey: Self.expandedHeightKey) }
            f.size.height = Self.collapsedHeight
            panel.minSize = NSSize(width: 260, height: Self.collapsedHeight)
            panel.maxSize = NSSize(width: 900, height: Self.collapsedHeight)
        } else {
            let saved = defaults.double(forKey: Self.expandedHeightKey)
            f.size.height = max(saved > 0 ? saved : 300, 140)
            panel.minSize = NSSize(width: 260, height: 140)
            panel.maxSize = NSSize(width: 900, height: 2000)
        }
        f.origin.y = top - f.height
        panel.setFrame(f, display: true, animate: animate)
    }
}
