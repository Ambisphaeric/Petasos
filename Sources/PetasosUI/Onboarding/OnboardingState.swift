import Foundation
import PetasosCore
import PetasosHermes

@MainActor
public final class OnboardingState: ObservableObject {
    public enum Step: Equatable {
        case welcome
        case serverConfig
        case auth(baseURL: URL)
        case probe(baseURL: URL, bearer: String)
        case complete(profile: ServerProfile)
    }

    public struct ProbeResult: Equatable {
        public var capabilities: Capabilities
        public var models: [HermesModel]
        public var detailedHealth: DetailedHealth?
    }

    @Published public var step: Step = .welcome
    @Published public var candidates: [AutoDiscover.Candidate] = []
    @Published public var isDiscovering = false
    @Published public var manualURLString: String = ""
    @Published public var bearerToken: String = ""
    @Published public var rememberInKeychain: Bool = true
    @Published public var probeResult: ProbeResult?
    @Published public var probeInFlight: Bool = false
    @Published public var errorMessage: String?
    @Published public var selectedModelID: String?

    public var onComplete: ((ServerProfile, String) -> Void)?

    public init() {}

    public func startDiscovery() async {
        isDiscovering = true
        defer { isDiscovering = false }
        candidates = await AutoDiscover().probe()
    }

    public func pick(candidate: AutoDiscover.Candidate) {
        manualURLString = candidate.url.absoluteString
        step = .auth(baseURL: candidate.url)
    }

    public func confirmManualURL() {
        guard let url = URL(string: manualURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http" || url.scheme == "https" else {
            errorMessage = "Enter a URL starting with http:// or https://"
            return
        }
        errorMessage = nil
        step = .auth(baseURL: url)
    }

    public func submitBearer() {
        guard case .auth(let url) = step else { return }
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Bearer token required."
            return
        }
        errorMessage = nil
        step = .probe(baseURL: url, bearer: token)
    }

    public func runProbe() async {
        guard case .probe(let url, let bearer) = step else { return }
        probeInFlight = true
        errorMessage = nil
        defer { probeInFlight = false }

        let client = HermesClient(baseURL: url, bearerToken: bearer)
        do {
            async let caps = client.capabilities()
            async let models = client.models()
            async let detailed = client.detailedHealth()
            let detailedSafe = try? await detailed
            let result = try await ProbeResult(
                capabilities: caps,
                models: models,
                detailedHealth: detailedSafe
            )
            self.probeResult = result
            self.selectedModelID = result.models.first?.id ?? result.capabilities.model
        } catch let err as HermesError {
            errorMessage = err.errorDescription ?? "Probe failed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func finalize(keychainAccount: String) {
        guard case .probe(let url, let bearer) = step,
              let result = probeResult else { return }
        let profile = ServerProfile(
            nickname: url.host ?? url.absoluteString,
            baseURL: url,
            keychainAccount: keychainAccount,
            preferredModel: selectedModelID,
            lastCapabilities: result.capabilities,
            lastVerifiedAt: .init()
        )
        onComplete?(profile, bearer)
        step = .complete(profile: profile)
    }

    public func goBack() {
        switch step {
        case .welcome: return
        case .serverConfig: step = .welcome
        case .auth: step = .serverConfig
        case .probe(let url, _): step = .auth(baseURL: url)
        case .complete: return
        }
    }
}
