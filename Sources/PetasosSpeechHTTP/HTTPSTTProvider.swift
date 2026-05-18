import Foundation
import PetasosCore
import PetasosSpeech

/// STT backed by an OpenAI-compatible /v1/audio/transcriptions endpoint (the mac-speech-services sidecar).
///
/// HTTP STT is batch, not streaming: we accumulate every audio frame from the input
/// stream into a single buffer, encode WAV when the stream finishes, post, and yield
/// the final transcript. PTT works naturally (mic stops on release → batch posts).
public final class HTTPSTTProvider: SpeechRecognizer, @unchecked Sendable {
    public static let identifier: String = "http_stt"
    public static let displayName: String = "HTTP sidecar (OpenAI-compatible)"

    public var isReady: Bool { get async { true } }

    private let endpointURL: URL
    private let bearer: String?
    private let session: URLSession

    public init(endpointURL: URL, bearer: String? = nil, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.bearer = bearer
        self.session = session
    }

    public func prepare() async throws {}
    public func shutdown() async {}

    public func recognize(audio: AsyncStream<AudioFrame>) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var samples: [Float] = []
                samples.reserveCapacity(16_000 * 10)
                var sampleRate = 16_000

                for await frame in audio {
                    if Task.isCancelled { break }
                    samples.append(contentsOf: frame.samples)
                    sampleRate = frame.sampleRate
                }

                if Task.isCancelled {
                    continuation.finish()
                    return
                }
                guard !samples.isEmpty else {
                    continuation.finish()
                    return
                }

                do {
                    let wav = WAV.encode(samplesFloat32: samples, sampleRate: sampleRate)
                    let text = try await self.postTranscription(wav: wav)
                    continuation.yield(Transcript(text: text, isFinal: true, confidence: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func postTranscription(wav: Data) async throws -> String {
        let url = endpointURL.appendingPathComponent("v1/audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendForm(boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", payload: wav)
        body.appendFormField(boundary: boundary, name: "model", value: "whisper-1")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Petasos.HTTPSTT", code: code, userInfo: [NSLocalizedDescriptionKey: body])
        }
        struct Response: Codable { let text: String }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.text
    }
}

private extension Data {
    mutating func appendForm(boundary: String, name: String, filename: String, contentType: String, payload: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(payload)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendFormField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }
}
