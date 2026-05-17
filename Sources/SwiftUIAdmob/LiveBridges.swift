import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

// MARK: - Live Mobile Ads bridge

/// Production ``MobileAdsBridge`` that delegates to `MobileAds.shared`.
///
/// Owns the started/not-started flag. Once ``start()`` returns, subsequent
/// calls no-op.
@MainActor
public final class LiveMobileAdsBridge: MobileAdsBridge {
    /// `true` after `MobileAds.shared.start` has invoked its completion handler.
    public private(set) var isStarted: Bool = false

    /// Create the live bridge. No SDK work happens until ``start()`` is called.
    public init() {}

    /// Start the Google Mobile Ads SDK. Idempotent.
    ///
    /// Returns when the SDK's start completion fires. The bridge does not
    /// inspect the SDK initialization status — callers gate on ``isStarted``.
    public func start() async {
        if isStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in
                continuation.resume()
            }
        }
        isStarted = true
    }

    /// Forward test device identifiers to `MobileAds.shared.requestConfiguration`.
    public func updateRequestConfiguration(testDeviceIdentifiers: [String]) {
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
    }
}

// MARK: - Live consent bridge

/// Production ``ConsentBridge`` that delegates to `ConsentInformation.shared`
/// and `ConsentForm`.
///
/// Translates UMP completion-handler APIs into `async`/`await`. Errors thrown
/// from the underlying SDK propagate to the caller untouched.
@MainActor
public final class LiveConsentBridge: ConsentBridge {
    /// Create the live bridge.
    public init() {}

    /// Snapshot read from `ConsentInformation.shared` on each access.
    public var snapshot: AdmobConsentSnapshot {
        AdmobConsentSnapshot(
            canRequestAds: ConsentInformation.shared.canRequestAds,
            privacyOptionsRequired: ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        )
    }

    /// Refresh consent information from the UMP service.
    /// - Throws: Any error reported by `ConsentInformation.requestConsentInfoUpdate`.
    public func requestConsentInfoUpdate(debugSettings: AdmobConsentDebugSettings?) async throws {
        let params = RequestParameters()
        if let debugSettings {
            let debug = DebugSettings()
            debug.geography = mapGeography(debugSettings.geography)
            debug.testDeviceIdentifiers = debugSettings.testDeviceIdentifiers
            params.debugSettings = debug
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: params) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Present the consent form if UMP says one is required, then return.
    /// - Throws: Any error reported by `ConsentForm.loadAndPresentIfRequired`.
    public func presentRequiredFormIfNeeded(from viewController: UIViewController) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentForm.loadAndPresentIfRequired(from: viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Present the privacy options form on demand.
    /// - Throws: Any error reported by `ConsentForm.presentPrivacyOptionsForm`.
    public func presentPrivacyOptionsForm(from viewController: UIViewController) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Reset stored UMP consent state. Intended for DEBUG use only.
    public func reset() {
        ConsentInformation.shared.reset()
    }

    private func mapGeography(_ geography: AdmobConsentDebugSettings.Geography) -> DebugGeography {
        switch geography {
        case .disabled: return .disabled
        case .eea: return .EEA
        case .notEEA: return .other
        case .regulatedUSState: return .regulatedUSState
        case .other: return .other
        }
    }
}
