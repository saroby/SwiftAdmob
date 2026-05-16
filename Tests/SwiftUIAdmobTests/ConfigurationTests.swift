import Testing
@testable import SwiftUIAdmob

@Suite("AdmobConfiguration")
struct ConfigurationTests {
    @Test("Disabled preset rejects ad requests")
    func disabledPreset() {
        let config = AdmobConfiguration.disabled
        #expect(config.runtimeMode == .disabled)
        #expect(config.isAdRequestPermitted == false)
        #expect(config.adUnits.banner == nil)
    }

    @Test("Development preset uses Google test IDs and permits requests")
    func developmentPreset() {
        let config = AdmobConfiguration.development()
        #expect(config.runtimeMode == .test)
        #expect(config.isAdRequestPermitted)
        #expect(config.adUnits.banner == "ca-app-pub-3940256099942544/2934735716")
        #expect(config.adUnits.interstitial == "ca-app-pub-3940256099942544/4411468910")
        #expect(config.adUnits.rewarded == "ca-app-pub-3940256099942544/1712485313")
        #expect(config.adUnits.rewardedInterstitial == "ca-app-pub-3940256099942544/6978759866")
        #expect(config.adUnits.appOpen == "ca-app-pub-3940256099942544/5575463023")
        #expect(config.adUnits.native == "ca-app-pub-3940256099942544/3986624511")
    }

    @Test("adUnitID(for:) resolves every format")
    func adUnitLookup() {
        let map = AdUnitIDMap.googleTest
        for format in AdmobAdFormat.allCases {
            #expect(map.adUnitID(for: format) != nil, "missing ID for \(format.rawValue)")
        }
    }

    @Test("Production preset can be built without test IDs")
    func productionPreset() {
        let map = AdUnitIDMap(banner: "ca-app-pub-1/2", interstitial: "ca-app-pub-1/3")
        let config = AdmobConfiguration(runtimeMode: .production, adUnits: map)
        #expect(config.runtimeMode == .production)
        #expect(config.isAdRequestPermitted)
        #expect(config.adUnits.banner == "ca-app-pub-1/2")
        #expect(config.adUnits.rewarded == nil)
    }
}
