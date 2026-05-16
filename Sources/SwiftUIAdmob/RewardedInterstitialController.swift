import Foundation
import Observation
import UIKit
import GoogleMobileAds

@MainActor
@Observable
public final class AdmobRewardedInterstitialController {
    public private(set) var isReady: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var lastErrorMessage: String?

    private let adUnitID: String
    private let eventSink: AdmobEventSink
    private let autoReload: Bool

    private var ad: RewardedInterstitialAd?
    private var bridge: FullScreenDelegateBridge?
    private var pendingPresent: CheckedContinuation<AdmobReward?, Error>?
    private var earnedReward: AdmobReward?

    public init(
        adUnitID: String,
        eventSink: AdmobEventSink = .none,
        autoReload: Bool = true
    ) {
        self.adUnitID = adUnitID
        self.eventSink = eventSink
        self.autoReload = autoReload
    }

    public func load() async {
        guard !isLoading, ad == nil else { return }
        isLoading = true
        eventSink.send(.adLoadStarted(.rewardedInterstitial))
        do {
            let loaded = try await RewardedInterstitialAd.load(with: adUnitID, request: Request())
            let bridge = makeBridge()
            loaded.fullScreenContentDelegate = bridge
            ad = loaded
            self.bridge = bridge
            isReady = true
            lastErrorMessage = nil
            eventSink.send(.adLoadSucceeded(.rewardedInterstitial))
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.adLoadFailed(.rewardedInterstitial, message: error.localizedDescription))
        }
        isLoading = false
    }

    /// Present the loaded rewarded-interstitial ad.
    ///
    /// IMPORTANT: AdMob policy requires the host app to show an intro screen
    /// explaining the reward and offering an opt-out before calling this method.
    /// This package does not show such a screen.
    @discardableResult
    public func present(from viewController: UIViewController? = nil) async throws -> AdmobReward? {
        guard pendingPresent == nil else {
            throw AdmobError.duplicateRequest(format: .rewardedInterstitial)
        }
        guard let ad else {
            throw AdmobError.presentationUnavailable(reason: "No loaded rewarded interstitial ad")
        }
        guard let presenter = viewController ?? RootViewControllerLocator.find() else {
            throw AdmobError.presentationUnavailable(reason: "No presenting view controller")
        }
        earnedReward = nil
        let reward: AdmobReward? = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AdmobReward?, Error>) in
            pendingPresent = continuation
            ad.present(from: presenter) { [weak self] in
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
                    self?.eventSink.send(.adPresented(.rewardedInterstitial))
                }
            },
            onImpression: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adImpressed(.rewardedInterstitial))
                }
            },
            onClick: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adClicked(.rewardedInterstitial))
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
        eventSink.send(.adDismissed(.rewardedInterstitial))
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
        eventSink.send(.adLoadFailed(.rewardedInterstitial, message: message))
        let continuation = pendingPresent
        pendingPresent = nil
        continuation?.resume(throwing: AdmobError.presentationUnavailable(reason: message))
    }
}
