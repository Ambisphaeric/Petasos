import Foundation
import PetasosCore

/// Subscribes to a hermes run's SSE event stream and yields typed `RunEvent`s.
///
/// The async stream finishes when the server closes the connection or the
/// consumer breaks out of the for-await loop. If the consumer cancels the parent
/// Task, the underlying URL load is also cancelled.
public enum RunEventStream {
    public static func subscribe(
        runID: String,
        endpoint: RunsEndpoint,
        decoder: RunEventDecoder = .init(),
        session: URLSession? = nil
    ) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let urlSession = session ?? Self.makeStreamingSession()
                do {
                    let request = try endpoint.eventsRequest(runID: runID)
                    let (bytes, response) = try await urlSession.bytes(for: request)
                    try Self.validate(response: response)

                    var parser = SSEParser()
                    var chunk: [UInt8] = []
                    chunk.reserveCapacity(1024)
                    var totalBytes = 0

                    // Drain bytes by hand: AsyncLineSequence's grapheme-aware splitting
                    // and internal buffering don't play well with SSE on aiohttp.
                    // SSEParser already knows how to handle CR/LF/CRLF at the byte level.
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        totalBytes += 1
                        chunk.append(byte)
                        // Flush on LF — every SSE field and the event-terminator end in LF.
                        if byte == 0x0A {
                            let events = parser.feed(Data(chunk))
                            chunk.removeAll(keepingCapacity: true)
                            for ev in events {
                                continuation.yield(decoder.decode(ev))
                            }
                        }
                    }
                    if !chunk.isEmpty {
                        let events = parser.feed(Data(chunk))
                        for ev in events {
                            continuation.yield(decoder.decode(ev))
                        }
                    }
                    if totalBytes == 0 {
                        continuation.finish(throwing: HermesError.notReachable(underlying: "Stream closed before yielding any data."))
                    } else {
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch let err as HermesError {
                    continuation.finish(throwing: err)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .timedOut {
                    continuation.finish(throwing: HermesError.timeout)
                } catch {
                    continuation.finish(throwing: HermesError.notReachable(underlying: error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streaming-friendly URLSession config: caching off, generous timeouts so long-running
    /// tool calls don't trip the per-packet timeout, no waiting for connectivity.
    private static func makeStreamingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60 * 30   // 30min per packet — tool calls can be slow
        config.timeoutIntervalForResource = 60 * 60  // 1h overall
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HermesError.notReachable(underlying: "Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw HermesError.unauthorized
        case 403: throw HermesError.forbidden
        case 404: throw HermesError.notFound(path: http.url?.path ?? "")
        default: throw HermesError.server(status: http.statusCode, message: nil)
        }
    }
}
