import Testing
@testable import SwiftUIAdmob

@MainActor
final class FakeMobileAdsBridge: MobileAdsBridge {
    var isStarted: Bool = false
    private(set) var startCallCount = 0
    private(set) var lastTestDeviceIdentifiers: [String] = []

    func start() async {
        startCallCount += 1
        isStarted = true
    }

    func updateRequestConfiguration(testDeviceIdentifiers: [String]) {
        lastTestDeviceIdentifiers = testDeviceIdentifiers
    }
}

@Suite("AdmobBootstrapper")
@MainActor
struct BootstrapperTests {
    @Test("Disabled configuration skips startup entirely")
    func disabledSkipsStartup() async {
        let bridge = FakeMobileAdsBridge()
        let consent = AdmobConsentCoordinator(bridge: FakeConsentBridge())
        let bootstrapper = AdmobBootstrapper(
            configuration: .disabled,
            mobileAds: bridge,
            consent: consent
        )
        await bootstrapper.start()
        #expect(bridge.startCallCount == 0)
        #expect(bootstrapper.isStarted == false)
        #expect(bootstrapper.canRequestAds == false)
    }

    @Test("Consent denial defers SDK start")
    func consentDeniedDefersStart() async {
        let bridge = FakeMobileAdsBridge()
        let consentBridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: false, privacyOptionsRequired: false))
        let consent = AdmobConsentCoordinator(bridge: consentBridge)
        let bootstrapper = AdmobBootstrapper(
            configuration: .development(),
            mobileAds: bridge,
            consent: consent
        )
        await bootstrapper.start()
        #expect(bridge.startCallCount == 0)
        #expect(bootstrapper.isStarted == false)
    }

    @Test("Consent granted starts SDK exactly once")
    func consentGrantedStartsOnce() async {
        let bridge = FakeMobileAdsBridge()
        let consentBridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: true, privacyOptionsRequired: false))
        let consent = AdmobConsentCoordinator(bridge: consentBridge)
        let bootstrapper = AdmobBootstrapper(
            configuration: .development(),
            mobileAds: bridge,
            consent: consent
        )
        await bootstrapper.start()
        await bootstrapper.start()
        #expect(bridge.startCallCount == 1)
        #expect(bootstrapper.isStarted)
        #expect(bootstrapper.canRequestAds)
    }

    @Test("Test device identifiers forwarded to the SDK bridge")
    func testDeviceIdentifiersForwarded() async {
        let bridge = FakeMobileAdsBridge()
        let consentBridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: true, privacyOptionsRequired: false))
        let consent = AdmobConsentCoordinator(bridge: consentBridge)
        let config = AdmobConfiguration.development(testDeviceIdentifiers: ["DEVICE-A", "DEVICE-B"])
        let bootstrapper = AdmobBootstrapper(
            configuration: config,
            mobileAds: bridge,
            consent: consent
        )
        await bootstrapper.start()
        #expect(bridge.lastTestDeviceIdentifiers == ["DEVICE-A", "DEVICE-B"])
    }

    @Test("Reconcile starts SDK after delayed consent grant")
    func reconcileStartsAfterDelay() async {
        let bridge = FakeMobileAdsBridge()
        let consentBridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: false, privacyOptionsRequired: false))
        let consent = AdmobConsentCoordinator(bridge: consentBridge)
        let bootstrapper = AdmobBootstrapper(
            configuration: .development(),
            mobileAds: bridge,
            consent: consent
        )
        await bootstrapper.start()
        #expect(bootstrapper.isStarted == false)

        // Simulate the user granting consent later via privacy options form.
        consentBridge.snapshot = AdmobConsentSnapshot(canRequestAds: true, privacyOptionsRequired: false)
        await consent.refresh()
        await bootstrapper.reconcile()

        #expect(bridge.startCallCount == 1)
        #expect(bootstrapper.isStarted)
    }
}
