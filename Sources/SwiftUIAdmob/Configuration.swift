import Foundation

// MARK: - Runtime mode

/// Runtime gate that controls whether the package performs any ad work.
///
/// Use ``test`` during development with Google's test ad unit IDs, ``production``
/// for shipping builds with real ad unit IDs, and ``disabled`` to block all ad
/// requests regardless of consent or SDK state.
public enum AdmobRuntimeMode: Sendable, Hashable {
    /// All ad work is blocked. `AdmobBootstrapper.start()` short-circuits.
    case disabled
    /// Development mode — typically paired with ``AdUnitIDMap/googleTest``.
    case test
    /// Production mode. Real ad unit IDs are expected.
    case production
}

// MARK: - Ad unit ID map

/// Typed lookup of AdMob ad unit IDs keyed by ad format.
///
/// Each property is optional so apps can ship only the formats they use.
/// Resolve an ID at runtime via ``adUnitID(for:)``.
public struct AdUnitIDMap: Sendable, Hashable {
    /// Banner ad unit ID, used by ``AdmobBanner``.
    public var banner: String?
    /// Interstitial ad unit ID, used by ``AdmobInterstitialController``.
    public var interstitial: String?
    /// Rewarded ad unit ID, used by ``AdmobRewardedController``.
    public var rewarded: String?
    /// Rewarded-interstitial ad unit ID, used by ``AdmobRewardedInterstitialController``.
    public var rewardedInterstitial: String?
    /// App-open ad unit ID, used by ``AdmobAppOpenCoordinator``.
    public var appOpen: String?
    /// Native ad unit ID. Reserved for a future native ad surface.
    public var native: String?

    /// Create a map. Every parameter is optional so apps wire only the formats they ship.
    public init(
        banner: String? = nil,
        interstitial: String? = nil,
        rewarded: String? = nil,
        rewardedInterstitial: String? = nil,
        appOpen: String? = nil,
        native: String? = nil
    ) {
        self.banner = banner
        self.interstitial = interstitial
        self.rewarded = rewarded
        self.rewardedInterstitial = rewardedInterstitial
        self.appOpen = appOpen
        self.native = native
    }

    /// Resolve the ad unit ID for a given format.
    /// - Parameter format: The ad format to look up.
    /// - Returns: The configured ad unit ID, or `nil` if unset for this format.
    public func adUnitID(for format: AdmobAdFormat) -> String? {
        switch format {
        case .banner: return banner
        case .interstitial: return interstitial
        case .rewarded: return rewarded
        case .rewardedInterstitial: return rewardedInterstitial
        case .appOpen: return appOpen
        case .native: return native
        }
    }

    /// Google-published test ad unit IDs for iOS.
    ///
    /// Use these during development to avoid policy violations from clicking
    /// live ads. Source: https://developers.google.com/admob/ios/test-ads
    public static let googleTest = AdUnitIDMap(
        banner: "ca-app-pub-3940256099942544/2934735716",
        interstitial: "ca-app-pub-3940256099942544/4411468910",
        rewarded: "ca-app-pub-3940256099942544/1712485313",
        rewardedInterstitial: "ca-app-pub-3940256099942544/6978759866",
        appOpen: "ca-app-pub-3940256099942544/5575463023",
        native: "ca-app-pub-3940256099942544/3986624511"
    )
}

// MARK: - Consent debug settings

/// UMP debug settings forwarded to the consent bridge.
///
/// Only meaningful when paired with a device whose identifier is listed in
/// ``testDeviceIdentifiers`` — UMP ignores debug geography on real users.
public struct AdmobConsentDebugSettings: Sendable, Hashable {
    /// Forced geography used while debugging the consent flow on test devices.
    public enum Geography: Int, Sendable {
        /// Use the device's real geography.
        case disabled = 0
        /// Force European Economic Area behavior.
        case eea = 1
        /// Force non-EEA behavior.
        case notEEA = 2
        /// Force a US state with privacy regulations (e.g. California).
        case regulatedUSState = 3
        /// Force "other" / unregulated region behavior.
        case other = 4
    }

    /// Forced geography for the consent simulation.
    public let geography: Geography
    /// Device IDs allowed to receive the forced debug geography.
    public let testDeviceIdentifiers: [String]

    /// Create a debug settings bundle.
    /// - Parameters:
    ///   - geography: Forced geography for matching test devices.
    ///   - testDeviceIdentifiers: Device IDs that should see the forced geography.
    public init(geography: Geography = .disabled, testDeviceIdentifiers: [String] = []) {
        self.geography = geography
        self.testDeviceIdentifiers = testDeviceIdentifiers
    }
}

// MARK: - Configuration

/// Top-level runtime configuration consumed by ``AdmobBootstrapper``.
///
/// Build one configuration at app launch and inject it into the bootstrapper.
/// For local development, prefer the ``development(testDeviceIdentifiers:consentDebugSettings:)``
/// preset; for shipping builds, populate ``adUnits`` with real ad unit IDs and
/// set ``runtimeMode`` to ``AdmobRuntimeMode/production``.
///
/// - Important: The AdMob *app* ID lives in the host app's `Info.plist`
///   (`GADApplicationIdentifier`); it is intentionally not duplicated here.
public struct AdmobConfiguration: Sendable {
    /// Runtime gate. `.disabled` short-circuits every ad call site.
    public var runtimeMode: AdmobRuntimeMode
    /// Resolved ad unit IDs keyed by format.
    public var adUnits: AdUnitIDMap
    /// Device identifiers tagged as test devices by the Google Mobile Ads SDK.
    public var testDeviceIdentifiers: [String]
    /// Optional UMP debug settings for simulating geography on test devices.
    public var consentDebugSettings: AdmobConsentDebugSettings?

    /// Build a configuration explicitly.
    /// - Parameters:
    ///   - runtimeMode: Master gate for ad work.
    ///   - adUnits: Ad unit ID lookup.
    ///   - testDeviceIdentifiers: Test device IDs forwarded to `MobileAds`.
    ///   - consentDebugSettings: Optional UMP debug overrides.
    public init(
        runtimeMode: AdmobRuntimeMode,
        adUnits: AdUnitIDMap,
        testDeviceIdentifiers: [String] = [],
        consentDebugSettings: AdmobConsentDebugSettings? = nil
    ) {
        self.runtimeMode = runtimeMode
        self.adUnits = adUnits
        self.testDeviceIdentifiers = testDeviceIdentifiers
        self.consentDebugSettings = consentDebugSettings
    }

    /// Development preset that uses Google's published test ad unit IDs.
    ///
    /// Safe to use in DEBUG builds and on simulators without risking live ad
    /// policy violations.
    /// - Parameters:
    ///   - testDeviceIdentifiers: Test device IDs to forward to the SDK.
    ///   - consentDebugSettings: Optional UMP geography overrides for testing.
    /// - Returns: A configuration in ``AdmobRuntimeMode/test`` mode.
    public static func development(
        testDeviceIdentifiers: [String] = [],
        consentDebugSettings: AdmobConsentDebugSettings? = nil
    ) -> AdmobConfiguration {
        AdmobConfiguration(
            runtimeMode: .test,
            adUnits: .googleTest,
            testDeviceIdentifiers: testDeviceIdentifiers,
            consentDebugSettings: consentDebugSettings
        )
    }

    /// Disabled preset. Blocks every ad request and the SDK start call.
    public static let disabled = AdmobConfiguration(
        runtimeMode: .disabled,
        adUnits: AdUnitIDMap()
    )

    /// `true` when ``runtimeMode`` permits ad work.
    ///
    /// Consent and SDK-start state are checked separately by ``AdmobBootstrapper/canRequestAds``.
    public var isAdRequestPermitted: Bool {
        runtimeMode != .disabled
    }
}
