import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let panelView = QuotaPanelView()
    private let touchBarQuotaView = TouchBarQuotaView()
    private let client = CodexAppServerClient()
    private var refreshTimer: Timer?
    private var systemTouchBar: NSTouchBar?
    private var touchBarWindow: TouchBarWindow?
    private var touchBarResponder: TouchBarResponder?
    private var snapshot = QuotaSnapshot.empty
    private var lastError: String?

    private enum TouchBarID {
        static let bar = NSTouchBar.CustomizationIdentifier("com.local.codexQuotaTouchBar")
        static let quota = NSTouchBarItem.Identifier("com.local.codexQuotaTouchBar.quota")
        static let tray = "com.local.codexQuotaTouchBar.tray"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        installTouchBar()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.presentSystemModalTouchBar()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        client.stop()
    }

    func makeTouchBar() -> NSTouchBar? {
        if let systemTouchBar {
            return systemTouchBar
        }

        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = TouchBarID.bar
        touchBar.principalItemIdentifier = TouchBarID.quota
        touchBar.defaultItemIdentifiers = [TouchBarID.quota]
        systemTouchBar = touchBar
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == TouchBarID.quota else {
            return nil
        }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = touchBarQuotaView
        return item
    }

    @objc private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            presentSystemModalTouchBar()
        }
    }

    @objc private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            do {
                let newSnapshot = try self.client.readRateLimits()
                DispatchQueue.main.async {
                    self.snapshot = newSnapshot
                    self.lastError = nil
                    self.render()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.render()
                }
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openCodex() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Codex.app"))
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = "Codex"
        button.target = self
        button.action = #selector(showPopover)
        button.toolTip = "Codex 额度"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.menu = nil
    }

    private func configurePopover() {
        let controller = NSViewController()
        controller.view = panelView
        popover.contentViewController = controller
        popover.behavior = .transient
    }

    private func installTouchBar() {
        guard let touchBar = makeTouchBar() else {
            return
        }

        let responder = TouchBarResponder(appDelegate: self)
        touchBarResponder = responder

        let window = TouchBarWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.touchBar = touchBar
        window.nextResponder = responder
        window.makeFirstResponder(responder)
        window.level = .statusBar
        window.alphaValue = 0.01
        window.orderFrontRegardless()
        touchBarWindow = window

        NSApp.touchBar = touchBar
    }

    private func presentSystemModalTouchBar() {
        guard let touchBar = systemTouchBar ?? makeTouchBar() else {
            return
        }

        let selector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: selector) else {
            return
        }

        _ = NSTouchBar.perform(
            selector,
            with: touchBar,
            with: TouchBarID.tray
        )
    }

    private func render() {
        let remaining = snapshot.primary?.remainingPercent ?? snapshot.secondary?.remainingPercent
        if let remaining {
            statusItem.button?.title = "Codex \(remaining)%"
        } else {
            statusItem.button?.title = lastError == nil ? "Codex --%" : "Codex 错误"
        }

        panelView.update(snapshot: snapshot, error: lastError)
        touchBarQuotaView.update(snapshot: snapshot)
        presentSystemModalTouchBar()
    }
}

private final class TouchBarWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class TouchBarResponder: NSResponder {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeTouchBar() -> NSTouchBar? {
        appDelegate?.makeTouchBar()
    }
}
