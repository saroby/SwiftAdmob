import Foundation
import UIKit

// MARK: - Mobile Ads bridge

@MainActor
public protocol MobileAdsBridge: AnyObject {
    var isStarted: Bool { get }
    func start() async
    func updateRequestConfiguration(testDeviceIdentifiers: [String])
}

// MARK: - Consent bridge

public struct AdmobConsentSnapshot: Sendable, Hashable {
    public let canRequestAds: Bool
    public let privacyOptionsRequired: Bool

    public init(canRequestAds: Bool, privacyOptionsRequired: Bool) {
        self.canRequestAds = canRequestAds
        self.privacyOptionsRequired = privacyOptionsRequired
    }
}

@MainActor
public protocol ConsentBridge: AnyObject {
    var snapshot: AdmobConsentSnapshot { get }

    func requestConsentInfoUpdate(debugSettings: AdmobConsentDebugSettings?) async throws
    func presentRequiredFormIfNeeded(from viewController: UIViewController) async throws
    func presentPrivacyOptionsForm(from viewController: UIViewController) async throws
    func reset()
}
