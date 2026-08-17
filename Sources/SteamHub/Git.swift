import Foundation

enum Git {
    /// Everything that could make git block on a terminal prompt is disabled, and the
    /// process is killed if it outlives `timeout` — a hung fetch must not stall the poll loop.
    private static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        e["GIT_TERMINAL_PROMPT"] = "0"
        e["GIT_ASKPASS"] = "/usr/bin/false"
        e["SSH_ASKPASS"] = "/usr/bin/false"
        e["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        e["GIT_CONFIG_NOSYSTEM"] = "0"
        e["LC_ALL"] = "C"
        return e
    }()

    @discardableResult
    static func run(_ args: [String], in repo: String, timeout: TimeInterval = 45) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo] + args
        p.environment = env

        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        do { try p.run() } catch { return (-1, "") }

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func isRepo(_ path: String) -> Bool {
        run(["rev-parse", "--git-dir"], in: path, timeout: 5).status == 0
    }

    /// Preferred remote for a repo: `origin` when it exists, otherwise the first one.
    static func primaryRemote(of repo: String) -> String? {
        let r = run(["remote"], in: repo, timeout: 10)
        guard r.status == 0 else { return nil }
        let names = r.out.split(separator: "\n").map(String.init)
        return names.contains("origin") ? "origin" : names.first
    }
}
