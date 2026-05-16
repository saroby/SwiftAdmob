import Foundation
import Observation
import UIKit

@MainActor
@Observable
public final class AdmobBootstrapper {
    public let configuration: AdmobConfiguration
    public let consent: AdmobConsentCoordinator
    public let eventSink: AdmobEventSink

    public private(set) var isStarted: Bool = false
    public private(set) var lastStartErrorMessage: String?

    private let mobileAds: MobileAdsBridge
    private var startTask: Task<Void, Never>?

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

    /// Convenience initializer that wires the live Google Mobile Ads and UMP bridges.
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

    public var canRequestAds: Bool {
        guard configuration.isAdRequestPermitted else { return false }
        return isStarted && consent.canRequestAds
    }

    /// Run consent + SDK startup. Idempotent: concurrent or repeat calls await
    /// the in-flight task. Safe to call from every scene/view lifecycle event.
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
    /// Useful after presenting the privacy options form.
    public func reconcile() async {
        guard !isStarted else { return }
        guard configuration.isAdRequestPermitted else { return }
        guard consent.canRequestAds else { return }
        await mobileAds.start()
        isStarted = true
        eventSink.send(.sdkStarted)
    }
}
