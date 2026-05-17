# SwiftUIAdmob — AI Usage Guide

For AI coding agents (Claude Code, Cursor, Copilot) generating integration
code into a host SwiftUI app, and for humans pair-programming with one.

If you only read one file in this package, read this one. The patterns
below are copy-paste safe against v1.0.0 and verified by tests in
`Tests/SwiftUIAdmobTests/UsageExamplesTests.swift` — so they cannot
silently rot.

---

## 5-Minute Integration

```swift
import SwiftUI
import SwiftUIAdmob

@main
struct MyApp: App {
    @State private var bootstrapper = AdmobBootstrapper(
        configuration: .development(),       // Uses Google test IDs.
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
            .adBanner(.bottom)               // Bottom banner with safe-area inset.
    }
}
```

Host-app responsibilities (`Info.plist`, ATT prompt timing, placement
policy) live in [`HOST_APP_SETUP.md`](HOST_APP_SETUP.md). The package
cannot configure them for you.

---

## Decision Tree: Which API?

```
Persistent inline ad in a screen?
└─> AdmobBanner / .adBanner(.bottom | .top)

Full-screen ad at a natural break (level end, screen transition)?
└─> AdmobInterstitialController

Full-screen ad in exchange for an in-app reward (coins, hints, lives)?
└─> AdmobRewardedController
    └─> Grant the reward only from the AdmobReward? returned by present().

Reward ad shown like an interstitial (unsolicited, with intro)?
└─> AdmobRewardedInterstitialController
    └─> You MUST show your own intro/opt-out screen first (AdMob policy).

Ad on app foreground after backgrounding?
└─> AdmobAppOpenCoordinator
    └─> Wire .onChange(of: scenePhase) { _, phase in coordinator.handleScenePhaseChange(phase) }
    └─> Suppress during onboarding / IAP / login with isSuppressed = true.

Native ad (custom layout)?
└─> Not in 1.0.0 — deferred to a later milestone.
```

---

## Banner

### ✅ Do

```swift
struct ContentScreen: View {
    var body: some View {
        ScrollView { /* content */ }
            .adBanner(.bottom)               // Adaptive, safe-area aware.
    }
}
```

For inline placement (e.g. between feed items):

```swift
AdmobBanner(adUnitID: AdUnitIDMap.googleTest.banner) { event in
    switch event {
    case .loaded:  /* analytics */ break
    case .failed:  /* fallback UI */ break
    case .impressed, .clicked: break
    }
}
```

### ❌ Don't

```swift
// ❌ Hard-coded height — adaptive banners size by width.
AdmobBanner().frame(height: 50)

// ❌ Conditioning on a stale ad-unit-ID literal.
AdmobBanner(adUnitID: "ca-app-pub-3940256099942544/2934735716") // copy-paste rot risk

// ❌ Skipping the bootstrapper in the environment.
RootView().adBanner(.bottom) // AdmobBanner reads AdmobBootstrapper from @Environment
```

---

## Interstitial

### ✅ Do

```swift
struct GameOverView: View {
    @State private var interstitial = AdmobInterstitialController(
        adUnitID: AdUnitIDMap.googleTest.interstitial!
    )

    var body: some View {
        Button("Next Round") {
            Task {
                try? await interstitial.present()    // Throws on no-ad/no-presenter.
                continueGame()                       // Always run gameplay continuation.
            }
        }
        .task { await interstitial.load() }          // Preload at natural opportunity.
    }
}
```

### ❌ Don't

```swift
// ❌ Show on every screen transition. Violates AdMob policy and burns users.
.onAppear { Task { try? await interstitial.present() } }

// ❌ Block gameplay on present() success — present() failure is normal.
try await interstitial.present()         // throws on no-ad/no-presenter
continueGame()                           // never runs if user has no network

// ❌ Re-use after present() without load(). Interstitials are ONE-SHOT.
try? await interstitial.present()
try? await interstitial.present()        // second call: AdmobError.presentationUnavailable
// (autoReload: true (default) reloads after dismiss — but not synchronously)
```

---

## Rewarded

### ✅ Do

```swift
struct ShopView: View {
    @State private var rewarded = AdmobRewardedController(
        adUnitID: AdUnitIDMap.googleTest.rewarded!
    )
    @State private var coins = 0

    var body: some View {
        Button("Watch ad for 10 coins") {
            Task {
                guard let reward = try? await rewarded.present() else { return }
                // Grant the in-app benefit only when reward is non-nil.
                coins += Int(truncatingIfNeeded: NSDecimalNumber(decimal: reward.amount).intValue)
            }
        }
        .disabled(!rewarded.isReady)
        .task { await rewarded.load() }
    }
}
```

### ❌ Don't

```swift
// ❌ Grant the reward on dismiss / before present() completes.
try? await rewarded.present()
coins += 10                              // user may have skipped the ad

// ❌ Grant the reward inside the FullScreenContentDelegate callback you
//    implemented yourself. The controller already drives reward via SDK.

// ❌ Trust isReady alone for premium economy decisions — the user can
//    still close the ad early.
```

---

## Rewarded Interstitial

Same lifecycle as `AdmobRewardedController`. **AdMob policy requires** an
intro screen explaining the reward and offering opt-out **before** the ad
shows. The package does **not** enforce this.

### ✅ Do

```swift
struct LevelClearedView: View {
    @State private var rewardedInterstitial = AdmobRewardedInterstitialController(
        adUnitID: AdUnitIDMap.googleTest.rewardedInterstitial!
    )
    @State private var showIntro = false

    var body: some View {
        EmptyView()
            .task { await rewardedInterstitial.load() }
            .onAppear { showIntro = true }
            .sheet(isPresented: $showIntro) {
                IntroScreen(
                    onAccept: {
                        showIntro = false
                        Task {
                            _ = try? await rewardedInterstitial.present()
                        }
                    },
                    onDecline: { showIntro = false }
                )
            }
    }
}
```

### ❌ Don't

```swift
// ❌ Present without an intro screen — fails AdMob policy review.
.task {
    await rewardedInterstitial.load()
    _ = try? await rewardedInterstitial.present()   // direct present
}
```

---

## App Open

### ✅ Do

```swift
@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var bootstrapper = AdmobBootstrapper(configuration: .development())
    @State private var appOpen = AdmobAppOpenCoordinator(
        adUnitID: AdUnitIDMap.googleTest.appOpen!
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bootstrapper)
                .task { await bootstrapper.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            appOpen.handleScenePhaseChange(phase)
        }
    }
}

// Suppress during sensitive flows.
struct OnboardingFlow: View {
    @State private var appOpen: AdmobAppOpenCoordinator
    var body: some View {
        OnboardingContent()
            .onAppear { appOpen.isSuppressed = true }
            .onDisappear { appOpen.isSuppressed = false }
    }
}
```

### ❌ Don't

```swift
// ❌ Show app open ad on cold start before the user sees the app.
// (handleScenePhaseChange already prevents this; don't bypass with manual showIfAvailable.)
.onAppear { appOpen.showIfAvailable() }

// ❌ Show during a purchase, login, or onboarding flow.
// (Forgetting to set isSuppressed = true degrades UX.)

// ❌ Cache the ad past 4 hours.
// (The coordinator already enforces AdmobAppOpenCoordinator.expiration.)
```

---

## Consent

### ✅ Do

```swift
struct SettingsView: View {
    @Environment(AdmobBootstrapper.self) private var bootstrapper

    var body: some View {
        Form {
            if bootstrapper.consent.isPrivacyOptionsRequired {
                Button("Privacy options") {
                    Task {
                        guard let vc = RootViewControllerLocator.find() else { return }
                        await bootstrapper.consent.presentPrivacyOptions(from: vc)
                        await bootstrapper.reconcile()    // Late consent grant → start SDK.
                    }
                }
            }
        }
    }
}
```

### ❌ Don't

```swift
// ❌ Manually call ConsentInformation.shared.requestConsentInfoUpdate.
// (AdmobConsentCoordinator handles it. Double-requesting risks duplicate ads.)

// ❌ Skip reconcile() after the user grants consent late.
// (Bootstrapper won't start the SDK without reconcile or another start() call.)

// ❌ Trust canRequestAds without calling start() first.
// (canRequestAds requires runtimeMode + isStarted + consent.)
```

---

## AdmobError → Fix Cheat Sheet

Every `AdmobError` case exposes `recoverySuggestion` via `LocalizedError`.
Log it. AI agents reading the log can usually self-correct.

| Error case                         | Most common cause                                            | Quick fix                                                            |
|------------------------------------|--------------------------------------------------------------|----------------------------------------------------------------------|
| `.missingHostConfiguration`        | `Info.plist` missing `GADApplicationIdentifier`              | Add it. See `HOST_APP_SETUP.md`.                                     |
| `.sdkNotStarted`                   | Forgot `await bootstrapper.start()`                          | Add `.task { await bootstrapper.start() }` to root scene.            |
| `.consentNotResolved`              | UMP form not yet completed                                   | `await bootstrapper.start()` again; check `canRequestAds`.           |
| `.missingAdUnitID(format)`         | Controller built with no ID and config lacks one             | Pass `adUnitID:` explicitly or set `adUnits.<format>`.               |
| `.loadFailed(format, message)`     | No fill / network / wrong unit                               | Retry after a delay. Verify unit in AdMob console.                   |
| `.presentationUnavailable(reason)` | `isReady == false`, no VC, or duplicate present              | Call `load()`, await `isReady`, ensure a presenter exists.           |
| `.adExpired(format)`               | App-open ad older than 4 hours                               | `load()` again. Coordinator drops the stale ad.                      |
| `.duplicateRequest(format)`        | Two `present()` calls overlapping                            | Await the first before invoking the second.                          |
| `.disabledByConfiguration`         | `runtimeMode == .disabled`                                   | Use `.development()` or `.production(...)` configuration.            |

---

## Anti-Pattern Summary (one-liners)

- ❌ Hard-coding `50pt` banner height.
- ❌ Re-presenting a full-screen controller without `load()`.
- ❌ Granting rewards outside the `AdmobReward?` returned by `present()`.
- ❌ Showing rewarded interstitial without an intro/opt-out screen.
- ❌ Showing app-open ad on the first cold-start `.active`.
- ❌ Calling `bootstrapper.start()` from a background task without awaiting.
- ❌ Logging raw production ad-unit IDs.
- ❌ Skipping `bootstrapper.reconcile()` after the user grants late consent.
- ❌ Using production ad unit IDs in Debug builds.
- ❌ Asking `MobileAds.shared.start()` directly — `AdmobBootstrapper` owns it.

---

## See Also

- [`HOST_APP_SETUP.md`](HOST_APP_SETUP.md) — Info.plist, ATT, AdMob console, App Store privacy.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — design rationale and layered design.
- [`LLM_CONTEXT.md`](LLM_CONTEXT.md) — public API map and invariants.
- [`../CHANGELOG.md`](../CHANGELOG.md) — what changed across releases.
