import Testing
import UIKit
@testable import SwiftUIAdmob

// MARK: - Fake bridge

@MainActor
final class FakeConsentBridge: ConsentBridge {
    var snapshot: AdmobConsentSnapshot
    var refreshError: (any Error)?
    var presentFormError: (any Error)?
    var presentPrivacyError: (any Error)?

    private(set) var requestConsentCallCount = 0
    private(set) var presentFormCallCount = 0
    private(set) var presentPrivacyCallCount = 0
    private(set) var resetCallCount = 0

    init(snapshot: AdmobConsentSnapshot = AdmobConsentSnapshot(canRequestAds: false, privacyOptionsRequired: false)) {
        self.snapshot = snapshot
    }

    func requestConsentInfoUpdate(debugSettings: AdmobConsentDebugSettings?) async throws {
        requestConsentCallCount += 1
        if let refreshError {
            throw refreshError
        }
    }

    func presentRequiredFormIfNeeded(from viewController: UIViewController) async throws {
        presentFormCallCount += 1
        if let presentFormError {
            throw presentFormError
        }
    }

    func presentPrivacyOptionsForm(from viewController: UIViewController) async throws {
        presentPrivacyCallCount += 1
        if let presentPrivacyError {
            throw presentPrivacyError
        }
    }

    func reset() {
        resetCallCount += 1
    }
}

// MARK: - Suite

@Suite("AdmobConsentCoordinator")
@MainActor
struct ConsentCoordinatorTests {
    @Test("Initial snapshot mirrors the bridge")
    func initialSnapshot() {
        let bridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: true, privacyOptionsRequired: true))
        let coordinator = AdmobConsentCoordinator(bridge: bridge)
        #expect(coordinator.canRequestAds)
        #expect(coordinator.isPrivacyOptionsRequired)
    }

    @Test("Refresh without a view controller skips the form presentation step")
    func refreshWithoutViewController() async {
        let bridge = FakeConsentBridge()
        let coordinator = AdmobConsentCoordinator(bridge: bridge)
        await coordinator.refresh()
        #expect(bridge.requestConsentCallCount == 1)
        #expect(bridge.presentFormCallCount == 0)
    }

    @Test("Refresh records error message but does not throw")
    func refreshErrorRecorded() async {
        struct FakeFailure: Error { let message = "boom" }
        let bridge = FakeConsentBridge()
        bridge.refreshError = FakeFailure()
        let coordinator = AdmobConsentCoordinator(bridge: bridge)
        await coordinator.refresh()
        #expect(coordinator.lastErrorMessage != nil)
    }

    @Test("Snapshot updates emit consentUpdated events")
    func snapshotChangeEmitsEvent() async {
        let bridge = FakeConsentBridge(snapshot: AdmobConsentSnapshot(canRequestAds: false, privacyOptionsRequired: false))
        final class Capture: @unchecked Sendable {
            var events: [AdmobEvent] = []
        }
        let capture = Capture()
        let sink = AdmobEventSink { event in
            capture.events.append(event)
        }
        let coordinator = AdmobConsentCoordinator(bridge: bridge, eventSink: sink)
        bridge.snapshot = AdmobConsentSnapshot(canRequestAds: true, privacyOptionsRequired: false)
        await coordinator.refresh()
        #expect(capture.events.contains(.consentUpdated(canRequestAds: true, privacyOptionsRequired: false)))
    }

    @Test("Reset is forwarded to the bridge")
    func resetForwarded() {
        let bridge = FakeConsentBridge()
        let coordinator = AdmobConsentCoordinator(bridge: bridge)
        coordinator.reset()
        #expect(bridge.resetCallCount == 1)
    }
}
