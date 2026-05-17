import Foundation
import Observation
import UIKit
import GoogleMobileAds

/// Reward payload returned by ``AdmobRewardedController/present(from:)`` and
/// ``AdmobRewardedInterstitialController/present(from:)``.
public struct AdmobReward: Sendable, Hashable {
    /// Reward amount, as reported by the SDK's `adReward`.
    public let amount: Decimal
    /// Reward type label (e.g., "coins"), as reported by the SDK's `adReward`.
    public let type: String

    /// Create a reward value. Typically constructed by the controller, not callers.
    public init(amount: Decimal, type: String) {
        self.amount = amount
        self.type = type
    }
}

/// One-shot rewarded ad controller with async load/present.
///
/// Lifecycle: ``load()`` → ``present(from:)`` → discarded. After a successful
/// present (or any failure), the underlying ad object is released and
/// ``isReady`` is set to `false`. Call ``load()`` again before the next
/// ``present(from:)`` — or rely on ``autoReload`` to re-load automatically.
///
/// - Warning: Grant the in-app benefit **only** based on the non-nil
///   ``AdmobReward`` returned from ``present(from:)``. Returning `nil` means
///   the user dismissed without earning. Never grant benefits on dismissal
///   alone — that's a policy violation and breaks reward economics.
@MainActor
@Observable
public final class AdmobRewardedController {
    /// `true` when a loaded ad is available to present.
    public private(set) var isReady: Bool = false
    /// `true` while a `load()` call is in flight.
    public private(set) var isLoading: Bool = false
    /// Localized message of the most recent load failure, or `nil` after success.
    public private(set) var lastErrorMessage: String?

    private let adUnitID: String
    private let eventSink: AdmobEventSink
    private let autoReload: Bool

    private var ad: RewardedAd?
    private var bridge: FullScreenDelegateBridge?
    private var pendingPresent: CheckedContinuation<AdmobReward?, Error>?
    private var earnedReward: AdmobReward?

    /// Create a rewarded controller.
    /// - Parameters:
    ///   - adUnitID: AdMob ad unit ID for the rewarded format.
    ///   - eventSink: Sink for load/present/reward lifecycle events.
    ///   - autoReload: When `true` (default), the controller automatically
    ///     re-loads after dismiss or failure. Set to `false` to manage reloads
    ///     manually.
    public init(
        adUnitID: String,
        eventSink: AdmobEventSink = .none,
        autoReload: Bool = true
    ) {
        self.adUnitID = adUnitID
        self.eventSink = eventSink
        self.autoReload = autoReload
    }

    /// Load a rewarded ad. No-ops when a load is already in flight or an ad
    /// is already ready.
    public func load() async {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        eventSink.send(.adLoadStarted(.rewarded))
        do {
            let loaded = try await RewardedAd.load(with: adUnitID, request: Request())
            let bridge = makeBridge()
            loaded.fullScreenContentDelegate = bridge
            ad = loaded
            self.bridge = bridge
            isReady = true
            lastErrorMessage = nil
            eventSink.send(.adLoadSucceeded(.rewarded))
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.adLoadFailed(.rewarded, message: error.localizedDescription))
        }
        isLoading = false
    }

    /// Present the loaded rewarded ad and await dismissal.
    ///
    /// - Parameter viewController: Presenter. When `nil`, the top-most
    ///   foreground-scene view controller is resolved via
    ///   ``RootViewControllerLocator``.
    /// - Returns: The earned reward, or `nil` if the user dismissed the ad
    ///   without earning. Grant the in-app benefit **only** when a non-nil
    ///   reward is returned.
    /// - Throws:
    ///   - ``AdmobError/duplicateRequest(format:)`` when another `present` is
    ///     already awaiting (continuation safety).
    ///   - ``AdmobError/presentationUnavailable(reason:)`` when no ad is
    ///     loaded, no presenter is available, or the SDK reports a presentation
    ///     failure.
    @discardableResult
    public func present(from viewController: UIViewController? = nil) async throws -> AdmobReward? {
        guard pendingPresent == nil else {
            throw AdmobError.duplicateRequest(format: .rewarded)
        }
        guard let ad else {
            throw AdmobError.presentationUnavailable(reason: "No loaded rewarded ad")
        }
        guard let presenter = viewController ?? RootViewControllerLocator.find() else {
            throw AdmobError.presentationUnavailable(reason: "No presenting view controller")
        }
        earnedReward = nil
        let reward: AdmobReward? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AdmobReward?, Error>) in
            pendingPresent = continuation
            ad.present(from: presenter) { [weak self] in
                // SDK does not statically guarantee main-thread invocation. Hop
                // explicitly so all @MainActor state mutation stays serialized.
                let amount = ad.adReward.amount.decimalValue
                let type = ad.adReward.type
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let reward = AdmobReward(amount: amount, type: type)
                    self.earnedReward = reward
                    self.eventSink.send(.rewardEarned(
                        amount: NSDecimalNumber(decimal: amount).doubleValue,
                        type: type
                    ))
                }
            }
        }
        return reward
    }

    private func makeBridge() -> FullScreenDelegateBridge {
        FullScreenDelegateBridge(
            onPresent: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adPresented(.rewarded))
                }
            },
            onImpression: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adImpressed(.rewarded))
                }
            },
            onClick: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adClicked(.rewarded))
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleDismiss()
                }
            },
            onFailure: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleFailure(message: message)
                }
            }
        )
    }

    private func handleDismiss() {
        ad = nil
        bridge = nil
        isReady = false
        eventSink.send(.adDismissed(.rewarded))
        let continuation = pendingPresent
        pendingPresent = nil
        continuation?.resume(returning: earnedReward)
        earnedReward = nil
        if autoReload {
            Task { await self.load() }
        }
    }

    private func handleFailure(message: String) {
        ad = nil
        bridge = nil
        isReady = false
        lastErrorMessage = message
        eventSink.send(.adLoadFailed(.rewarded, message: message))
        let continuation = pendingPresent
        pendingPresent = nil
        continuation?.resume(throwing: AdmobError.presentationUnavailable(reason: message))
    }
}
