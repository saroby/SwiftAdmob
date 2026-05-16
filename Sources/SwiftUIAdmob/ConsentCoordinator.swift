import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class AdmobConsentCoordinator {
    public private(set) var snapshot: AdmobConsentSnapshot
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastErrorMessage: String?

    private let bridge: ConsentBridge
    private let eventSink: AdmobEventSink

    public init(bridge: ConsentBridge, eventSink: AdmobEventSink = .none) {
        self.bridge = bridge
        self.eventSink = eventSink
        self.snapshot = bridge.snapshot
    }

    public var canRequestAds: Bool { snapshot.canRequestAds }
    public var isPrivacyOptionsRequired: Bool { snapshot.privacyOptionsRequired }

    /// Refresh consent information. If a `viewController` is provided and a consent
    /// form is required, it is presented before returning.
    ///
    /// Failure to refresh is recorded in ``lastErrorMessage`` but does not throw —
    /// callers should still inspect ``canRequestAds`` before requesting ads.
    public func refresh(
        from viewController: UIViewController? = nil,
        debugSettings: AdmobConsentDebugSettings? = nil
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            syncFromBridge()
        }
        do {
            try await bridge.requestConsentInfoUpdate(debugSettings: debugSettings)
            if let viewController {
                try await bridge.presentRequiredFormIfNeeded(from: viewController)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.diagnosticWarning("Consent refresh failed: \(error.localizedDescription)"))
        }
    }

    public func presentPrivacyOptions(from viewController: UIViewController) async {
        do {
            try await bridge.presentPrivacyOptionsForm(from: viewController)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.diagnosticWarning("Privacy options form failed: \(error.localizedDescription)"))
        }
        syncFromBridge()
    }

    public func reset() {
        bridge.reset()
        syncFromBridge()
    }

    private func syncFromBridge() {
        let next = bridge.snapshot
        let changed = next != snapshot
        snapshot = next
        if changed {
            eventSink.send(.consentUpdated(
                canRequestAds: next.canRequestAds,
                privacyOptionsRequired: next.privacyOptionsRequired
            ))
        }
    }
}
