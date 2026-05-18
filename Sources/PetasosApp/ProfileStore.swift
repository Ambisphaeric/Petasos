import Foundation
import PetasosCore

/// Persists the saved ServerProfile to disk as JSON.
/// Path: ~/Library/Application Support/Petasos/profile.json
@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: ServerProfile?
    private let url: URL
    private let logger: AppLogger

    init(logger: AppLogger) {
        self.logger = logger
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = support.appendingPathComponent("Petasos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("profile.json")
        self.profile = Self.load(from: url, logger: logger)
    }

    func save(_ profile: ServerProfile) {
        self.profile = profile
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(profile)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("ProfileStore.save failed: \(error)")
        }
    }

    func clear() {
        profile = nil
        try? FileManager.default.removeItem(at: url)
    }

    private static func load(from url: URL, logger: AppLogger) -> ServerProfile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ServerProfile.self, from: data)
        } catch {
            logger.error("ProfileStore.load failed: \(error)")
            return nil
        }
    }
}
