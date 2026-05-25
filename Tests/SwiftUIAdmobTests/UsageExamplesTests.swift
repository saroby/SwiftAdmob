import Testing
import SwiftUI
@testable import SwiftUIAdmob

// MARK: - Usage compile checks
//
// These tests do NOT call into the live Google Mobile Ads SDK. Their purpose
// is to keep `docs/AI_USAGE.md` snippets honest: if a public API signature
// changes incompatibly, the matching example here fails to build and someone
// has to update the docs. Bodies that would otherwise require a live SDK
// session are wrapped in `_neverRun` so the compiler still type-checks them
// without running anything at test time.

@MainActor
private func _neverRun(_ body: () async throws -> Void) {
    // Type-check only. Never invoked.
    _ = body
}

// MARK: - Banner height (real assertions)

@Suite("AdmobBanner.height")
@MainActor
struct BannerHeightTests {
    @Test("Non-positive width returns zero")
    func zeroWidth() {
        #expect(AdmobBanner.height(forWidth: 0) == 0)
        #expect(AdmobBanner.height(forWidth: -10) == 0)
    }

    @Test("Positive width returns the standard 320x50 banner height")
    func positiveWidth() {
        // AdmobBanner is fixed 320x50 since 1.0.1; height is constant
        // regardless of container width.
        #expect(AdmobBanner.height(forWidth: 320) == 50)
        #expect(AdmobBanner.height(forWidth: 390) == 50)
        #expect(AdmobBanner.height(forWidth: 768) == 50)
    }
}

@Suite("AdmobAdaptiveBanner.height")
@MainActor
struct AdaptiveBannerHeightTests {
    @Test("Non-positive width returns zero")
    func zeroWidth() {
        #expect(AdmobAdaptiveBanner.height(forWidth: 0) == 0)
        #expect(AdmobAdaptiveBanner.height(forWidth: -10) == 0)
    }

    @Test("Positive width yields a height in the 50–150pt adaptive range")
    func positiveWidth() {
        let height320 = AdmobAdaptiveBanner.height(forWidth: 320)
        let height390 = AdmobAdaptiveBanner.height(forWidth: 390)
        // GADLargeAnchoredAdaptiveBannerAdSize is documented as
        // 50–150pt for any width/device combination. Test the contract,
        // not a specific SDK-computed value.
        #expect(height320 >= 50)
        #expect(height320 <= 150)
        #expect(height390 >= 50)
        #expect(height390 <= 150)
    }
}

// MARK: - Construction smoke tests

@Suite("Controller construction")
@MainActor
struct ControllerConstructionTests {
    @Test("Interstitial controller starts in idle state")
    func interstitialIdle() {
        let controller = AdmobInterstitialController(
            adUnitID: AdUnitIDMap.googleTest.interstitial!
        )
        #expect(controller.isReady == false)
        #expect(controller.isLoading == false)
        #expect(controller.lastErrorMessage == nil)
    }

    @Test("Rewarded controller starts in idle state")
    func rewardedIdle() {
        let controller = AdmobRewardedController(
            adUnitID: AdUnitIDMap.googleTest.rewarded!
        )
        #expect(controller.isReady == false)
        #expect(controller.isLoading == false)
    }

    @Test("Rewarded interstitial controller starts in idle state")
    func rewardedInterstitialIdle() {
        let controller = AdmobRewardedInterstitialController(
            adUnitID: AdUnitIDMap.googleTest.rewardedInterstitial!
        )
        #expect(controller.isReady == false)
        #expect(controller.isLoading == false)
    }

    @Test("App-open coordinator starts in idle state with 4h expiration")
    func appOpenIdle() {
        let coordinator = AdmobAppOpenCoordinator(
            adUnitID: AdUnitIDMap.googleTest.appOpen!
        )
        #expect(coordinator.isReady == false)
        #expect(coordinator.isLoading == false)
        #expect(coordinator.isPresenting == false)
        #expect(coordinator.isSuppressed == false)
        #expect(AdmobAppOpenCoordinator.expiration == 4 * 60 * 60)
    }
}

// MARK: - Error recovery hints

@Suite("AdmobError recoverySuggestion")
struct AdmobErrorRecoveryTests {
    @Test("Every case provides a recovery suggestion")
    func everyCaseHasHint() {
        let cases: [AdmobError] = [
            .missingHostConfiguration("GADApplicationIdentifier"),
            .sdkNotStarted,
            .consentNotResolved,
            .missingAdUnitID(.banner),
            .loadFailed(format: .interstitial, message: "no fill"),
            .presentationUnavailable(reason: "no presenter"),
            .adExpired(format: .appOpen),
            .duplicateRequest(format: .rewarded),
            .disabledByConfiguration
        ]
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(error.recoverySuggestion?.isEmpty == false)
            #expect(error.failureReason?.isEmpty == false)
        }
    }
}

// MARK: - Compile-only example: 5-minute integration
//
// Mirrors the "5-Minute Integration" snippet in docs/AI_USAGE.md.

@MainActor
private struct _FiveMinuteIntegrationApp: App {
    @State private var bootstrapper = AdmobBootstrapper(
        configuration: .development(),
        eventSink: .logging()
    )

    var body: some Scene {
        WindowGroup {
            _RootViewExample()
                .environment(bootstrapper)
                .task { await bootstrapper.start() }
        }
    }
}

@MainActor
private struct _RootViewExample: View {
    var body: some View {
        Color.clear
            .adBanner(.bottom)
    }
}

// MARK: - Compile-only example: top banner placement

@MainActor
private struct _TopBannerExample: View {
    var body: some View {
        Color.clear.adBanner(.top)
    }
}

// MARK: - Compile-only example: inline banner with event callback

@MainActor
private struct _InlineBannerExample: View {
    var body: some View {
        AdmobBanner(adUnitID: AdUnitIDMap.googleTest.banner) { event in
            switch event {
            case .loaded, .failed, .impressed, .clicked:
                break
            }
        }
    }
}

// MARK: - Compile-only example: adaptive banner placement

@MainActor
private struct _AdaptiveBannerExample: View {
    var body: some View {
        Color.clear.adAdaptiveBanner(.bottom)
    }
}

@MainActor
private struct _InlineAdaptiveBannerExample: View {
    var body: some View {
        AdmobAdaptiveBanner(adUnitID: AdUnitIDMap.googleTest.banner) { event in
            switch event {
            case .loaded, .failed, .impressed, .clicked:
                break
            }
        }
    }
}

// MARK: - Compile-only example: interstitial usage

@MainActor
private struct _InterstitialExample: View {
    @State private var interstitial = AdmobInterstitialController(
        adUnitID: AdUnitIDMap.googleTest.interstitial!
    )

    var body: some View {
        Button("Next Round") {
            Task {
                try? await interstitial.present()
                _continueGame()
            }
        }
        .task { await interstitial.load() }
    }

    private func _continueGame() {}
}

// MARK: - Compile-only example: rewarded with reward grant

@MainActor
private struct _RewardedExample: View {
    @State private var rewarded = AdmobRewardedController(
        adUnitID: AdUnitIDMap.googleTest.rewarded!
    )
    @State private var coins = 0

    var body: some View {
        Button("Watch ad for 10 coins") {
            Task {
                guard let reward = try? await rewarded.present() else { return }
                coins += Int(truncatingIfNeeded: NSDecimalNumber(decimal: reward.amount).intValue)
            }
        }
        .disabled(!rewarded.isReady)
        .task { await rewarded.load() }
    }
}

// MARK: - Compile-only example: rewarded interstitial with intro screen

@MainActor
private struct _RewardedInterstitialExample: View {
    @State private var rewardedInterstitial = AdmobRewardedInterstitialController(
        adUnitID: AdUnitIDMap.googleTest.rewardedInterstitial!
    )
    @State private var showIntro = false

    var body: some View {
        Color.clear
            .task { await rewardedInterstitial.load() }
            .onAppear { showIntro = true }
            .sheet(isPresented: $showIntro) {
                Button("Accept") {
                    showIntro = false
                    Task { _ = try? await rewardedInterstitial.present() }
                }
            }
    }
}

// MARK: - Compile-only example: app-open with scene phase

@MainActor
private struct _AppOpenExample: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootstrapper = AdmobBootstrapper(configuration: .development())
    @State private var appOpen = AdmobAppOpenCoordinator(
        adUnitID: AdUnitIDMap.googleTest.appOpen!
    )

    var body: some Scene {
        WindowGroup {
            Color.clear
                .environment(bootstrapper)
                .task { await bootstrapper.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            appOpen.handleScenePhaseChange(phase)
        }
    }
}

// MARK: - Compile-only example: consent privacy options

@MainActor
private struct _ConsentSettingsExample: View {
    @Environment(AdmobBootstrapper.self) private var bootstrapper

    var body: some View {
        Form {
            if bootstrapper.consent.isPrivacyOptionsRequired {
                Button("Privacy options") {
                    Task {
                        guard let vc = RootViewControllerLocator.find() else { return }
                        await bootstrapper.consent.presentPrivacyOptions(from: vc)
                        await bootstrapper.reconcile()
                    }
                }
            }
        }
    }
}
