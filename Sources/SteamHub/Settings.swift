import Foundation

/// UserDefaults-backed configuration. Repos are stored as absolute paths.
enum Settings {
    private static let d = UserDefaults.standard

    /// Folders scanned for `.git` directories.
    static var scanRoots: [String] {
        get { d.array(forKey: "scanRoots") as? [String] ?? defaultScanRoots }
        set { d.set(newValue, forKey: "scanRoots") }
    }

    /// Repos added by hand that live outside any scan root.
    static var manualRepos: [String] {
        get { d.array(forKey: "manualRepos") as? [String] ?? [] }
        set { d.set(newValue, forKey: "manualRepos") }
    }

    /// Repos the user has explicitly muted.
    static var disabledRepos: Set<String> {
        get { Set(d.array(forKey: "disabledRepos") as? [String] ?? []) }
        set { d.set(Array(newValue), forKey: "disabledRepos") }
    }

    /// Set once, the first time the app decides the launch-at-login default. Without it,
    /// turning the setting off would be undone on the next launch.
    static var didConfigureLaunchAtLogin: Bool {
        get { d.bool(forKey: "didConfigureLaunchAtLogin") }
        set { d.set(newValue, forKey: "didConfigureLaunchAtLogin") }
    }

    static var pollInterval: TimeInterval {
        get { let v = d.double(forKey: "pollInterval"); return v > 0 ? v : 60 }
        set { d.set(newValue, forKey: "pollInterval") }
    }

    static var defaultScanRoots: [String] {
        let home = NSHomeDirectory()
        return ["Documents", "Developer", "Projects", "Desktop", "src", "code"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }
}
