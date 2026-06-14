import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let touchBarQuotaView = TouchBarQuotaView()
    private let client = CodexAppServerClient()
    private var refreshTimer: Timer?
    private var touchBarPresentationTimer: Timer?
    private var systemTouchBar: NSTouchBar?
    private var touchBarWindow: TouchBarWindow?
    private var touchBarResponder: TouchBarResponder?
    private var trayItem: NSCustomTouchBarItem?
    private var trayButton: NSButton?
    private var snapshot = QuotaSnapshot.empty
    private var lastError: String?
    private var isUsingCachedSnapshot = false

    private enum TouchBarID {
        static let bar = NSTouchBar.CustomizationIdentifier("com.local.codexQuotaTouchBar")
        static let quota = NSTouchBarItem.Identifier("com.local.codexQuotaTouchBar.quota")
        static let trayItem = NSTouchBarItem.Identifier("com.local.codexQuotaTouchBar.tray")
        static let tray = "com.local.codexQuotaTouchBar.tray"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installTouchBar()
        NSApp.activate(ignoringOtherApps: true)
        startTouchBarPresentationTimer()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.keepTouchBarVisible()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        touchBarPresentationTimer?.invalidate()
        unregisterControlStripItem()
        client.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        keepTouchBarVisible()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        keepTouchBarVisible()
    }

    func applicationDidResignActive(_ notification: Notification) {
        keepTouchBarVisible()
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

    @objc private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            do {
                let newSnapshot = try self.client.readRateLimits()
                DispatchQueue.main.async {
                    self.snapshot = newSnapshot
                    self.lastError = nil
                    self.isUsingCachedSnapshot = false
                    self.render()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isUsingCachedSnapshot = self.snapshot.primary != nil || self.snapshot.secondary != nil
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
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        touchBarWindow = window

        NSApp.touchBar = touchBar
        registerControlStripItem()
    }

    private func startTouchBarPresentationTimer() {
        touchBarPresentationTimer?.invalidate()
        touchBarPresentationTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.keepTouchBarVisible()
        }
    }

    private func registerControlStripItem() {
        guard trayItem == nil else {
            return
        }

        let button = NSButton(title: "Codex", target: self, action: #selector(refresh))
        button.bezelColor = .controlAccentColor
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let item = NSCustomTouchBarItem(identifier: TouchBarID.trayItem)
        item.customizationLabel = "Codex 额度"
        item.view = button

        let selector = NSSelectorFromString("addSystemTrayItem:")
        if NSTouchBarItem.responds(to: selector) {
            _ = NSTouchBarItem.perform(selector, with: item)
        }

        trayItem = item
        trayButton = button
    }

    private func unregisterControlStripItem() {
        guard let trayItem else {
            return
        }

        let selector = NSSelectorFromString("removeSystemTrayItem:")
        if NSTouchBarItem.responds(to: selector) {
            _ = NSTouchBarItem.perform(selector, with: trayItem)
        }
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

    private func keepTouchBarVisible() {
        touchBarWindow?.makeKeyAndOrderFront(nil)
        touchBarWindow?.orderFrontRegardless()
        NSApp.touchBar = systemTouchBar ?? makeTouchBar()
        presentSystemModalTouchBar()
    }

    private func render() {
        let remaining = snapshot.primary?.remainingPercent ?? snapshot.secondary?.remainingPercent
        if let remaining {
            trayButton?.title = "Codex \(remaining)%"
        } else {
            trayButton?.title = lastError == nil ? "Codex --%" : "Codex 错误"
        }

        touchBarQuotaView.update(snapshot: snapshot)
        keepTouchBarVisible()
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
