import Foundation
import PetasosCore

/// Probes likely local hermes-agent locations during onboarding so users on the
/// same machine as their hermes instance don't have to type URLs.
public struct AutoDiscover: Sendable {
    public struct Candidate: Sendable, Equatable, Identifiable {
        public let id = UUID()
        public let url: URL
        public let label: String
        public let platform: String?
    }

    /// Default candidate URLs to probe in order. 8642 is hermes-agent's default port.
    public static let defaultCandidates: [URL] = [
        URL(string: "http://127.0.0.1:8642")!,
        URL(string: "http://localhost:8642")!,
    ]

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 1.5) {
        self.session = session
        self.timeout = timeout
    }

    /// Probe the supplied URLs concurrently and return whichever respond with a healthy hermes platform.
    /// Order in the returned array is preserved relative to the input.
    public func probe(_ urls: [URL] = defaultCandidates) async -> [Candidate] {
        await withTaskGroup(of: (Int, Candidate?).self) { group in
            for (idx, url) in urls.enumerated() {
                group.addTask { (idx, await self.probeOne(url)) }
            }
            var indexed: [(Int, Candidate)] = []
            for await (idx, candidate) in group {
                if let candidate { indexed.append((idx, candidate)) }
            }
            return indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    private func probeOne(_ url: URL) async -> Candidate? {
        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let status = try? JSONDecoder().decode(HealthStatus.self, from: data)
            guard let status, status.isOK else { return nil }
            return Candidate(url: url, label: url.host ?? url.absoluteString, platform: status.platform)
        } catch {
            return nil
        }
    }
}
