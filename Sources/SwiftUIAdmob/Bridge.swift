import Foundation
import UIKit

// MARK: - Mobile Ads bridge

/// Indirection over `MobileAds.shared` so tests can avoid live Google ad requests.
///
/// The live implementation is ``LiveMobileAdsBridge``. Substitute a fake
/// conforming to this protocol when constructing ``AdmobBootstrapper`` in tests.
@MainActor
public protocol MobileAdsBridge: AnyObject {
    /// `true` once the underlying SDK `start` completion has fired.
    var isStarted: Bool { get }
    /// Start the Google Mobile Ads SDK. Implementations must be safe to call
    /// multiple times; subsequent calls should no-op once started.
    func start() async
    /// Forward test device identifiers to the SDK's request configuration.
    /// - Parameter testDeviceIdentifiers: Device IDs that should receive test ads.
    func updateRequestConfiguration(testDeviceIdentifiers: [String])
}

// MARK: - Consent bridge

/// Snapshot of the UMP consent state at one point in time.
///
/// Re-read from the bridge after any state-mutating call (consent form
/// presentation, privacy options form, reset) — UMP state changes only at
/// these explicit moments.
public struct AdmobConsentSnapshot: Sendable, Hashable {
    /// `true` when the SDK reports consent is sufficient to request ads.
    public let canRequestAds: Bool
    /// `true` when the app must expose a "Privacy options" entry point to the user.
    public let privacyOptionsRequired: Bool

    /// Create a snapshot. Typically constructed by a ``ConsentBridge`` implementation.
    public init(canRequestAds: Bool, privacyOptionsRequired: Bool) {
        self.canRequestAds = canRequestAds
        self.privacyOptionsRequired = privacyOptionsRequired
    }
}

/// Indirection over `UserMessagingPlatform` so tests can simulate consent flows
/// without presenting real UMP forms.
///
/// The live implementation is ``LiveConsentBridge``. Substitute a fake when
/// constructing ``AdmobConsentCoordinator`` in tests.
@MainActor
public protocol ConsentBridge: AnyObject {
    /// Current consent snapshot. Implementations should read from the SDK on each access.
    var snapshot: AdmobConsentSnapshot { get }

    /// Refresh consent information from the UMP service.
    /// - Parameter debugSettings: Optional debug overrides for geography and test devices.
    func requestConsentInfoUpdate(debugSettings: AdmobConsentDebugSettings?) async throws
    /// Present the consent form if UMP determines one is required.
    /// - Parameter viewController: Presenter for the modal form.
    func presentRequiredFormIfNeeded(from viewController: UIViewController) async throws
    /// Present the privacy options form on demand. Call from a "Manage privacy" menu item.
    /// - Parameter viewController: Presenter for the modal form.
    func presentPrivacyOptionsForm(from viewController: UIViewController) async throws
    /// Reset stored consent state. Useful in DEBUG to re-trigger the consent flow.
    func reset()
}
