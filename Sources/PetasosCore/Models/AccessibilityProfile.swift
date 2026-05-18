import Foundation

public struct AccessibilityProfile: Codable, Sendable, Equatable {
    public var enforceHighContrast: Bool
    public var minimumOpacity: Double          // 0.0–1.0; floor when respectReduceTransparency triggers
    public var minimumFontPointSize: Double
    public var respectReduceMotion: Bool
    public var respectReduceTransparency: Bool
    public var respectIncreaseContrast: Bool
    public var announceStateChanges: Bool      // TTS-announce listening/speaking transitions

    public init(
        enforceHighContrast: Bool,
        minimumOpacity: Double,
        minimumFontPointSize: Double,
        respectReduceMotion: Bool,
        respectReduceTransparency: Bool,
        respectIncreaseContrast: Bool,
        announceStateChanges: Bool
    ) {
        self.enforceHighContrast = enforceHighContrast
        self.minimumOpacity = minimumOpacity
        self.minimumFontPointSize = minimumFontPointSize
        self.respectReduceMotion = respectReduceMotion
        self.respectReduceTransparency = respectReduceTransparency
        self.respectIncreaseContrast = respectIncreaseContrast
        self.announceStateChanges = announceStateChanges
    }

    public static let standard = AccessibilityProfile(
        enforceHighContrast: false,
        minimumOpacity: 0.0,
        minimumFontPointSize: 11,
        respectReduceMotion: true,
        respectReduceTransparency: true,
        respectIncreaseContrast: true,
        announceStateChanges: false
    )

    public static let accessibility = AccessibilityProfile(
        enforceHighContrast: true,
        minimumOpacity: 0.95,
        minimumFontPointSize: 18,
        respectReduceMotion: true,
        respectReduceTransparency: true,
        respectIncreaseContrast: true,
        announceStateChanges: true
    )
}
