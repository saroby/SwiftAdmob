# Host App Setup

`SwiftUIAdmob` is a Swift Package. There are a handful of things it cannot
configure on your behalf — your application target must own them.

## 1. `Info.plist`

### Required

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
```

Without `GADApplicationIdentifier`, the Google Mobile Ads SDK fatal-asserts on
start. Use the test ID `ca-app-pub-3940256099942544~1458002511` during local
development.

```xml
<key>SKAdNetworkItems</key>
<array>
    <!-- Copy the current list from Google's docs:
         https://developers.google.com/admob/ios/quick-start#update-your-infoplist
    -->
</array>
```

Google updates the `SKAdNetworkItems` list periodically. Re-check before each
release.

### Optional, only if you call ATT

```xml
<key>NSUserTrackingUsageDescription</key>
<string>광고 개인화를 위해 사용됩니다. 데이터는 제3자와 공유되지 않습니다.</string>
```

`SwiftUIAdmob` does not call `ATTrackingManager.requestTrackingAuthorization`.
That timing and copy is a host-app decision with App Store review implications.

## 2. AdMob console

- Register the bundle ID.
- Create the ad units you intend to use.
- For UMP, configure a GDPR / regulated US state message under
  *Privacy & messaging* and **publish** it. Unpublished messages do not appear.

## 3. Bootstrapping order

The package enforces this sequence inside `AdmobBootstrapper.start`:

1. `ConsentBridge.requestConsentInfoUpdate(debugSettings:)`
2. If a view controller is provided and a form is required,
   `ConsentBridge.presentRequiredFormIfNeeded(from:)`.
3. `MobileAdsBridge.updateRequestConfiguration(testDeviceIdentifiers:)`.
4. If `ConsentInformation.canRequestAds == true`, `MobileAds.shared.start`.
5. `isStarted = true`.

If the user later grants consent (e.g. via the privacy options form), call
`bootstrapper.reconcile()` to start the SDK.

You can call `bootstrapper.start()` from every scene’s `.task` modifier — it is
idempotent and concurrent calls await the same in-flight task.

## 4. Ad unit IDs

In production, prefer keeping IDs out of version control:

- Build-time injection via `xcconfig` or a generated Swift file.
- A `#if DEBUG` branch that points to `AdUnitIDMap.googleTest`.

Never commit production IDs to a public repository.

## 5. App Store Connect

- Privacy nutrition labels: mark *Identifiers (Device ID)* and *Usage Data*
  unless you can prove otherwise. Google publishes a reference matrix at
  https://developers.google.com/admob/ios/privacy/data-disclosure.
- Mark *Used for tracking* only if you call ATT and the user can grant tracking.

## 6. App Open ad guidance

`AdmobAppOpenCoordinator.handleScenePhaseChange` ignores the first
`.active` event so the ad does not appear after cold-start content is already
interactive. Background → active transitions trigger the show. During
onboarding, IAP flows, or login, set `coordinator.isSuppressed = true` and
restore it afterwards.

## 7. Rewarded interstitial intro screen

AdMob policy requires the host app to show an intro screen that explains the
reward and lets the user opt out before presenting a rewarded interstitial.
`AdmobRewardedInterstitialController` does not enforce this — your UI must.

## 8. Diagnostics

`AdmobEventSink.logging()` writes through `OSLog`. Replace it with a custom
sink to forward events into your analytics pipeline:

```swift
let sink = AdmobEventSink { event in
    Analytics.track("admob", payload: ["event": String(describing: event)])
}
let bootstrapper = AdmobBootstrapper(configuration: .development(), eventSink: sink)
```

Avoid logging raw ad unit IDs in production builds.
