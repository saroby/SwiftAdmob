# SwiftUIAdmob

A thin, SwiftUI-first Swift Package Manager layer over the official Google Mobile
Ads SDK and User Messaging Platform (UMP) SDK. Targets **iOS 26+** and **Swift 6**.

`SwiftUIAdmob` aims to reduce the boilerplate of integrating AdMob into SwiftUI
apps without hiding the policy and configuration responsibilities that belong
to the host app.

## Status

Version **1.0.2**. See `docs/ARCHITECTURE.md` and `docs/LLM_CONTEXT.md` for
design rationale and `docs/HOST_APP_SETUP.md` for required host-app integration.

## Features

- `AdmobBootstrapper` — idempotent SDK startup that gates on UMP consent.
- `AdmobConsentCoordinator` — observable consent state, refresh, and privacy
  options form presentation.
- `AdmobBanner` + `.adBanner(_:)` modifier — adaptive banner that resizes with
  the container width and never hard-codes `50pt`.
- `AdmobVerticalBanner` — fixed 120x600 `Skyscraper` slot for sidebar
  layouts (AdMob has no true "vertical adaptive" format).
- `AdmobInterstitialController`, `AdmobRewardedController`,
  `AdmobRewardedInterstitialController` — async `load` + `present`, one-shot
  semantics, and optional auto-reload after dismissal.
- `AdmobAppOpenCoordinator` — scene-phase aware, 4-hour expiration, cold-start
  guard, and a per-session suppression flag.
- Sendable `AdmobEvent` / `AdmobEventSink` for analytics piping.
- Protocol-backed `MobileAdsBridge` and `ConsentBridge` so unit tests can avoid
  live Google ad requests.

Native ads are intentionally deferred to a later milestone.

## Installation

In your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/SwiftUIAdmob.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SwiftUIAdmob", package: "SwiftUIAdmob")
    ])
]
```

In Xcode, add the package via *File → Add Package Dependencies…* and pick the
`SwiftUIAdmob` library product.

## Host App Setup (mandatory)

`SwiftUIAdmob` cannot own these — your app must:

1. Add `GADApplicationIdentifier` to `Info.plist` (your real AdMob App ID).
2. Add `SKAdNetworkItems` to `Info.plist` (Google publishes the current list).
3. Add `NSUserTrackingUsageDescription` if you call `ATTrackingManager`.
4. Register the app and ad units in the AdMob console.
5. Decide whether to request ATT, and where in your onboarding flow it fits.
6. Decide on natural break points for interstitial / rewarded ads.

See `docs/HOST_APP_SETUP.md` for the full checklist.

## Quick Start

```swift
import SwiftUI
import SwiftUIAdmob

@main
struct DemoApp: App {
    @State private var bootstrapper = AdmobBootstrapper(
        configuration: .development(),
        eventSink: .logging()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bootstrapper)
                .task { await bootstrapper.start() }
        }
    }
}

struct RootView: View {
    var body: some View {
        ContentView()
            .adBanner(.bottom)
    }
}
```

### Interstitial

```swift
struct GameOverView: View {
    @State private var interstitial = AdmobInterstitialController(
        adUnitID: AdUnitIDMap.googleTest.interstitial!
    )

    var body: some View {
        Button("Next Round") {
            Task {
                try? await interstitial.present()
                continueGame()
            }
        }
        .task { await interstitial.load() }
    }
}
```

### Rewarded

```swift
struct ShopView: View {
    @State private var rewarded = AdmobRewardedController(
        adUnitID: AdUnitIDMap.googleTest.rewarded!
    )
    @State private var coins = 0

    var body: some View {
        Button("Watch ad for 10 coins") {
            Task {
                if let reward = try? await rewarded.present() {
                    coins += Int(truncatingIfNeeded: (reward.amount as NSDecimalNumber).intValue)
                }
            }
        }
        .disabled(!rewarded.isReady)
        .task { await rewarded.load() }
    }
}
```

### App open

```swift
@main
struct DemoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootstrapper = AdmobBootstrapper(configuration: .development())
    @State private var appOpen = AdmobAppOpenCoordinator(
        adUnitID: AdUnitIDMap.googleTest.appOpen!
    )

    var body: some Scene {
        WindowGroup { ContentView().environment(bootstrapper) }
            .onChange(of: scenePhase) { _, phase in
                appOpen.handleScenePhaseChange(phase)
            }
    }
}
```

### Consent

```swift
struct SettingsView: View {
    @Environment(AdmobBootstrapper.self) private var bootstrapper

    var body: some View {
        Form {
            if bootstrapper.consent.isPrivacyOptionsRequired {
                Button("Privacy options") {
                    Task {
                        if let vc = RootViewControllerLocator.find() {
                            await bootstrapper.consent.presentPrivacyOptions(from: vc)
                            await bootstrapper.reconcile()
                        }
                    }
                }
            }
        }
    }
}
```

## Testing

Unit tests use [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
and a pair of fakes (`FakeMobileAdsBridge`, `FakeConsentBridge`) so no real ad
requests are made.

```bash
swift test
```

## License

MIT (see LICENSE — to be added).
