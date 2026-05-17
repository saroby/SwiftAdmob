import Foundation
import Observation
import SwiftUI
import UIKit
import GoogleMobileAds

/// Scene-aware app-open ad coordinator.
///
/// Typical wiring in a SwiftUI app:
///
/// ```swift
/// @Environment(\.scenePhase) private var scenePhase
/// // ...
/// .onChange(of: scenePhase) { _, new in
///     appOpen.handleScenePhaseChange(new)
/// }
/// ```
///
/// - Important: The first `.active` transition after launch is **consumed as a
///   load trigger only** — the ad is not shown on cold start, to avoid
///   interrupting content that's already interactive. Subsequent
///   background→active transitions show the loaded ad if available.
/// - Note: Loaded ads expire after ``expiration`` (4 hours) per AdMob policy.
@MainActor
@Observable
public final class AdmobAppOpenCoordinator {
    /// Maximum age of a loaded app-open ad before it must be discarded.
    ///
    /// 4 hours. Required by AdMob policy. See
    /// https://developers.google.com/admob/ios/app-open
    public static let expiration: TimeInterval = 4 * 60 * 60

    /// `true` when a loaded, non-expired ad is available to present.
    public private(set) var isReady: Bool = false
    /// `true` while a `load()` call is in flight.
    public private(set) var isLoading: Bool = false
    /// `true` between `present` and dismiss/failure.
    public private(set) var isPresenting: Bool = false
    /// Localized message of the most recent load failure, or `nil` after success.
    public private(set) var lastErrorMessage: String?

    /// Suppress all ``showIfAvailable(from:)`` calls when `true`.
    ///
    /// Set to `true` during onboarding, IAP/login flows, or any critical
    /// moment where an app-open ad would disrupt UX. Restore to `false` when
    /// the critical flow ends.
    public var isSuppressed: Bool = false

    private let adUnitID: String
    private let eventSink: AdmobEventSink

    private var ad: AppOpenAd?
    private var bridge: FullScreenDelegateBridge?
    private var loadTime: Date?
    private var firstForegroundConsumed: Bool = false

    /// Create the coordinator.
    /// - Parameters:
    ///   - adUnitID: AdMob ad unit ID for the app-open format.
    ///   - eventSink: Sink for load/present/dismiss lifecycle events.
    public init(adUnitID: String, eventSink: AdmobEventSink = .none) {
        self.adUnitID = adUnitID
        self.eventSink = eventSink
    }

    /// Load an app-open ad. No-ops when a load is in flight, or when a
    /// non-expired ad is already ready.
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

    /// Show the loaded ad if one is available and not expired.
    ///
    /// Silently no-ops when ``isSuppressed`` is `true`, a present is already
    /// in flight, or no non-expired ad is ready. Triggers a background load
    /// when no ad is ready.
    /// - Parameter viewController: Presenter. When `nil`, the top-most
    ///   foreground-scene view controller is resolved.
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

    /// Forward a SwiftUI `scenePhase` change to drive the cold-start guard
    /// and background→foreground show.
    ///
    /// - Parameter phase: The new `ScenePhase` value.
    /// - Important: The **first** `.active` event after launch is consumed as
    ///   a load trigger only — no ad is shown. Subsequent `.active` events
    ///   (background→foreground) call ``showIfAvailable(from:)``.
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
