import Foundation

// MARK: - Runtime mode

public enum AdmobRuntimeMode: Sendable, Hashable {
    case disabled
    case test
    case production
}

// MARK: - Ad unit ID map

public struct AdUnitIDMap: Sendable, Hashable {
    public var banner: String?
    public var interstitial: String?
    public var rewarded: String?
    public var rewardedInterstitial: String?
    public var appOpen: String?
    public var native: String?

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
    /// Source: https://developers.google.com/admob/ios/test-ads
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

public struct AdmobConsentDebugSettings: Sendable, Hashable {
    public enum Geography: Int, Sendable {
        case disabled = 0
        case eea = 1
        case notEEA = 2
        case regulatedUSState = 3
        case other = 4
    }

    public let geography: Geography
    public let testDeviceIdentifiers: [String]

    public init(geography: Geography = .disabled, testDeviceIdentifiers: [String] = []) {
        self.geography = geography
        self.testDeviceIdentifiers = testDeviceIdentifiers
    }
}

// MARK: - Configuration

public struct AdmobConfiguration: Sendable {
    public var runtimeMode: AdmobRuntimeMode
    public var adUnits: AdUnitIDMap
    public var testDeviceIdentifiers: [String]
    public var consentDebugSettings: AdmobConsentDebugSettings?

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

    /// Development-mode preset that uses Google test ad unit IDs.
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

    /// Disabled preset that prevents any ad request work.
    public static let disabled = AdmobConfiguration(
        runtimeMode: .disabled,
        adUnits: AdUnitIDMap()
    )

    public var isAdRequestPermitted: Bool {
        runtimeMode != .disabled
    }
}
