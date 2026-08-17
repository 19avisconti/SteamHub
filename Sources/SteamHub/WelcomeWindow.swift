import AppKit
import SwiftUI

/// First-run setup. Without it, launching SteamHub does nothing visible except add a
/// menu-bar icon — the user can't tell whether it found their repos or is even working.
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private static let seenKey = "hasSeenWelcome"
    private var window: NSWindow?
    private let state = WelcomeState()

    /// Shown automatically on first launch, and on demand from the menu.
    func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: Self.seenKey) else { return }
        show()
    }

    func show() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        state.refreshRoots()

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingView(rootView: WelcomeView(state: state))
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "SteamHub Setup"
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        // An accessory app loses activation the moment whatever launched it (Terminal,
        // Finder) reclaims focus, which buries this window behind that app. Float it so
        // first-run setup can't be missed; it goes away as soon as the user dismisses it.
        w.level = .floating
        w.collectionBehavior = [.moveToActiveSpace]
        w.contentView = host
        // The content grows when folders are added, so track its intrinsic height.
        host.autoresizingMask = [.width, .height]
        w.setContentSize(host.fittingSize)
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func reposChanged(count: Int) {
        state.scanning = false
        state.repoCount = count
        state.refreshRoots()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

final class WelcomeState: ObservableObject {
    @Published var scanning = true
    @Published var repoCount = 0
    @Published var roots: [String] = []

    func refreshRoots() {
        roots = Settings.scanRoots
    }
}

struct WelcomeView: View {
    static let maxListedRoots = 6

    @ObservedObject var state: WelcomeState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SteamHub")
                    .font(.system(size: 28, weight: .semibold))
                Text("A Steam achievement pops up when a teammate pushes to a repo you've cloned.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            status

            VStack(alignment: .leading, spacing: 8) {
                Text("Looking in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                if state.roots.isEmpty {
                    Text("No folders yet — add the one holding your repos.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    // Typically 3-6 entries; anything longer is summarised rather than scrolled.
                    ForEach(state.roots.prefix(Self.maxListedRoots), id: \.self) { root in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text((root as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                        }
                    }
                    if state.roots.count > Self.maxListedRoots {
                        Text("+\(state.roots.count - Self.maxListedRoots) more")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Add Folder…", action: addFolder)
                    .padding(.top, 2)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("SteamHub lives in the menu bar — look for the trophy.",
                      systemImage: "trophy.fill")
                Label("Starts automatically at login. Turn it off in the menu.",
                      systemImage: "power")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            HStack {
                Button("Show Me One", action: playSample)
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            if state.scanning {
                ProgressView().controlSize(.small)
                Text("Scanning for repositories…").font(.system(size: 13))
            } else if state.repoCount == 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No repositories found").font(.system(size: 13, weight: .medium))
                    Text("Add the folder where you keep your clones.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Watching ^[\(state.repoCount) repository](inflect: true)")
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan Folder"
        panel.message = "Pick the folder that holds your cloned repositories."
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }

        if !Settings.scanRoots.contains(path) { Settings.scanRoots.append(path) }
        state.refreshRoots()
        state.scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            RepoWatcher.shared.reloadRepos()
            RepoWatcher.shared.checkNow()
        }
    }

    private func playSample() {
        ToastPresenter.shared.show(title: "octocat",
                                   body: "Refactor the notification queue so overlapping pushes stack cleanly")
    }

    private func done() {
        NSApp.keyWindow?.close()
    }
}
