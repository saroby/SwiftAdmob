import Foundation
import Observation
import UIKit

/// Top-level coordinator that wires consent + SDK start and gates all ad work.
///
/// Construct one bootstrapper per app, typically in `@main`, and inject it via
/// `.environment(bootstrapper)`. SwiftUI scenes then call ``start(presenting:)``
/// from a `.task { }` modifier:
///
/// ```swift
/// .task { await bootstrapper.start() }
/// ```
///
/// - Important: ``start(presenting:)`` is **idempotent**. Calling it from every
///   scene/view `.task` is safe — concurrent calls await the same in-flight
///   `Task` and repeat calls after success no-op.
///
/// ## External references
///
/// Before wiring this type into a host app, make sure the project satisfies
/// Google's official iOS quick-start (Info.plist `GADApplicationIdentifier`,
/// `SKAdNetworkItems`, AdMob console registration). The bootstrapper assumes
/// these are already in place and will fatal-assert via the underlying SDK
/// otherwise.
///
/// - Google AdMob iOS quick-start: <https://developers.google.com/admob/ios/quick-start>
/// - Host-side checklist in this repo: `docs/HOST_APP_SETUP.md`
@MainActor
@Observable
public final class AdmobBootstrapper {
    /// The configuration this bootstrapper was created with.
    public let configuration: AdmobConfiguration
    /// Consent coordinator that owns UMP state and form presentation.
    public let consent: AdmobConsentCoordinator
    /// Event sink used for SDK-level events (startup, diagnostic warnings).
    public let eventSink: AdmobEventSink

    /// `true` once `MobileAds.start` has completed successfully.
    public private(set) var isStarted: Bool = false
    /// Human-readable description of the last start failure, or `nil`. Reserved for future use.
    public private(set) var lastStartErrorMessage: String?

    private let mobileAds: MobileAdsBridge
    private var startTask: Task<Void, Never>?

    /// Designated initializer with injectable bridges. Use this in tests.
    /// - Parameters:
    ///   - configuration: Runtime configuration.
    ///   - mobileAds: Mobile Ads SDK bridge (use ``LiveMobileAdsBridge`` in production).
    ///   - consent: Pre-built consent coordinator.
    ///   - eventSink: Sink for SDK-level events.
    public init(
        configuration: AdmobConfiguration,
        mobileAds: MobileAdsBridge,
        consent: AdmobConsentCoordinator,
        eventSink: AdmobEventSink = .none
    ) {
        self.configuration = configuration
        self.mobileAds = mobileAds
        self.consent = consent
        self.eventSink = eventSink
    }

    /// Convenience initializer that wires live Google Mobile Ads and UMP bridges.
    ///
    /// Use this in shipping apps. Tests should use the designated initializer
    /// with fake bridges.
    /// - Parameters:
    ///   - configuration: Runtime configuration.
    ///   - eventSink: Sink for SDK-level events.
    public convenience init(
        configuration: AdmobConfiguration,
        eventSink: AdmobEventSink = .none
    ) {
        let mobileAds = LiveMobileAdsBridge()
        let consentBridge = LiveConsentBridge()
        let consent = AdmobConsentCoordinator(bridge: consentBridge, eventSink: eventSink)
        self.init(
            configuration: configuration,
            mobileAds: mobileAds,
            consent: consent,
            eventSink: eventSink
        )
    }

    /// Composite gate that controllers and views must observe before requesting ads.
    ///
    /// All three conditions must hold: configuration permits ads
    /// (``AdmobConfiguration/isAdRequestPermitted``), SDK is started, and consent
    /// permits ad requests (``AdmobConsentCoordinator/canRequestAds``).
    public var canRequestAds: Bool {
        guard configuration.isAdRequestPermitted else { return false }
        return isStarted && consent.canRequestAds
    }

    /// Run consent refresh + SDK startup.
    ///
    /// **Idempotent.** Concurrent or repeat calls await the in-flight task,
    /// so it is safe to call from every scene `.task` and from view `.task`
    /// modifiers without coordination.
    ///
    /// - Parameter viewController: Optional presenter for the UMP consent form.
    ///   When `nil`, consent info is refreshed but no form is presented.
    /// - Note: If consent does not permit ad requests, SDK start is deferred.
    ///   Call ``reconcile()`` after a later consent grant to complete startup.
    public func start(
        presenting viewController: UIViewController? = nil
    ) async {
        if isStarted { return }
        if let task = startTask {
            await task.value
            return
        }
        let task = Task { @MainActor [self] in
            guard configuration.isAdRequestPermitted else {
                eventSink.send(.diagnosticWarning("AdmobConfiguration.runtimeMode is .disabled — skipping startup."))
                return
            }

            await consent.refresh(
                from: viewController,
                debugSettings: configuration.consentDebugSettings
            )

            mobileAds.updateRequestConfiguration(
                testDeviceIdentifiers: configuration.testDeviceIdentifiers
            )

            guard consent.canRequestAds else {
                eventSink.send(.diagnosticWarning("Consent does not permit ad requests — SDK start deferred."))
                return
            }

            await mobileAds.start()
            isStarted = true
            eventSink.send(.sdkStarted)
        }
        startTask = task
        await task.value
        startTask = nil
    }

    /// Re-evaluate consent state and start the SDK if it became permissible.
    ///
    /// Call this after a late consent grant — typically after the user
    /// completes the privacy options form via
    /// ``AdmobConsentCoordinator/presentPrivacyOptions(from:)``.
    public func reconcile() async {
        guard !isStarted else { return }
        guard configuration.isAdRequestPermitted else { return }
        guard consent.canRequestAds else { return }
        await mobileAds.start()
        isStarted = true
        eventSink.send(.sdkStarted)
    }
}
