# SwiftUIAdmob Implementation — Phase 1

## Goal

Implement the SwiftUIAdmob Swift Package per `docs/ARCHITECTURE.md` and
`docs/LLM_CONTEXT.md`. iOS 26 minimum, Swift 6, Google Mobile Ads 13.3.

## Acceptance Criteria

- [x] `Package.swift` exists with iOS 26 minimum and the official Google Mobile
      Ads SPM dependency pinned to 13.3.0.
- [x] Configuration, Bridge, ConsentCoordinator, Bootstrapper, Banner, three
      full-screen controllers, and AppOpen coordinator implemented.
- [x] Protocol-backed bridges allow unit tests without live ad requests.
- [x] `xcodebuild -scheme SwiftUIAdmob -destination 'generic/platform=iOS
      Simulator'` succeeds.
- [x] Unit tests pass via `xcodebuild ... test` on `iPhone 17 Pro` simulator.
- [x] README, HOST_APP_SETUP, and ARCHITECTURE/LLM_CONTEXT consistent.

## Checklist

- [x] Package.swift scaffold (iOS 26, GoogleMobileAds 13.3, Swift 6 language mode).
- [x] Support layer: AdmobError, AdmobEvent, AdmobEventSink, AdmobAdFormat,
      AdmobLogger, RootViewControllerLocator, UnsafeTransfer.
- [x] Configuration layer: AdmobConfiguration, RuntimeMode, AdUnitIDMap (with
      Google test ID preset), AdmobConsentDebugSettings.
- [x] Bridge protocols: MobileAdsBridge, ConsentBridge, AdmobConsentSnapshot.
- [x] Live bridges: LiveMobileAdsBridge, LiveConsentBridge (UMP-backed).
- [x] AdmobConsentCoordinator (@Observable, MainActor, refresh + privacy options).
- [x] AdmobBootstrapper (idempotent start, reconcile after late consent grant).
- [x] AdmobBanner (large anchored adaptive sizing via onGeometryChange,
      rootViewController injection, no hard-coded 50pt).
- [x] AdmobBannerModifier (`.adBanner(.bottom)` via safeAreaInset).
- [x] AdmobInterstitialController (one-shot + autoReload).
- [x] AdmobRewardedController (reward callback bridged into Sendable AdmobReward).
- [x] AdmobRewardedInterstitialController (intro-screen responsibility documented).
- [x] AdmobAppOpenCoordinator (scenePhase aware, 4h expiration, cold-start guard).
- [x] FullScreenDelegateBridge (closure-based, hops to MainActor).
- [x] Tests: ConfigurationTests, ConsentCoordinatorTests, BootstrapperTests
      (14 tests across 3 suites, all passing).
- [x] README.md with installation + quick start.
- [x] docs/HOST_APP_SETUP.md (Info.plist keys, consent flow, app open guidance).

## Working Notes

- iOS 26 SDK was available locally at `iPhoneSimulator26.4.sdk`.
- Google Mobile Ads SPM resolves to 13.3.0; UMP transitively 3.1.0.
- Sendable warnings required wrapping the loaded ad pointer in
  `UnsafeTransfer<T>` before crossing the actor boundary in
  `withCheckedThrowingContinuation`. Pattern reused for all four full-screen
  controllers.
- `BannerHost.Coordinator` keeps MainActor isolation by hopping inside `Task {
  @MainActor in ... }` instead of capturing isolated properties from a
  nonisolated context.
- `currentOrientationAnchoredAdaptiveBanner(width:)` is deprecated in 13.3;
  switched to `largeAnchoredAdaptiveBanner(width:)`. Heights are slightly
  larger but Google recommends it for monetization.
- UMP `DebugGeography` has no `.notEEA` constant in 3.1.0; mapped to `.other`.
- `tasks/lessons.md` is intentionally not created yet — no postmortem from
  this phase. Lessons file should appear when a real correction happens.

## Results

- 19 Swift source files written across `Sources/SwiftUIAdmob/`.
- 3 test files written, 14 tests pass on iPhone 17 Pro / iOS 26 simulator.
- `xcodebuild build` exits 0, no warnings.
- `xcodebuild test` exits 0, all suites green.
- Docs updated: README.md and docs/HOST_APP_SETUP.md added.

## Out of Scope (Deferred to Phase 2)

- Native ad loading (`AdmobNativeAdLoader`) and reference SwiftUI templates.
- Sample app target.
- Mediation adapter wiring guides.
- `tasks/lessons.md` — write on first real correction.
