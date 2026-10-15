// Midpoint UI: a menu bar item for everyday use and a settings window that shows live status.

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let showMenuBarIconKey = "showMenuBarIcon"
    private static let launchedBeforeKey = "hasLaunchedBefore"

    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var refreshTimer: Timer?

    private let statusDot = NSTextField(labelWithString: "●")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let fingersLabel = NSTextField(labelWithString: "")
    private let lastClickLabel = NSTextField(labelWithString: "")
    private var permissionBox: NSStackView!
    private var threeClickBox: NSButton!
    private var threeTapBox: NSButton!
    private var loginBox: NSButton!
    private var menuBarBox: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.showMenuBarIconKey: true])
        buildMainMenu()
        buildWindow()
        updateStatusItemVisibility()
        startTouchInput()
        if !startEngine() {
            // Ask once, then poll: the tap starts as soon as access is granted, no relaunch needed.
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                if startEngine() { t.invalidate(); self?.refresh() }
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()

        // Open the window on first launch, when permission is missing, or when there is no menu bar icon to use.
        let firstLaunch = !UserDefaults.standard.bool(forKey: Self.launchedBeforeKey)
        UserDefaults.standard.set(true, forKey: Self.launchedBeforeKey)
        if firstLaunch || !AXIsProcessTrusted() || statusItem == nil { showWindow() }
    }

    // Closing the window keeps the app running; reopening it from Finder or Spotlight brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: Menu bar item

    private func updateStatusItemVisibility() {
        let show = UserDefaults.standard.bool(forKey: Self.showMenuBarIconKey)
        if show, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.menuBarImage()
            item.button?.toolTip = "Midpoint"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !show, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Rebuilt each time the menu opens so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(Self.infoItem(statusLabel.stringValue))
        if let last = Status.lastClick {
            menu.addItem(Self.infoItem("Last: \(last.gesture), \(last.at.formatted(date: .omitted, time: .shortened))"))
        }
        menu.addItem(.separator())
        menu.addItem(toggleItem("Three Finger Click", on: Settings.threeClick, action: #selector(toggleThreeClick)))
        menu.addItem(toggleItem("Three Finger Tap", on: Settings.threeTap, action: #selector(toggleThreeTap)))
        menu.addItem(.separator())
        menu.addItem(toggleItem("Launch on Login", on: SMAppService.mainApp.status == .enabled, action: #selector(toggleLoginFromMenu)))
        let settings = NSMenuItem(title: "Settings…", action: #selector(showWindow), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Midpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func toggleItem(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Settings window

    private func buildWindow() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: "Midpoint")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.spacing = 4
        let header = NSStackView(views: [title, statusRow, detailLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        let top = NSStackView(views: [icon, header])
        top.spacing = 14
        top.alignment = .centerY

        let warn = NSTextField(wrappingLabelWithString: "Midpoint needs Accessibility access to send middle clicks. Turn it on in Privacy & Security → Accessibility; Midpoint starts as soon as it's allowed.")
        warn.font = .systemFont(ofSize: 12)
        let openSettings = NSButton(title: "Open System Settings", target: self, action: #selector(openAccessibilitySettings))
        permissionBox = NSStackView(views: [warn, openSettings])
        permissionBox.orientation = .vertical
        permissionBox.alignment = .leading

        threeClickBox = NSButton(checkboxWithTitle: "Three Finger Click", target: self, action: #selector(toggleThreeClick))
        threeTapBox = NSButton(checkboxWithTitle: "Three Finger Tap", target: self, action: #selector(toggleThreeTap))
        let gestures = NSStackView(views: [threeClickBox, threeTapBox])
        gestures.orientation = .vertical
        gestures.alignment = .leading
        let trackpadRow = NSStackView(views: [Self.rowLabel("Trackpad:"), gestures])
        trackpadRow.alignment = .top

        for l in [fingersLabel, lastClickLabel] { l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular) }
        let activity = NSStackView(views: [fingersLabel, lastClickLabel])
        activity.orientation = .vertical
        activity.alignment = .leading
        let activityRow = NSStackView(views: [Self.rowLabel("Activity:"), activity])
        activityRow.alignment = .top

        loginBox = NSButton(checkboxWithTitle: "Launch on login", target: self, action: #selector(toggleLogin(_:)))
        menuBarBox = NSButton(checkboxWithTitle: "Show menu bar icon", target: self, action: #selector(toggleMenuBarIcon(_:)))
        let general = NSStackView(views: [loginBox, menuBarBox])
        general.orientation = .vertical
        general.alignment = .leading
        let generalRow = NSStackView(views: [Self.rowLabel("General:"), general])
        generalRow.alignment = .top

        let hint = NSTextField(wrappingLabelWithString: "Closing this window keeps Midpoint running. Open it again from the menu bar icon, or by launching Midpoint from Finder.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [
            NSButton(title: "Open Debug Log", target: self, action: #selector(openLog)),
            NSView(),
            NSButton(title: "Quit Midpoint", target: NSApp, action: #selector(NSApplication.terminate(_:))),
        ])

        let root = NSStackView(views: [top, permissionBox, Self.separator(), trackpadRow, activityRow, generalRow,
                                       Self.separator(), hint, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for v in root.arrangedSubviews where v === permissionBox || v === buttons || v === hint || v is NSBox {
            v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Midpoint"
        window.isReleasedWhenClosed = false
        window.contentView = root
        root.widthAnchor.constraint(equalToConstant: 440).isActive = true
        window.center()
    }

    /// App menu so ⌘Q / ⌘W work while the settings window is focused.
    private func buildMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Midpoint", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let bar = NSMenu()
        for (title, menu) in [("Midpoint", appMenu), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            bar.addItem(item)
        }
        NSApp.mainMenu = bar
    }

    // MARK: Live status

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        let running = trusted && Status.tapInstalled
        statusItem?.button?.appearsDisabled = !running
        switch (trusted, Status.tapInstalled, Status.deviceCount) {
        case (false, _, _):
            setStatus("Waiting for Accessibility permission", .systemOrange, "Middle clicks are off until access is granted.")
        case (true, false, _):
            setStatus("Starting…", .systemOrange, "Permission granted; installing the event tap.")
        case (true, true, 0):
            setStatus("Running, but no trackpad found", .systemOrange, "Connect a trackpad; it is picked up after sleep/wake.")
        case (true, true, let n):
            let gestures = [Settings.threeClick ? "click" : nil, Settings.threeTap ? "tap" : nil].compactMap { $0 }
            setStatus("Running", .systemGreen, gestures.isEmpty
                      ? "All gestures are turned off."
                      : "Listening to \(n) trackpad\(n == 1 ? "" : "s") for three-finger \(gestures.joined(separator: " and ")).")
        }
        guard window.isVisible else { return }
        permissionBox.isHidden = running
        threeClickBox.state = Settings.threeClick ? .on : .off
        threeTapBox.state = Settings.threeTap ? .on : .off
        loginBox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menuBarBox.state = statusItem != nil ? .on : .off
        fingersLabel.stringValue = "Fingers on trackpad: \(state.fingers)"
        if let last = Status.lastClick {
            let time = last.at.formatted(date: .omitted, time: .standard)
            lastClickLabel.stringValue = "Last middle click: \(last.gesture) at \(time) (\(Status.clickCount) total)"
        } else {
            lastClickLabel.stringValue = "Last middle click: none yet"
        }
    }

    private func setStatus(_ text: String, _ color: NSColor, _ detail: String) {
        statusLabel.stringValue = text
        statusDot.textColor = color
        detailLabel.stringValue = detail
    }

    // MARK: Actions

    @objc private func toggleThreeClick() { UserDefaults.standard.set(!Settings.threeClick, forKey: Settings.threeClickKey); refresh() }
    @objc private func toggleThreeTap() { UserDefaults.standard.set(!Settings.threeTap, forKey: Settings.threeTapKey); refresh() }
    @objc private func toggleLoginFromMenu() { setLaunchOnLogin(SMAppService.mainApp.status != .enabled) }
    @objc private func toggleLogin(_ sender: NSButton) { setLaunchOnLogin(sender.state == .on) }

    private func setLaunchOnLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "You can add Midpoint manually in System Settings → General → Login Items."
            alert.runModal()
        }
        refresh()
    }

    @objc private func toggleMenuBarIcon(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.showMenuBarIconKey)
        updateStatusItemVisibility()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: logURL.path) { try? "".write(to: logURL, atomically: true, encoding: .utf8) }
        NSWorkspace.shared.open(logURL)
    }

    // MARK: Helpers

    private static func rowLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return l
    }

    private static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    /// Template glyph matching the app icon: a trackpad outline with three fingertips.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let pad = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5, width: 15, height: 11), xRadius: 2.5, yRadius: 2.5)
            pad.lineWidth = 1.5
            NSColor.black.setStroke(); pad.stroke()
            NSColor.black.setFill()
            for (x, y) in [(5.0, 9.0), (9.0, 10.0), (13.0, 9.0)] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
