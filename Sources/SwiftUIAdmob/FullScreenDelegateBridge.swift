import Foundation
import GoogleMobileAds

/// Internal NSObject bridge that adapts ``FullScreenContentDelegate`` callbacks
/// into Sendable closures. Each controller hops the closure body onto its own
/// `@MainActor`-isolated handler.
final class FullScreenDelegateBridge: NSObject, FullScreenContentDelegate {
    typealias VoidHandler = @Sendable () -> Void
    typealias FailureHandler = @Sendable (String) -> Void

    private let onPresent: VoidHandler
    private let onImpression: VoidHandler
    private let onClick: VoidHandler
    private let onDismiss: VoidHandler
    private let onFailure: FailureHandler

    init(
        onPresent: @escaping VoidHandler,
        onImpression: @escaping VoidHandler,
        onClick: @escaping VoidHandler,
        onDismiss: @escaping VoidHandler,
        onFailure: @escaping FailureHandler
    ) {
        self.onPresent = onPresent
        self.onImpression = onImpression
        self.onClick = onClick
        self.onDismiss = onDismiss
        self.onFailure = onFailure
    }

    func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        onPresent()
    }

    func adDidRecordImpression(_ ad: any FullScreenPresentingAd) {
        onImpression()
    }

    func adDidRecordClick(_ ad: any FullScreenPresentingAd) {
        onClick()
    }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        onFailure(error.localizedDescription)
    }
}
