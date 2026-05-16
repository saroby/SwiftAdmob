import Foundation
import Observation
import UIKit
import GoogleMobileAds

@MainActor
@Observable
public final class AdmobInterstitialController {
    public private(set) var isReady: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var lastErrorMessage: String?

    private let adUnitID: String
    private let eventSink: AdmobEventSink
    private let autoReload: Bool

    private var ad: InterstitialAd?
    private var bridge: FullScreenDelegateBridge?
    private var pendingPresent: CheckedContinuation<Void, Error>?

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

    /// Present the loaded interstitial. Throws if no ad is ready, no presenter
    /// is available, or a present call is already in flight. Returns when the
    /// user dismisses the ad.
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
