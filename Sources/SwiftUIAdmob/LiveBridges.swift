import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

// MARK: - Live Mobile Ads bridge

@MainActor
public final class LiveMobileAdsBridge: MobileAdsBridge {
    public private(set) var isStarted: Bool = false

    public init() {}

    public func start() async {
        if isStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in
                continuation.resume()
            }
        }
        isStarted = true
    }

    public func updateRequestConfiguration(testDeviceIdentifiers: [String]) {
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIdentifiers
    }
}

// MARK: - Live consent bridge

@MainActor
public final class LiveConsentBridge: ConsentBridge {
    public init() {}

    public var snapshot: AdmobConsentSnapshot {
        AdmobConsentSnapshot(
            canRequestAds: ConsentInformation.shared.canRequestAds,
            privacyOptionsRequired: ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        )
    }

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
