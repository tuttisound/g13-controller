import AppKit
import SwiftUI
import G13Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let controller = AppController()
    lazy var editor = EditorModel(controller: controller)

    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
        setupStatusItem()
        refreshMenu()

        // Show the window on first run if permissions are missing.
        if !controller.inputMonitoringGranted || !controller.accessibilityGranted {
            showWindow()
        }

        // Poll permissions so the menu/UI reflect grants made in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.controller.refreshPermissions()
                self.refreshMenu()
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gamecontroller", accessibilityDescription: "G13")
        item.menu = NSMenu()
        statusItem = item
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        menu.addItem(disabled(controller.deviceConnected ? "G13: Connected" : "G13: Disconnected"))
        menu.addItem(disabled("Profile: \(controller.activeProfileName) — \(MKey.forBank(controller.activeBankIndex).displayName)"))
        if !controller.inputMonitoringGranted || !controller.accessibilityGranted {
            menu.addItem(disabled("⚠︎ Permissions needed — open settings"))
        }
        menu.addItem(.separator())

        let bankMenu = NSMenu()
        for i in 0..<4 {
            let it = NSMenuItem(title: "\(MKey.forBank(i).displayName): \(activeBankName(i))",
                                action: #selector(selectBank(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (i == controller.activeBankIndex) ? .on : .off
            bankMenu.addItem(it)
        }
        let bankItem = NSMenuItem(title: "Active Bank", action: nil, keyEquivalent: "")
        bankItem.submenu = bankMenu
        menu.addItem(bankItem)

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = controller.config.settings.masterEnabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open G13 Manager…", action: #selector(showWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit G13 Manager", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func activeBankName(_ i: Int) -> String {
        controller.config.profiles.first { $0.id == controller.activeProfileID }?.banks[safe: i]?.name
            ?? "Bank \(i + 1)"
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    @objc private func selectBank(_ sender: NSMenuItem) {
        controller.selectBank(sender.tag)
        refreshMenu()
    }

    @objc private func toggleEnabled() {
        controller.setMasterEnabled(!controller.config.settings.masterEnabled)
        refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Window

    @objc private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(editor: editor))
            let win = NSWindow(contentViewController: hosting)
            win.title = "G13 Manager"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 1080, height: 720))
            win.contentMinSize = NSSize(width: 900, height: 600)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            win.setFrameAutosaveName("G13ManagerMainWindow")  // remember size across launches
            window = win
        }
        NSApp.setActivationPolicy(.regular)   // show app menu + Dock icon while open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // back to menu-bar-only when window closes
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
}
