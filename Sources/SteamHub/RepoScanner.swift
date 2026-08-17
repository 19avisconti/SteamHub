import Foundation

enum RepoScanner {
    private static let skip: Set<String> = [
        "node_modules", "Library", "Pods", "vendor", "DerivedData", "Applications",
        ".build", ".venv", "venv", "target", "build", "dist", ".Trash", ".git",
    ]

    /// Depth-limited walk that stops descending as soon as a repo is found.
    static func scan(roots: [String], maxDepth: Int = 4) -> [String] {
        let fm = FileManager.default
        var found: Set<String> = []
        var frontier: [(path: String, depth: Int)] = roots.map { ($0, 0) }

        while let (path, depth) = frontier.popLast() {
            if fm.fileExists(atPath: path + "/.git") {
                found.insert(path)
                continue
            }
            guard depth < maxDepth,
                  let entries = try? fm.contentsOfDirectory(atPath: path) else { continue }
            for name in entries where !skip.contains(name) && !name.hasPrefix(".") {
                let child = path + "/" + name
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
                // Don't follow symlinks — they invite cycles and duplicate hits.
                let attrs = try? fm.attributesOfItem(atPath: child)
                if attrs?[.type] as? FileAttributeType == .typeSymbolicLink { continue }
                frontier.append((child, depth + 1))
            }
        }
        return found.sorted()
    }
}
