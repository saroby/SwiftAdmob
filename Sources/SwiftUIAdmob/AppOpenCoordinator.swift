import Foundation
import Observation
import SwiftUI
import UIKit
import GoogleMobileAds

@MainActor
@Observable
public final class AdmobAppOpenCoordinator {
    /// AdMob requires app open ads to be discarded after four hours.
    public static let expiration: TimeInterval = 4 * 60 * 60

    public private(set) var isReady: Bool = false
    public private(set) var isLoading: Bool = false
    public private(set) var isPresenting: Bool = false
    public private(set) var lastErrorMessage: String?

    /// Setting this to `true` suppresses any further `showIfAvailable` calls.
    /// Useful during onboarding, IAP flows, or critical app moments.
    public var isSuppressed: Bool = false

    private let adUnitID: String
    private let eventSink: AdmobEventSink

    private var ad: AppOpenAd?
    private var bridge: FullScreenDelegateBridge?
    private var loadTime: Date?
    private var firstForegroundConsumed: Bool = false

    public init(adUnitID: String, eventSink: AdmobEventSink = .none) {
        self.adUnitID = adUnitID
        self.eventSink = eventSink
    }

    public func load() async {
        if isLoading { return }
        if isReady, !isExpired { return }
        isLoading = true
        eventSink.send(.adLoadStarted(.appOpen))
        do {
            let loaded = try await AppOpenAd.load(with: adUnitID, request: Request())
            let bridge = makeBridge()
            loaded.fullScreenContentDelegate = bridge
            ad = loaded
            self.bridge = bridge
            loadTime = Date()
            isReady = true
            lastErrorMessage = nil
            eventSink.send(.adLoadSucceeded(.appOpen))
        } catch {
            lastErrorMessage = error.localizedDescription
            eventSink.send(.adLoadFailed(.appOpen, message: error.localizedDescription))
        }
        isLoading = false
    }

    /// Show the loaded ad if available and not expired. Silently no-ops when
    /// suppressed, already presenting, or no ad is ready. Returns immediately;
    /// the ad lifecycle is tracked through ``isPresenting``.
    public func showIfAvailable(from viewController: UIViewController? = nil) {
        guard !isSuppressed, !isPresenting else { return }
        guard isReady, !isExpired, let ad else {
            Task { await self.load() }
            return
        }
        guard let presenter = viewController ?? RootViewControllerLocator.find() else {
            eventSink.send(.diagnosticWarning("App open ad has no presenter — skipping."))
            return
        }
        isPresenting = true
        ad.present(from: presenter)
    }

    /// Hook this to `.onChange(of: scenePhase)` in the host app. App-open ads
    /// should not appear when content is already interactive on cold start,
    /// so the first foreground event is consumed as a load trigger only.
    public func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        if !firstForegroundConsumed {
            firstForegroundConsumed = true
            Task { await self.load() }
            return
        }
        showIfAvailable()
    }

    private var isExpired: Bool {
        guard let loadTime else { return true }
        return Date().timeIntervalSince(loadTime) > Self.expiration
    }

    private func makeBridge() -> FullScreenDelegateBridge {
        FullScreenDelegateBridge(
            onPresent: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adPresented(.appOpen))
                }
            },
            onImpression: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adImpressed(.appOpen))
                }
            },
            onClick: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.eventSink.send(.adClicked(.appOpen))
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
        loadTime = nil
        isReady = false
        isPresenting = false
        eventSink.send(.adDismissed(.appOpen))
        Task { await self.load() }
    }

    private func handleFailure(message: String) {
        ad = nil
        bridge = nil
        loadTime = nil
        isReady = false
        isPresenting = false
        lastErrorMessage = message
        eventSink.send(.adLoadFailed(.appOpen, message: message))
    }
}
