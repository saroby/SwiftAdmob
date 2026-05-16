# SwiftUIAdmob Architecture

## Status

This is the initial architecture document for `SwiftUIAdmob`, a Swift Package
Manager library for adding Google AdMob to SwiftUI apps. No package source code
has been created yet.

## Product Intent

`SwiftUIAdmob` should make common AdMob integration paths feel native in SwiftUI:

- App startup and SDK initialization that are explicit and testable.
- Consent-aware ad loading.
- SwiftUI-first banner placement.
- Async full-screen ad loading and presentation for interstitial, rewarded,
  rewarded interstitial, and app open ads.
- Small, predictable APIs that hide UIKit delegate noise without hiding AdMob
  policy responsibilities from the app developer.

Minimum supported platform: iOS 26.

## External Baseline

Checked on 2026-05-16 against current official sources:

- Google Mobile Ads iOS setup documents Xcode 16.0+ and iOS 13.0+ as SDK
  prerequisites. This package deliberately raises the consumer-facing minimum to
  iOS 26.
- Google's official SPM package is
  `https://github.com/googleads/swift-package-manager-google-mobile-ads.git`.
  The current repository package manifest exposes the `GoogleMobileAds` product,
  depends on `GoogleUserMessagingPlatform`, and currently points at Google Mobile
  Ads SDK 13.3.0.
- Host apps must provide `GADApplicationIdentifier` and `SKAdNetworkItems` in
  their `Info.plist`. A Swift package cannot reliably own those app-level
  declarations.
- `MobileAds.shared.start()` must run before loading ads. If consent or
  request-specific flags are required, resolve them before initializing or
  requesting ads.
- UMP consent flow should request consent information on each launch and gate ad
  requests with `ConsentInformation.shared.canRequestAds`.
- Official ad format docs cover banner, interstitial, rewarded, rewarded
  interstitial, app open, and native ads. Native ads remain app-rendered after
  the SDK returns the ad assets.

## Design Principles

- Keep the public surface SwiftUI-native, but do not pretend Google Mobile Ads
  is a SwiftUI framework. UIKit bridging stays inside implementation modules.
- Prefer explicit lifecycle calls over global magic. Apps should know when the
  SDK starts, when consent is gathered, and when an ad is requested.
- Treat consent, test mode, and production ad unit IDs as first-class state.
- Make invalid production use hard, especially accidental live ad requests in
  development.
- Use iOS 26-era Swift APIs freely: `async`/`await`, `@MainActor`, `Observation`,
  scene phase integration, and SwiftUI layout APIs.
- Avoid wrapping every Google SDK property. Expose stable workflows first and
  provide escape hatches only where the SDK surface is unlikely to stay hidden.

## Package Responsibility Boundary

`SwiftUIAdmob` owns:

- SwiftUI views and modifiers for supported ad placements.
- Async coordinators that load, present, and invalidate ad objects.
- Consent gating helpers around UMP.
- Test ad unit presets and fake loaders for package tests.
- Runtime diagnostics for missing configuration that the package can detect.
- Documentation that tells host apps which plist, privacy, and App Store fields
  they must maintain.

Host apps own:

- AdMob app registration and real ad unit IDs.
- `Info.plist` values: `GADApplicationIdentifier`, `SKAdNetworkItems`, and any
  app-specific privacy strings.
- App Store Connect data disclosures and privacy manifest review.
- ATT prompts, if the app chooses to request tracking authorization.
- Ad placement policy decisions: natural breaks, reward economics, frequency,
  user experience, and regional compliance.
- Mediation adapter dependency decisions. Re-check current Google mediation docs
  before implementation because adapter distribution can change independently of
  this package.

## Layered Design

The intended package should be organized around four layers:

1. Public SwiftUI API
   - Views, modifiers, environment values, and observable controllers that app
     developers use directly.
2. Lifecycle and state coordinators
   - `@MainActor` types that own ad state, consent state, loading state,
     expiration, and presentation safety.
3. Google SDK bridge
   - Small adapters around `GoogleMobileAds` and `GoogleUserMessagingPlatform`
     so tests can replace SDK calls without loading real ads.
4. Policy and diagnostics
   - Validation, test-mode guards, structured errors, and event reporting.

No layer above the SDK bridge should import UIKit directly except where SwiftUI
requires a representable boundary.

## Planned Public Concepts

### Configuration

`AdmobConfiguration` should describe:

- Runtime mode: test, production, or disabled.
- Test device IDs.
- Default request configuration.
- Ad unit ID map, preferably typed by ad format.
- Optional diagnostics callback or event sink.

The AdMob app ID should not be duplicated as ordinary runtime configuration
unless it is only used for diagnostics. The real source of truth remains the
host app's `Info.plist`.

### Startup

`AdmobBootstrapper` or an equivalent app-level service should provide one clear
startup flow:

1. Validate host configuration that can be checked at runtime.
2. Gather or refresh consent information.
3. Start Google Mobile Ads.
4. Mark ads as requestable only after consent and startup requirements are met.

Startup must be idempotent. Multiple SwiftUI scene creations should not start
the SDK or request consent repeatedly.

### Consent

`AdmobConsentCoordinator` should wrap UMP without hiding policy decisions:

- Refresh consent information at launch.
- Present required forms from the current UI context.
- Expose whether ads can be requested.
- Expose whether a privacy options entry point is required.
- Prevent duplicate ad request work when multiple consent checks return true.

The coordinator should not automatically show ATT prompts. ATT is an app-level
choice with copy, timing, and policy implications outside this package.

### Banner Ads

Banner support should be the first implementation slice.

The public API should make the common case easy:

- A SwiftUI banner view for anchored adaptive banners.
- A modifier for bottom or top safe-area placement.
- Optional placeholder, loading, and failure states.
- Width-driven sizing that updates when the container width changes.

The bridge should own:

- Creating the Google `BannerView`.
- Applying the ad unit ID and request.
- Computing anchored adaptive size from available width.
- Forwarding impression, click, load, and failure callbacks.

The SwiftUI layer should not hard-code a fixed 50 point height for adaptive
banners. Fixed-size banners can be a separate explicit mode.

### Interstitial Ads

Interstitial support should expose a load-then-present controller:

- Load ahead of the natural break.
- Present only when a valid ad and a presentation context are available.
- Clear the one-time-use ad after presentation or failure.
- Reload only when the app asks or an explicit policy says to.

The package should not decide where an interstitial belongs. The host app must
call presentation at natural transitions.

### Rewarded Ads

Rewarded support should follow the same one-time-use lifecycle as interstitials,
with one extra invariant:

- The app may grant rewards only from the SDK reward callback.

The API should make reward delivery explicit and should support server-side
verification custom data without requiring every app to use SSV.

### Rewarded Interstitial Ads

Rewarded interstitial support should stay separate from rewarded ads because the
user experience and policy requirements are different:

- The host app must show an intro screen that explains the reward and allows
  opt-out before presentation.
- The package can provide lifecycle helpers, but it should not fake the consent
  or intro-screen requirement.

### App Open Ads

App open ads should be scene-aware:

- Integrate with `scenePhase` or an explicit foreground event.
- Track ad load time and treat app open ads as expired after four hours.
- Avoid showing an app open ad after the main content is already interactive on
  cold start.
- Provide a way for apps to suppress app open ads during onboarding, purchases,
  login, or critical flows.

### Native Ads

Native ads should be a later milestone, not the first slice.

Because Google returns ad assets and the app is responsible for rendering them,
the package should focus on:

- Loading native ads.
- Exposing a Swift-friendly ad model.
- Providing optional reference SwiftUI templates.
- Preserving AdChoices, attribution, media, click, and impression requirements.

Native templates should be opt-in. The package should not force a visual style
that conflicts with the host app.

## Error and Event Model

Use structured package errors rather than leaking every SDK error directly
through the public API.

Recommended categories:

- Missing host app configuration.
- Consent not requestable.
- SDK not started.
- Ad unit ID missing for requested format.
- Load failure with wrapped SDK error.
- Presentation unavailable.
- Expired ad.
- Duplicate in-flight request.

Events should be observable for analytics and debugging:

- SDK started.
- Consent updated.
- Ad load started, succeeded, failed.
- Ad presented, dismissed, clicked, impressed.
- Reward earned.
- Diagnostic warning emitted.

Do not log full ad unit IDs by default in production diagnostics.

## Testing Strategy

Future implementation should be testable without live Google ad requests:

- Protocol-backed SDK bridge fakes for unit tests.
- Consent coordinator fakes for requestability scenarios.
- SwiftUI view tests for banner sizing and placeholder states.
- Lifecycle tests for one-time-use full-screen ads.
- Expiration tests for app open ads.
- Integration sample app that uses Google's test IDs only.

Live ad requests are not required for package tests. Sample/manual testing
should use Google-provided test ad unit IDs.

## Documentation Strategy

The package should eventually include:

- `README.md`: install, quick start, and host-app checklist.
- `docs/ARCHITECTURE.md`: this design document.
- `docs/LLM_CONTEXT.md`: concise context for future LLM agents.
- `docs/HOST_APP_SETUP.md`: plist, privacy, consent, test IDs, and App Store
  obligations.
- `Examples/`: only after the package source exists.

## Implementation Milestones

1. Package scaffold and dependency wiring.
2. Core configuration, diagnostics, startup, and consent gate.
3. Banner view and safe-area modifier.
4. Test fakes and unit tests for banner/startup/consent.
5. Interstitial and rewarded controllers.
6. App open coordinator.
7. Native ad loading and optional templates.
8. Example app and README quick start.

## Open Questions

- Should the first release include UMP consent UI, or only provide a gate and
  documented hooks?
- Should production mode require explicit real ad unit IDs at startup, or allow
  per-call IDs for dynamic apps?
- Should the package include an optional sample app target in the same
  repository or keep examples separate?
- Should native ad templates be part of the core product or a separate product
  target?
- How strict should runtime diagnostics be in release builds?

## References

- Google Mobile Ads SDK iOS setup:
  https://developers.google.com/admob/ios/quick-start
- Google Mobile Ads official SPM package:
  https://github.com/googleads/swift-package-manager-google-mobile-ads
- Google Mobile Ads SPM manifest:
  https://raw.githubusercontent.com/googleads/swift-package-manager-google-mobile-ads/main/Package.swift
- Banner ads:
  https://developers.google.com/admob/ios/banner
- UMP consent:
  https://developers.google.com/admob/ios/privacy
- Interstitial ads:
  https://developers.google.com/admob/ios/interstitial
- Rewarded ads:
  https://developers.google.com/admob/ios/rewarded
- Rewarded interstitial ads:
  https://developers.google.com/admob/ios/rewarded-interstitial
- App open ads:
  https://developers.google.com/admob/ios/app-open
- Native ads:
  https://developers.google.com/admob/ios/native
- App Store data disclosure:
  https://developers.google.com/admob/ios/privacy/data-disclosure
