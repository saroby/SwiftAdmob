# Lessons

Postmortem-style notes from corrections and surprises during SwiftUIAdmob
development. Read before starting non-trivial work to avoid repeating mistakes.

## 1. Google Mobile Ads SDK 13.3 has native `async throws -> sending T` load APIs

**Failure mode:** Initially wrapped `InterstitialAd.load`, `RewardedAd.load`,
`RewardedInterstitialAd.load`, and `AppOpenAd.load` with
`withCheckedThrowingContinuation` plus a custom `UnsafeTransfer<T>` shim because
the loaded ad value (non-Sendable class) was being passed across actor boundaries
through the continuation.

**Detection signal:** Swift 6 build error
`sending 'ad' risks causing data races` at `RewardedController.swift:52`.

**Root cause:** Did not read the SDK headers. The Objective-C declarations
already carry `NS_SWIFT_SENDING`:

```objc
+ (void)loadWithAdUnitID:(nonnull NSString *)adUnitID
                 request:(nullable GADRequest *)request
       completionHandler:(nonnull GADInterstitialAdLoadCompletionHandler)completionHandler
    NS_SWIFT_NAME(load(with:request:completionHandler:))NS_SWIFT_SENDING;
```

That attribute tells Swift to synthesize an `async throws` overload whose
return value is `sending`, so no manual continuation wrapping or shim type is
needed. Google's own SwiftUI sample uses:

```swift
interstitialAd = try await InterstitialAd.load(
    with: "ca-app-pub-...", request: Request())
```

**Prevention rule:** Before writing `withCheckedThrowingContinuation` around any
SDK callback, check the `.h` headers for `NS_SWIFT_ASYNC` /
`NS_SWIFT_SENDING` / `NS_SWIFT_NAME` and the existing `.swiftinterface` for an
auto-generated `async` overload. If one exists, use it directly.

**Where to look:**
- DerivedData → `…/GoogleMobileAds.framework/Headers/`
- Or run `grep -rE "load\(with" <framework path>/Headers`

## 2. SwiftUI `UIViewRepresentable.Coordinator` keeps stale captures unless explicitly refreshed

**Failure mode:** `BannerHost.Coordinator` stored its `eventSink` and `onEvent`
closure as `let`. Each SwiftUI re-render produced a new `BannerHost` struct
with potentially fresh closure captures, but `makeCoordinator()` only fires
once per representable lifetime, so the coordinator kept invoking the closure
captured at first mount.

**Detection signal:** Code review by Codex (`/codex consult`). Symptoms in
practice would be subtle: parent `@State` mutations referenced inside the
`onEvent` closure use stale values.

**Root cause:** Misunderstood the `UIViewRepresentable` contract. `makeUIView`
and `makeCoordinator` are one-shot; `updateUIView` is the place to push fresh
data into the coordinator on every render.

**Prevention rule:** Any value the coordinator forwards (closures, sinks,
configuration) must be `var` on the coordinator and reassigned at the top of
`updateUIView` *before* any early return. Tested in `Banner.swift:124` after
the fix.

## 3. Always check the delegate set for full coverage — defined event ≠ wired event

**Failure mode:** `AdmobBannerEvent.clicked` was defined in the public event
enum but `BannerViewDelegate.bannerViewDidRecordClick(_:)` was never
implemented, so the click event could never fire. Dead code path that looked
healthy from outside.

**Detection signal:** Codex consult flagged it during review.

**Prevention rule:** When defining a public event enum that mirrors an SDK
delegate, write a one-line correspondence table in code comments or tests, and
verify every enum case has at least one production call site.

## 4. `present()` style APIs need explicit duplicate-call guards even on `@MainActor`

**Failure mode:** `AdmobInterstitialController.present` stored its
`CheckedContinuation` in a `var pendingPresent`. A second concurrent call
would overwrite the first continuation and leak it forever (continuation never
resumes → caller hangs).

**Detection signal:** Codex consult flagged it during review.

**Root cause:** Being on `@MainActor` serializes writes but does not prevent
two awaiting callers from both reaching the `pendingPresent = continuation`
assignment in the second-then-first pattern when interleaved across `await`
points.

**Prevention rule:** Any continuation-storing `async` method on `@MainActor`
must guard `pendingPresent == nil` at the top and throw a dedicated
`duplicateRequest` error. Same applies to rewarded / rewarded-interstitial.

## 5. AdMob SDK callbacks: do not assume main-thread invocation, hop explicitly

**Failure mode:** `RewardedController.present`'s reward closure
(`ad.present(from:) { ... }`) wrote `self.earnedReward` and called
`self.eventSink.send(...)` directly. The closure is invoked by the SDK at an
unspecified thread; Google's own sample assumes main but does not document it.

**Detection signal:** Codex consult flagged risk under Swift 6 strict
concurrency.

**Prevention rule:** Inside any SDK callback that touches `@MainActor` state,
copy out only Sendable primitive values (e.g. `Decimal`, `String`) and hop to
`Task { @MainActor in ... }` before mutating actor-isolated properties.
Implemented in `RewardedController.swift` and
`RewardedInterstitialController.swift`.
