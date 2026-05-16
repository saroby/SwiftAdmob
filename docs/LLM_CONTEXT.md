# SwiftUIAdmob LLM Context

## One-Screen Summary

`SwiftUIAdmob` is intended to be a Swift Package Manager library that makes
Google AdMob easier to use from SwiftUI apps.

The package name is `SwiftUIAdmob`.

The minimum supported platform is iOS 26.

The project currently contains documentation only. Do not assume a package
scaffold, source target, tests, or examples already exist.

## Current Repository State

- `docs/ARCHITECTURE.md` contains the product architecture and implementation
  direction.
- `docs/LLM_CONTEXT.md` is this high-level orientation document.
- `tasks/todo.md` tracks the current documentation-only task.
- No `Package.swift` exists yet.
- No Swift source files exist yet.
- No tests exist yet.
- The directory is not currently initialized as a git repository.

## Primary Goal

Build a thin, reliable SwiftUI layer over Google Mobile Ads for iOS 26 apps.
The library should reduce boilerplate, not hide AdMob responsibilities that
belong to the host app.

## Non-Negotiable Constraints

- Do not create code unless the user explicitly asks for implementation.
- Keep the package SwiftUI-first at the public API boundary.
- Keep UIKit and Google delegate machinery behind bridge/coordinator types.
- Treat consent as a first-class gate before ad requests.
- Keep host-app responsibilities explicit.
- Use Google test ad unit IDs for examples and manual testing.
- Avoid live production ad requests in tests.
- Do not hard-code a fixed banner height for adaptive banners.
- Do not make App Store privacy or ATT claims that the package cannot guarantee.

## Host App Responsibilities

Future implementation and docs must keep these outside the package:

- Registering the app in AdMob.
- Supplying real ad unit IDs.
- Adding `GADApplicationIdentifier` to `Info.plist`.
- Adding `SKAdNetworkItems` to `Info.plist`.
- Reviewing App Store Connect data disclosure.
- Deciding whether and when to request ATT authorization.
- Choosing ad placement timing and frequency.
- Making mediation dependency decisions.

## Planned Package Responsibilities

The package should provide:

- Runtime configuration for test, production, and disabled modes.
- SDK startup orchestration.
- UMP consent coordination.
- SwiftUI banner views and placement modifiers.
- Async full-screen ad controllers.
- App open ad coordination.
- Native ad loading support in a later milestone.
- Structured diagnostics and lifecycle events.
- Fakes or protocol-backed bridges for tests.

## Important External Assumptions

These were checked on 2026-05-16:

- Official Google Mobile Ads iOS setup requires Xcode 16.0+ and targets iOS
  13.0+ at the SDK level. This package intentionally requires iOS 26.
- Official Google Mobile Ads SPM package URL:
  `https://github.com/googleads/swift-package-manager-google-mobile-ads.git`
- Current official package manifest exposes the `GoogleMobileAds` product,
  depends on `GoogleUserMessagingPlatform`, and points to Google Mobile Ads SDK
  13.3.0.
- Google setup docs require host apps to add `GADApplicationIdentifier` and
  `SKAdNetworkItems`.
- Google UMP docs require checking `ConsentInformation.shared.canRequestAds`
  before requesting ads.

Re-check official Google docs before implementing because SDK APIs and policy
guidance can change.

## Architecture Keywords

Use these names consistently unless there is a strong reason to change them:

- `AdmobConfiguration`
- `AdmobBootstrapper`
- `AdmobConsentCoordinator`
- `AdmobBanner`
- `AdmobInterstitialController`
- `AdmobRewardedController`
- `AdmobRewardedInterstitialController`
- `AdmobAppOpenCoordinator`
- `AdmobNativeAdLoader`
- `AdmobEvent`
- `AdmobError`

The exact public API is not final, but these names express the intended
boundaries.

## Recommended Implementation Order

1. Create `Package.swift` with iOS 26 minimum and Google Mobile Ads dependency.
2. Add configuration, diagnostics, and SDK bridge protocols.
3. Add consent coordinator with fakeable UMP bridge.
4. Add banner view as the first vertical slice.
5. Add tests for configuration, consent gating, and banner sizing.
6. Add interstitial and rewarded controllers.
7. Add app open coordination.
8. Add native ad loading and optional templates.
9. Add README and host-app setup guide.
10. Add example app only after the core API is stable.

## Verification Expectations

When implementation begins, a change is not done until it has a verification
story.

Preferred checks:

- `swift build`
- `swift test`
- Example app build on an iOS simulator when examples exist.
- Manual verification with Google test ad IDs only when UI behavior is involved.

If no package scaffold exists, do not claim build or test verification.

## Common Pitfalls

- Starting Google Mobile Ads before consent-sensitive flags are resolved.
- Loading ads twice because multiple consent callbacks report requestability.
- Treating full-screen ads as reusable after presentation.
- Showing interstitials outside natural breaks.
- Granting rewarded benefits outside the SDK reward callback.
- Showing app open ads after the main content is already interactive.
- Forgetting app open ad expiration.
- Rendering native ads without preserving required attribution and AdChoices UI.
- Assuming an SPM package can fix missing host app `Info.plist` keys.
- Logging real ad unit IDs in production diagnostics.

## Source Of Truth

For product direction, read:

1. `docs/ARCHITECTURE.md`
2. `docs/LLM_CONTEXT.md`
3. User's latest request in the active conversation

For Google SDK behavior, use official Google documentation and the official
Google SPM package manifest. Do not rely on old blog posts or third-party
tutorials without verifying against current official sources.
