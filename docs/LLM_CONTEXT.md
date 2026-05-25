# SwiftUIAdmob — LLM Context

Optimised orientation for AI coding agents (Claude Code, Cursor, Copilot)
working in this repository or integrating this package into a host app.

For copy-pasteable usage patterns, read **`docs/AI_USAGE.md`** first. This
file is the conceptual map; `AI_USAGE.md` is the cookbook.

## Current State (2026-05-24)

- **Version**: 1.0.1, released. Public API is stable — do not rename or
  break signatures.
- **Platform**: iOS 26 minimum, Swift 6 strict concurrency.
- **Dependency**: Google Mobile Ads SDK 13.3.0 via
  `https://github.com/googleads/swift-package-manager-google-mobile-ads.git`.
- **Source**: 13 files under `Sources/SwiftUIAdmob/`.
- **Tests**: Swift Testing suites under `Tests/SwiftUIAdmobTests/`. Live
  Google ad requests are never made — `FakeMobileAdsBridge` and
  `FakeConsentBridge` cover the testable surface.

## Public API at a Glance

| Type                                   | Purpose                                                                              |
|----------------------------------------|--------------------------------------------------------------------------------------|
| `AdmobConfiguration`                   | Runtime mode (`.test` / `.production` / `.disabled`), ad unit IDs, debug settings.   |
| `AdUnitIDMap` + `.googleTest`          | Typed ad unit ID map. `.googleTest` ships Google's test IDs for local dev.           |
| `AdmobBootstrapper` (`@Observable`)    | Idempotent SDK + consent startup. Drives `canRequestAds`.                            |
| `AdmobConsentCoordinator` (`@Observable`) | UMP wrapper: refresh, present required form, present privacy options, reset.     |
| `AdmobBanner` + `.adBanner(_:)`        | Fixed 320x50 SwiftUI banner. Bottom/top safe-area modifier.                          |
| `AdmobAdaptiveBanner` + `.adAdaptiveBanner(_:)` | Anchored-adaptive SwiftUI banner (50–150pt height). Bottom/top safe-area modifier. |
| `AdmobVerticalBanner`                  | Fixed 120x600 (`AdSizeSkyscraper`) SwiftUI banner for sidebar / tall slots.          |
| `AdmobInterstitialController`          | Async `load`/`present`, one-shot, optional `autoReload`.                             |
| `AdmobRewardedController`              | Same lifecycle as interstitial; `present()` returns the earned `AdmobReward?`.       |
| `AdmobRewardedInterstitialController`  | Like rewarded, but **host must show intro screen** before `present()`.               |
| `AdmobAppOpenCoordinator`              | Scene-phase aware, 4-hour expiration, cold-start guard, per-session suppression.     |
| `MobileAdsBridge` / `ConsentBridge`    | Protocol seams. `Live*` implementations talk to Google; fakes power tests.           |
| `AdmobEvent` + `AdmobEventSink`        | Sendable event pipeline for analytics. `.logging(label:)` writes through `OSLog`.    |
| `AdmobError` (`LocalizedError`)        | Structured failures with `errorDescription` + `recoverySuggestion` + `failureReason`.|
| `RootViewControllerLocator.find()`     | Topmost VC resolver for banners and full-screen presentation.                        |

## Core Invariants — AI Must NOT Violate

1. **Consent gates ads**. Never load or request ads when
   `bootstrapper.canRequestAds == false`. The bootstrapper enforces this for
   banners; full-screen controllers trust the caller.
2. **Full-screen ads are one-shot**. `Interstitial`/`Rewarded`/
   `RewardedInterstitial` discard the underlying `Ad` after present or
   failure. Call `load()` again — or rely on `autoReload: true` (default).
3. **Rewarded benefit must come from the SDK reward callback**. The package
   exposes this as the value returned from `present()` (`AdmobReward?`). Grant
   the in-app reward only when that value is non-nil. Never grant on dismiss.
4. **App-open ads expire after 4 hours**
   (`AdmobAppOpenCoordinator.expiration`). The coordinator handles this
   internally — do not cache the underlying ad.
5. **App-open cold-start guard**. `handleScenePhaseChange(_:)` consumes the
   first `.active` as a load trigger only. Do not bypass this with manual
   `showIfAvailable` calls during initial launch.
6. **Suppress app-open during onboarding / IAP / login** by setting
   `coordinator.isSuppressed = true`. Restore afterwards.
7. **Rewarded Interstitial intro screen** is AdMob policy — the host app
   must show it. The package does not enforce it; missing it can fail review.
8. **Banner sizing depends on the view**. `AdmobBanner` is fixed 320x50.
   `AdmobAdaptiveBanner` has a dynamic height (50–150pt) — use
   `AdmobAdaptiveBanner.height(forWidth:)` to reserve space; never
   hard-code a height on it. `AdmobVerticalBanner` is fixed 120x600.
9. **Bootstrapper is idempotent**. Call `await bootstrapper.start()` from
   every scene's `.task` — concurrent and repeat calls await the same task.
10. **Do not log raw production ad unit IDs**. `AdmobLogger` keeps them out of
    its own output; sinks added by host apps must do the same.

## Host App Responsibilities (Out of Scope for This Package)

- `GADApplicationIdentifier` and `SKAdNetworkItems` in `Info.plist`.
- AdMob console: register bundle ID, create ad units, publish UMP messages.
- `ATTrackingManager.requestTrackingAuthorization` timing and copy.
- Ad placement policy: natural breaks, frequency, reward economics.
- App Store Connect privacy disclosures.
- Mediation adapter dependency decisions.

See `docs/HOST_APP_SETUP.md` for the full checklist.

## Where To Look Next

| Question                                              | File                                |
|-------------------------------------------------------|-------------------------------------|
| "How do I add a rewarded ad?"                         | `docs/AI_USAGE.md`                  |
| "What does the host app need in Info.plist?"          | `docs/HOST_APP_SETUP.md`            |
| "Why was this designed this way?"                     | `docs/ARCHITECTURE.md`              |
| "What changed in this release?"                       | `CHANGELOG.md`                      |
| "What error means what?"                              | `Sources/SwiftUIAdmob/Support.swift` (see `recoverySuggestion`) |
| "How are tests structured?"                           | `Tests/SwiftUIAdmobTests/`          |

## Source-of-Truth Precedence

When sources disagree:

1. The current `Sources/SwiftUIAdmob/*.swift` files.
2. `CHANGELOG.md` for the latest release.
3. `docs/AI_USAGE.md` for usage patterns.
4. `docs/ARCHITECTURE.md` for design rationale.
5. This document (`LLM_CONTEXT.md`) — orientation only.

If this document conflicts with the code, the code wins. File an issue (or
update this file in the same PR).
