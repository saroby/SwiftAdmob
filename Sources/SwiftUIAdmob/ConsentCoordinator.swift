import Foundation
import Observation
import UIKit

/// Observable wrapper around UMP that tracks the latest consent snapshot and
/// coordinates form presentation.
///
/// Owned by ``AdmobBootstrapper``. Callers should treat ``canRequestAds`` as
/// the authoritative consent gate and never request ads while ``isRefreshing``
/// is `true`.
@MainActor
@Observable
public final class AdmobConsentCoordinator {
    /// Latest snapshot read from the underlying bridge. Updates after each
    /// state-mutating call.
    public private(set) var snapshot: AdmobConsentSnapshot
    /// `true` while a ``refresh(from:debugSettings:)`` call is in flight.
    public private(set) var isRefreshing: Bool = false
    /// Localized description of the last error from refresh or privacy options,
    /// or `nil` after a successful operation.
    public private(set) var lastErrorMessage: String?

    private let bridge: ConsentBridge
    private let eventSink: AdmobEventSink

    /// Create a coordinator over the given consent bridge.
    /// - Parameters:
    ///   - bridge: Live or fake UMP bridge.
    ///   - eventSink: Sink for consent and diagnostic events.
    public init(bridge: ConsentBridge, eventSink: AdmobEventSink = .none) {
        self.bridge = bridge
        self.eventSink = eventSink
        self.snapshot = bridge.snapshot
    }

    /// `true` when consent permits ad requests. Convenience over ``snapshot``.
    public var canRequestAds: Bool { snapshot.canRequestAds }
    /// `true` when the host app must expose a "Privacy options" entry point.
    public var isPrivacyOptionsRequired: Bool { snapshot.privacyOptionsRequired }

    /// Refresh consent information, optionally presenting a required consent form.
    ///
    /// - Parameters:
    ///   - viewController: When non-nil and UMP requires a form, the form is
    ///     presented from this controller before the call returns.
    ///   - debugSettings: Optional debug overrides forwarded to UMP.
    ///
    /// - Important: This method does **not** throw. Failures are stored in
    ///   ``lastErrorMessage`` and emitted as a `.diagnosticWarning` event.
    ///   Callers must inspect ``canRequestAds`` (or
    ///   ``AdmobBootstrapper/canRequestAds``) before requesting ads.
    /// - Note: Calling this while a refresh is already in flight is a no-op.
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

    /// Present the privacy options form from a host-app entry point.
    ///
    /// Call from a "Manage privacy" menu item when ``isPrivacyOptionsRequired``
    /// is `true`. After the user grants consent, call
    /// ``AdmobBootstrapper/reconcile()`` to complete deferred SDK start.
    /// - Parameter viewController: Presenter for the modal form.
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

    /// Reset stored consent state via the bridge. Intended for DEBUG use only.
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
