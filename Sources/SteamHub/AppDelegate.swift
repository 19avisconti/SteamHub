import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = RepoWatcher.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "trophy.fill",
                                          accessibilityDescription: "SteamHub")
        statusItem.button?.image?.isTemplate = true

        watcher.onEvent = { ToastPresenter.shared.show($0) }
        watcher.onReposChanged = { [weak self] in
            guard let self else { return }
            self.rebuildMenu()
            WelcomeWindowController.shared.reposChanged(count: self.watcher.repos.count)
        }

        enableLaunchAtLoginByDefault()
        rebuildMenu()
        watcher.start()
        WelcomeWindowController.shared.showIfFirstRun()
    }

    /// On by default — a push notifier that isn't running notifies nothing, and being an
    /// agent with no Dock icon there's nothing obvious to relaunch it from. Applied once,
    /// so switching it off in the menu sticks.
    private func enableLaunchAtLoginByDefault() {
        guard !Settings.didConfigureLaunchAtLogin else { return }
        Settings.didConfigureLaunchAtLogin = true
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Registration can fail when the app runs from a temporary or non-stable
            // location. Not worth interrupting launch over; the menu toggle still works.
            NSLog("SteamHub: launch at login registration failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        let repos = watcher.repos
        let active = watcher.activeRepos.count

        menu.addItem(withTitle: repos.isEmpty
                        ? "No repositories found"
                        : "Watching \(active) of \(repos.count) repositories",
                     action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        addSubmenu(to: menu, "Repositories", repositoriesMenu(repos))
        addSubmenu(to: menu, "Scan Folders", scanFoldersMenu())
        addSubmenu(to: menu, "Check Every", intervalMenu())

        menu.addItem(.separator())
        add(to: menu, "Check Now", #selector(checkNow))
        add(to: menu, "Test Notification", #selector(testNotification))
        add(to: menu, "Setup…", #selector(showSetup))

        menu.addItem(.separator())
        let login = add(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off

        menu.addItem(withTitle: "Quit SteamHub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func repositoriesMenu(_ repos: [String]) -> NSMenu {
        let menu = NSMenu()
        let muted = Settings.disabledRepos
        for repo in repos {
            let item = add(to: menu, URL(fileURLWithPath: repo).lastPathComponent, #selector(toggleRepo(_:)))
            item.representedObject = repo
            item.toolTip = repo
            item.state = muted.contains(repo) ? .off : .on
        }
        if !repos.isEmpty { menu.addItem(.separator()) }
        add(to: menu, "Add Repository…", #selector(addRepository))
        add(to: menu, "Rescan Now", #selector(rescan))
        return menu
    }

    private func scanFoldersMenu() -> NSMenu {
        let menu = NSMenu()
        for root in Settings.scanRoots {
            let item = add(to: menu, (root as NSString).abbreviatingWithTildeInPath, #selector(removeScanRoot(_:)))
            item.representedObject = root
            item.toolTip = "Click to stop scanning this folder"
        }
        if !Settings.scanRoots.isEmpty { menu.addItem(.separator()) }
        add(to: menu, "Add Folder…", #selector(addScanRoot))
        return menu
    }

    private func intervalMenu() -> NSMenu {
        let menu = NSMenu()
        for (label, seconds) in [("30 seconds", 30.0), ("1 minute", 60.0),
                                 ("5 minutes", 300.0), ("15 minutes", 900.0)] {
            let item = add(to: menu, label, #selector(setInterval(_:)))
            item.representedObject = seconds
            item.state = Settings.pollInterval == seconds ? .on : .off
        }
        return menu
    }

    private func addSubmenu(to menu: NSMenu, _ title: String, _ submenu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.setSubmenu(submenu, for: item)
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func checkNow() { watcher.checkNow() }

    @objc private func testNotification() {
        ToastPresenter.shared.show(title: "octocat",
                                   body: "Refactor the notification queue so overlapping pushes stack cleanly")
    }

    @objc private func showSetup() { WelcomeWindowController.shared.show() }

    @objc private func rescan() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.watcher.reloadRepos()
            self.watcher.checkNow()
        }
    }

    @objc private func toggleRepo(_ sender: NSMenuItem) {
        guard let repo = sender.representedObject as? String else { return }
        var muted = Settings.disabledRepos
        if muted.contains(repo) { muted.remove(repo) } else { muted.insert(repo) }
        Settings.disabledRepos = muted
        rebuildMenu()
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        Settings.pollInterval = seconds
        watcher.restartTimer()
        rebuildMenu()
    }

    @objc private func addRepository() {
        guard let path = chooseFolder(prompt: "Watch Repository") else { return }
        guard FileManager.default.fileExists(atPath: path + "/.git") || Git.isRepo(path) else {
            alert("Not a git repository", "\(path) doesn't contain a .git directory.")
            return
        }
        if !Settings.manualRepos.contains(path) { Settings.manualRepos.append(path) }
        Settings.disabledRepos.remove(path)
        rescan()
    }

    @objc private func addScanRoot() {
        guard let path = chooseFolder(prompt: "Scan Folder") else { return }
        if !Settings.scanRoots.contains(path) { Settings.scanRoots.append(path) }
        rescan()
    }

    @objc private func removeScanRoot(_ sender: NSMenuItem) {
        guard let root = sender.representedObject as? String else { return }
        Settings.scanRoots.removeAll { $0 == root }
        rescan()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change login item", error.localizedDescription)
        }
        rebuildMenu()
    }

    // MARK: - Helpers

    private func chooseFolder(prompt: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
