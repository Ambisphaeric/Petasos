import Foundation

/// Scans the standard HuggingFace cache directory for installed model snapshots.
/// We use this to populate the Settings → Speech → Model dropdown with whatever the
/// user already has on disk — no auto-download, no surprise network calls at launch.
///
/// HF cache layout:
///   ~/.cache/huggingface/hub/
///     models--<org>--<name>/
///       refs/main                 (file with the commit sha)
///       snapshots/<sha>/...       (the actual model files, as symlinks into blobs/)
///       blobs/<hash>              (real bytes)
public struct HuggingFaceCacheScanner: Sendable {
    public struct InstalledModel: Sendable, Identifiable, Equatable, Hashable {
        public let id: String          // canonical HF repo id, e.g. "mlx-community/parakeet-tdt_ctc-110m"
        public let displayName: String // last path component for UI
        public let snapshotURL: URL    // ~/.cache/.../snapshots/<sha>
        public let sizeBytes: Int64
        public let files: [String]     // filenames in the snapshot

        public var hasSafetensors: Bool { files.contains(where: { $0.hasSuffix(".safetensors") }) }
        public var hasConfig: Bool { files.contains("config.json") }
        public var isValid: Bool { hasConfig && hasSafetensors }
    }

    public let cacheRoot: URL

    public init(cacheRoot: URL? = nil) {
        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.cacheRoot = home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        }
    }

    /// Return every installed model whose canonical id matches `pattern`.
    /// Pattern uses simple glob-style with `*`: `mlx-community/parakeet-*` matches
    /// `mlx-community/parakeet-tdt_ctc-110m`, etc.
    public func scan(matching pattern: String) -> [InstalledModel] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        let regex = makeRegex(pattern: pattern)
        var results: [InstalledModel] = []
        for entry in entries {
            let folderName = entry.lastPathComponent
            guard folderName.hasPrefix("models--") else { continue }
            let canonicalID = canonicalRepoID(from: folderName)
            guard regex.firstMatch(in: canonicalID, range: NSRange(canonicalID.startIndex..., in: canonicalID)) != nil else {
                continue
            }
            if let installed = scanModel(at: entry, repoID: canonicalID) {
                results.append(installed)
            }
        }
        return results.sorted { $0.id < $1.id }
    }

    private func scanModel(at modelRoot: URL, repoID: String) -> InstalledModel? {
        let fm = FileManager.default
        let snapshotsRoot = modelRoot.appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshots = try? fm.contentsOfDirectory(at: snapshotsRoot, includingPropertiesForKeys: [.contentModificationDateKey]),
              let snapshot = snapshots.max(by: { (a, b) in
                  let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                  return aDate < bDate
              }) else {
            return nil
        }
        let files: [String]
        if let entries = try? fm.contentsOfDirectory(atPath: snapshot.path) {
            files = entries
        } else {
            files = []
        }
        let size = directorySize(modelRoot)
        let name = repoID.split(separator: "/").last.map(String.init) ?? repoID
        return InstalledModel(
            id: repoID,
            displayName: name,
            snapshotURL: snapshot,
            sizeBytes: size,
            files: files
        )
    }

    private func canonicalRepoID(from folderName: String) -> String {
        // "models--mlx-community--Kokoro-82M-bf16" → "mlx-community/Kokoro-82M-bf16"
        let stripped = String(folderName.dropFirst("models--".count))
        let parts = stripped.components(separatedBy: "--")
        if parts.count >= 2 {
            return parts[0] + "/" + parts[1...].joined(separator: "--")
        }
        return stripped
    }

    private func makeRegex(pattern: String) -> NSRegularExpression {
        // Convert glob (`*`) to regex. Escape everything else.
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return (try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]))
            ?? (try! NSRegularExpression(pattern: ".*"))
    }

    private func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
