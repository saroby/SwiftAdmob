# Changelog

All notable changes to SwiftUIAdmob are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.1] - 2026-05-24

### Changed

- `AdmobBanner` now uses the standard `AdSizeBanner` (320x50) instead of the
  large anchored adaptive variant. The previous large adaptive ad size
  produced ~100pt+ heights that overlapped bottom toolbars and floating
  buttons. Anchored adaptive APIs (both regular and large) are also Google's
  current recommendation but produce variable heights; 320x50 gives a
  predictable, non-deprecated baseline. `AdmobBanner.height(forWidth:)` now
  returns 50 for any positive width.

### Docs

- `SwiftUIAdmob` namespace and `AdmobBootstrapper` DocC now link to Google's
  official AdMob iOS quick-start
  (<https://developers.google.com/admob/ios/quick-start>) so host-app
  integrators (and AI coding agents reading the public API) are pointed at
  the upstream source of truth for `Info.plist` / `SKAdNetworkItems` /
  AdMob console setup.
- `docs/HOST_APP_SETUP.md` opens with an explicit "source of truth" callout
  that defers to Google's docs when they disagree with the local checklist.

## [1.0.0] - 2026-05-17

Initial public release.

### Added

- `Package.swift` — Swift 6 / iOS 26 minimum, depends on
  `googleads/swift-package-manager-google-mobile-ads` 13.3.0.
- `AdmobConfiguration`, `AdmobRuntimeMode`, `AdUnitIDMap` (with
  `AdUnitIDMap.googleTest` preset for development).
- `AdmobConsentDebugSettings` for UMP geography overrides.
- `MobileAdsBridge` and `ConsentBridge` protocols plus
  `LiveMobileAdsBridge` / `LiveConsentBridge` UMP-backed implementations.
- `AdmobConsentCoordinator` (`@MainActor @Observable`) with
  `refresh(from:debugSettings:)`, `presentPrivacyOptions(from:)`, and `reset`.
- `AdmobBootstrapper` (`@MainActor @Observable`) with idempotent `start` and
  `reconcile` for late consent grants.
- `AdmobBanner` SwiftUI view and `.adBanner(.top|.bottom)` modifier using
  `largeAnchoredAdaptiveBanner(width:)` with dynamic width tracking via
  `onGeometryChange`. Explicit re-load guard via `lastRequestedWidth`.
- `AdmobInterstitialController`, `AdmobRewardedController`,
  `AdmobRewardedInterstitialController` with `load`, `present`, optional
  `autoReload`, and one-shot lifecycle.
- `AdmobAppOpenCoordinator` with `handleScenePhaseChange`, 4-hour expiration,
  cold-start guard, and per-session `isSuppressed` flag.
- `FullScreenDelegateBridge` — closure-based `NSObject` bridge so each
  controller hops back to `@MainActor` from non-isolated SDK delegate
  callbacks.
- `AdmobError`, `AdmobEvent`, `AdmobEventSink`, `AdmobLogger` with `OSLog`
  privacy annotations and no ad-unit-ID leakage by default.
- `RootViewControllerLocator.find()` — topmost view controller resolver for
  banners and full-screen presentation.
- Unit tests: `ConfigurationTests`, `ConsentCoordinatorTests`,
  `BootstrapperTests` (14 tests across 3 suites, all passing).
- Docs: `README.md`, `docs/HOST_APP_SETUP.md`, `docs/ARCHITECTURE.md`,
  `docs/LLM_CONTEXT.md`.

### Fixed (during review pass)

- Banner `Coordinator` no longer captures stale closures across SwiftUI
  re-renders. `eventSink` and `onEvent` are refreshed in `updateUIView`
  before any early return.
- Banner click events now fire — added missing
  `bannerViewDidRecordClick(_:)` delegate implementation.
- Banner hides its `BannerView` when `bootstrapper.canRequestAds` becomes
  `false` mid-session (consent revoked, etc.) so no impressions accrue on a
  stale ad surface.
- All full-screen controllers (`Interstitial`, `Rewarded`,
  `RewardedInterstitial`) now throw `AdmobError.duplicateRequest(...)` if
  `present()` is called while another presentation is in flight, preventing
  the previous `CheckedContinuation` from leaking.
- Rewarded reward callbacks (`ad.present(from:) { ... }`) now hop to
  `@MainActor` via `Task` before touching actor-isolated state instead of
  assuming the SDK invokes them on the main thread.

### Notes

- Native ad loading and reference SwiftUI templates remain out of scope for
  1.0; deferred to a later milestone.
- No example app target ships with the package; see `README.md` Quick Start
  for inline snippets covering banner, interstitial, rewarded, app open, and
  consent flows.
