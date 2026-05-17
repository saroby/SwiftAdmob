import Foundation
import Observation
import UIKit
import GoogleMobileAds

/// One-shot interstitial ad controller with async load/present.
///
/// Lifecycle: ``load()`` → ``present(from:)`` → discarded. After a successful
/// present (or any failure), the underlying ad object is released and
/// ``isReady`` is set to `false`. Call ``load()`` again before the next
/// ``present(from:)`` — or rely on ``autoReload`` to re-load automatically.
///
/// Construct one controller per natural break (e.g., end-of-level), call
/// ``load()`` ahead of time, and `await` ``present(from:)`` at the break.
///
/// - Important: Host apps decide where interstitials belong. This package does
///   not impose placement or frequency policy.
@MainActor
@Observable
public final class AdmobInterstitialController {
    /// `true` when a loaded ad is available to present.
    public private(set) var isReady: Bool = false
    /// `true` while a `load()` call is in flight.
    public private(set) var isLoading: Bool = false
    /// Localized message of the most recent load failure, or `nil` after success.
    public private(set) var lastErrorMessage: String?

    private let adUnitID: String
    private let eventSink: AdmobEventSink
    private let autoReload: Bool

    private var ad: InterstitialAd?
    private var bridge: FullScreenDelegateBridge?
    private var pendingPresent: CheckedContinuation<Void, Error>?

    /// Create an interstitial controller.
    /// - Parameters:
    ///   - adUnitID: AdMob ad unit ID for the interstitial format.
    ///   - eventSink: Sink for load/present lifecycle events.
    ///   - autoReload: When `true` (default), the controller automatically
    ///     re-loads after dismiss or failure so the next ``present(from:)``
    ///     has an ad ready. Set to `false` to manage reloads manually.
    public init(
        adUnitID: String,
        eventSink: AdmobEventSink = .none,
        autoReload: Bool = true
    ) {
        self.adUnitID = adUnitID
        self.eventSink = eventSink
        self.autoReload = autoReload
    }

    /// Load an interstitial ad. No-ops when a load is already in flight or an
    /// ad is already ready.
    public func load() async {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        eventSink.send(.adLoadStarted(.interstitial))
        do {
            let loaded = try await InterstitialAd.load(with: adUnitID, request: Request())
            let bridge = makeBridge()
            loaded.fullScreenContentDelegate = bridge
            ad = loaded
            self.bridge = bridge
            isReady = true
            lastErrorMessage = nil
            eventSink.send(.adLoadSucceeded(.interstitial))
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.adLoadFailed(.interstitial, message: error.localizedDescription))
        }
        isLoading = false
    }

    /// Present the loaded interstitial. Returns when the user dismisses the ad.
    ///
    /// - Parameter viewController: Presenter. When `nil`, the top-most
    ///   foreground-scene view controller is resolved via
    ///   ``RootViewControllerLocator``.
    /// - Throws:
    ///   - ``AdmobError/duplicateRequest(format:)`` when another `present` is
    ///     already awaiting (continuation safety).
    ///   - ``AdmobError/presentationUnavailable(reason:)`` when no ad is
    ///     loaded, no presenter is available, or the SDK reports a presentation
    ///     failure.
    public func present(from viewController: UIViewController? = nil) async throws {
        guard pendingPresent == nil else {
            throw AdmobError.duplicateRequest(format: .interstitial)
        }
        guard let ad else {
            throw AdmobError.presentationUnavailable(reason: "No loaded interstitial ad")
        }
        guard let presenter = viewController ?? RootViewControllerLocator.find() else {
            throw AdmobError.presentationUnavailable(reason: "No presenting view controller")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingPresent = continuation
            ad.present(from: presenter)
        }
    }

    private func makeBridge() -> FullScreenDelegateBridge {
        FullScreenDelegateBridge(
            onPresent: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adPresented(.interstitial))
                }
            },
            onImpression: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adImpressed(.interstitial))
                }
            },
            onClick: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adClicked(.interstitial))
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleDismiss()
                }
            },
            onFailure: { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleFailure(message: message)
                }
            }
        )
    }

    private func handleDismiss() {
        ad = nil
        bridge = nil
        isReady = false
        eventSink.send(.adDismissed(.interstitial))
        let continuation = pendingPresent
        pendingPresent = nil
        continuation?.resume()
        if autoReload {
            Task { await self.load() }
        }
    }

    private func handleFailure(message: String) {
        ad = nil
        bridge = nil
        isReady = false
        lastErrorMessage = message
        eventSink.send(.adLoadFailed(.interstitial, message: message))
        let continuation = pendingPresent
        pendingPresent = nil
        continuation?.resume(throwing: AdmobError.presentationUnavailable(reason: message))
    }
}
