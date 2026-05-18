import AVFoundation
import Foundation

/// Microphone permission wrapper. Requesting access requires the app's Info.plist to
/// have `NSMicrophoneUsageDescription`; without it, the request returns `.denied`
/// without showing a prompt. See Sources/PetasosApp/Resources/Info.plist.
public enum AudioPermissions {
    public enum Status: Sendable, Equatable {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    public static func current() -> Status {
        let av = AVCaptureDevice.authorizationStatus(for: .audio)
        return map(av)
    }

    public static func request() async -> Status {
        if case .notDetermined = current() {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return current()
    }

    private static func map(_ av: AVAuthorizationStatus) -> Status {
        switch av {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}
