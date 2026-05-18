import Foundation

/// Stable identifier under which the hermes bearer token is written in Keychain.
/// Kept in UI module so the onboarding window can pass it into OnboardingState.finalize
/// without depending on the App module.
public enum KeychainAccount {
    public static let `default` = "hermes-default"
}
