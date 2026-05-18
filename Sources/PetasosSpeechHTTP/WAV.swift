import Foundation

/// Minimal WAV encoder/decoder for the HTTP speech sidecar path.
///
/// Encoder: 16-bit PCM mono — what most OpenAI-compatible STT endpoints expect.
/// Decoder: handles 16-bit PCM and 32-bit Float WAV files produced by Kokoro/Coqui style services.
public enum WAV {
    public struct DecodedAudio: Sendable {
        public let samples: [Float]   // mono, normalized to [-1, 1]
        public let sampleRate: Int
    }

    // MARK: - Encode (Float32 mono → 16-bit PCM mono WAV)

    public static func encode(samplesFloat32: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let bytesPerSample: UInt32 = 2
        let numSamples = UInt32(samplesFloat32.count)
        let byteRate = UInt32(sampleRate) * bytesPerSample
        let blockAlign: UInt16 = UInt16(bytesPerSample)
        let dataSize = numSamples * bytesPerSample
        let chunkSize: UInt32 = 36 + dataSize

        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: chunkSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))           // fmt subchunk size
        data.append(littleEndian: UInt16(1))            // PCM
        data.append(littleEndian: UInt16(1))            // mono
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: UInt16(16))           // bits per sample
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)

        data.reserveCapacity(data.count + Int(dataSize))
        for f in samplesFloat32 {
            let clamped = max(-1.0, min(1.0, f))
            let s = Int16(clamped * 32767)
            data.append(littleEndian: s)
        }
        return data
    }

    // MARK: - Decode (WAV file → Float32 mono samples)

    public enum DecodeError: Error {
        case notRIFF
        case notWAVE
        case unsupportedFormat(Int)
    }

    public static func decode(_ data: Data) throws -> DecodedAudio {
        guard data.count >= 44 else { throw DecodeError.notRIFF }
        guard data[0..<4].elementsEqual("RIFF".utf8) else { throw DecodeError.notRIFF }
        guard data[8..<12].elementsEqual("WAVE".utf8) else { throw DecodeError.notWAVE }

        // Scan for "fmt " and "data" chunks (some encoders insert LIST/INFO between fmt and data).
        var cursor = 12
        var audioFormat: UInt16 = 0
        var channels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var dataRange: Range<Int>?

        while cursor + 8 <= data.count {
            let id = String(data: data.subdata(in: cursor..<cursor+4), encoding: .ascii) ?? ""
            let size = data.readU32(at: cursor + 4)
            let payloadStart = cursor + 8
            let payloadEnd = payloadStart + Int(size)
            if id == "fmt " {
                audioFormat = data.readU16(at: payloadStart)
                channels = data.readU16(at: payloadStart + 2)
                sampleRate = data.readU32(at: payloadStart + 4)
                bitsPerSample = data.readU16(at: payloadStart + 14)
            } else if id == "data" {
                dataRange = payloadStart..<min(payloadEnd, data.count)
                break
            }
            cursor = payloadEnd
        }

        guard let dataRange else { throw DecodeError.unsupportedFormat(0) }
        let raw = data.subdata(in: dataRange)
        let ch = Int(channels == 0 ? 1 : channels)

        var mono: [Float]
        switch (audioFormat, bitsPerSample) {
        case (1, 16):
            mono = decodeInt16(raw, channels: ch)
        case (3, 32):
            mono = decodeFloat32(raw, channels: ch)
        case (1, 8):
            mono = decodeInt8(raw, channels: ch)
        case (1, 24):
            mono = decodeInt24(raw, channels: ch)
        default:
            throw DecodeError.unsupportedFormat(Int(audioFormat) * 100 + Int(bitsPerSample))
        }
        return DecodedAudio(samples: mono, sampleRate: Int(sampleRate))
    }

    private static func decodeInt16(_ raw: Data, channels: Int) -> [Float] {
        let count = raw.count / 2
        var samples: [Float] = []
        samples.reserveCapacity(count / channels)
        let stride = channels * 2
        var i = 0
        while i + 1 < raw.count {
            let s = Int16(raw[i]) | (Int16(raw[i + 1]) << 8)
            samples.append(Float(s) / 32768.0)
            i += stride
        }
        return samples
    }

    private static func decodeInt8(_ raw: Data, channels: Int) -> [Float] {
        // 8-bit WAV is unsigned (0..255), centered at 128.
        var samples: [Float] = []
        samples.reserveCapacity(raw.count / channels)
        var i = 0
        while i < raw.count {
            samples.append((Float(raw[i]) - 128) / 128.0)
            i += channels
        }
        return samples
    }

    private static func decodeInt24(_ raw: Data, channels: Int) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(raw.count / (3 * channels))
        let stride = channels * 3
        var i = 0
        while i + 2 < raw.count {
            var v = Int32(raw[i]) | (Int32(raw[i + 1]) << 8) | (Int32(raw[i + 2]) << 16)
            if v & 0x00800000 != 0 { v |= ~0x00FFFFFF }
            samples.append(Float(v) / 8388608.0)
            i += stride
        }
        return samples
    }

    private static func decodeFloat32(_ raw: Data, channels: Int) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(raw.count / 4 / channels)
        let stride = channels * 4
        var i = 0
        while i + 3 < raw.count {
            let b: UInt32 = UInt32(raw[i])
                | (UInt32(raw[i + 1]) << 8)
                | (UInt32(raw[i + 2]) << 16)
                | (UInt32(raw[i + 3]) << 24)
            samples.append(Float(bitPattern: b))
            i += stride
        }
        return samples
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }

    func readU16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readU32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
