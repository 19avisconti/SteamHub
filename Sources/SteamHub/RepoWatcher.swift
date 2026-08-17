import Foundation

struct PushEvent {
    let repoPath: String
    let repoName: String
    let branch: String
    let author: String
    let message: String
    let sha: String
}

/// Polls every watched repo's remote on a timer. A change to any remote-tracking ref
/// is a "push"; the new commits behind it are read straight out of git.
final class RepoWatcher {
    static let shared = RepoWatcher()

    var onEvent: ((PushEvent) -> Void)?
    var onReposChanged: (() -> Void)?

    /// Most commits reported for a single ref update, so a 200-commit branch
    /// merge can't turn into a 200-toast queue.
    private let maxCommitsPerRef = 5

    private let queue = DispatchQueue(label: "com.visconti.SteamHub.watcher")
    private var timer: DispatchSourceTimer?
    private var isChecking = false

    /// repoPath -> (refName -> sha). A repo absent here has never been polled, so its
    /// first poll only records a baseline instead of announcing every existing branch.
    /// Only touched on `queue`.
    private var baseline: [String: [String: String]] = [:]

    /// Read from the main thread when building the menu, written after a scan.
    private let lock = NSLock()
    private var _repos: [String] = []
    var repos: [String] { lock.withLock { _repos } }

    // MARK: - Lifecycle

    func start() {
        restartTimer()
        queue.async { [weak self] in
            self?.reloadRepos()
            self?.check()
        }
    }

    func restartTimer() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Settings.pollInterval, repeating: Settings.pollInterval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
    }

    func checkNow() {
        queue.async { [weak self] in self?.check() }
    }

    // MARK: - Repo list

    /// Union of the scan roots and manually added repos. Blocking — never call on the main thread.
    func reloadRepos() {
        let scanned = RepoScanner.scan(roots: Settings.scanRoots)
        let manual = Settings.manualRepos.filter { FileManager.default.fileExists(atPath: $0 + "/.git") }
        let all = Set(scanned).union(manual).sorted()

        lock.withLock { _repos = all }
        queue.async { self.baseline = self.baseline.filter { all.contains($0.key) } }
        DispatchQueue.main.async { self.onReposChanged?() }
    }

    var activeRepos: [String] {
        let muted = Settings.disabledRepos
        return repos.filter { !muted.contains($0) }
    }

    // MARK: - Polling

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        for repo in activeRepos {
            for event in poll(repo) {
                DispatchQueue.main.async { self.onEvent?(event) }
            }
        }
    }

    private func poll(_ repo: String) -> [PushEvent] {
        guard let remote = Git.primaryRemote(of: repo) else { return [] }

        // A failed fetch (offline, auth, deleted remote) just means no news this cycle.
        guard Git.run(["fetch", "--prune", "--quiet", remote], in: repo).status == 0 else { return [] }

        let current = remoteRefs(repo, remote: remote)
        guard let previous = baseline[repo] else {
            baseline[repo] = current   // first sight: record, announce nothing
            return []
        }
        baseline[repo] = current

        let name = URL(fileURLWithPath: repo).lastPathComponent
        var events: [PushEvent] = []
        var seen = Set<String>()   // a commit landing on two branches is still one push

        let prefix = "refs/remotes/\(remote)/"
        for (ref, sha) in current.sorted(by: { $0.key < $1.key }) where previous[ref] != sha {
            let branch = ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
            for commit in commits(repo, from: previous[ref], to: sha) where !seen.contains(commit.sha) {
                seen.insert(commit.sha)
                events.append(PushEvent(repoPath: repo, repoName: name, branch: branch,
                                        author: commit.author, message: commit.message, sha: commit.sha))
            }
        }
        return events
    }

    private func remoteRefs(_ repo: String, remote: String) -> [String: String] {
        // Full refnames, not `:short` — git shortens `refs/remotes/origin/HEAD` to plain
        // `origin`, which would slip past the filter below and mislabel every event.
        let r = Git.run(["for-each-ref", "--format=%(objectname)%09%(refname)",
                         "refs/remotes/\(remote)"], in: repo, timeout: 15)
        guard r.status == 0 else { return [:] }

        var refs: [String: String] = [:]
        for line in r.out.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let ref = String(parts[1])
            if ref == "refs/remotes/\(remote)/HEAD" { continue }   // a symref, not a branch
            refs[ref] = String(parts[0])
        }
        return refs
    }

    private func commits(_ repo: String, from old: String?, to new: String)
        -> [(sha: String, author: String, message: String)] {
        let fmt = "--format=%H%x1f%an%x1f%s"
        var r = (status: Int32(-1), out: "")
        if let old {
            // Fails after a force-push that orphaned `old`; fall back to just the tip.
            r = Git.run(["log", fmt, "-n", "\(maxCommitsPerRef)", "\(old)..\(new)"], in: repo, timeout: 15)
        }
        if r.status != 0 || r.out.isEmpty {
            r = Git.run(["log", fmt, "-n", "1", new], in: repo, timeout: 15)
        }
        guard r.status == 0 else { return [] }

        // git log is newest-first; reverse so a multi-commit push toasts chronologically.
        return r.out.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 3 else { return nil }
            return (f[0], f[1], f[2])
        }.reversed()
    }
}
