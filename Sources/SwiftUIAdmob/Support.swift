import Foundation
import OSLog
import UIKit

// MARK: - Ad Format

public enum AdmobAdFormat: String, Sendable, Hashable, CaseIterable {
    case banner
    case interstitial
    case rewarded
    case rewardedInterstitial
    case appOpen
    case native
}

// MARK: - Errors

public enum AdmobError: Error, Sendable, Equatable {
    case missingHostConfiguration(String)
    case sdkNotStarted
    case consentNotResolved
    case missingAdUnitID(AdmobAdFormat)
    case loadFailed(format: AdmobAdFormat, message: String)
    case presentationUnavailable(reason: String)
    case adExpired(format: AdmobAdFormat)
    case duplicateRequest(format: AdmobAdFormat)
    case disabledByConfiguration
}

extension AdmobError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingHostConfiguration(let detail):
            return "Missing host app configuration: \(detail)"
        case .sdkNotStarted:
            return "Google Mobile Ads SDK has not been started."
        case .consentNotResolved:
            return "User consent has not been resolved. Ads cannot be requested."
        case .missingAdUnitID(let format):
            return "Missing ad unit ID for format \(format.rawValue)."
        case .loadFailed(let format, let message):
            return "Failed to load \(format.rawValue) ad: \(message)"
        case .presentationUnavailable(let reason):
            return "Ad presentation unavailable: \(reason)"
        case .adExpired(let format):
            return "\(format.rawValue) ad expired before presentation."
        case .duplicateRequest(let format):
            return "A \(format.rawValue) ad request is already in flight."
        case .disabledByConfiguration:
            return "Ads are disabled by configuration."
        }
    }

    /// Actionable next step for each failure mode. Surfaced through
    /// `LocalizedError.recoverySuggestion` so AI coding agents and human
    /// developers see a concrete fix in logs and error dialogs.
    public var recoverySuggestion: String? {
        switch self {
        case .missingHostConfiguration:
            return "Add GADApplicationIdentifier and SKAdNetworkItems to your app's Info.plist. See docs/HOST_APP_SETUP.md for the full checklist."
        case .sdkNotStarted:
            return "Call `await bootstrapper.start()` from your root scene's `.task` modifier before requesting ads. AdmobBootstrapper.start is idempotent."
        case .consentNotResolved:
            return "Run `await bootstrapper.start()` to gather UMP consent, then inspect `bootstrapper.canRequestAds` before loading. Use `bootstrapper.reconcile()` after the user grants consent via the privacy options form."
        case .missingAdUnitID(let format):
            return "Set `adUnits.\(format.rawValue)` on AdmobConfiguration, or pass `adUnitID:` explicitly to the controller. Use `AdUnitIDMap.googleTest` for local development."
        case .loadFailed:
            return "Retry `load()` after a short delay. Verify network connectivity and that the ad unit ID exists in the AdMob console for this app bundle ID."
        case .presentationUnavailable:
            return "Verify the controller is loaded (isReady == true), no other `present()` is in flight, and a presenting UIViewController is available. Full-screen ads are one-shot — `load()` again before the next `present()`."
        case .adExpired(let format):
            return "Discard the cached ad and call `load()` again. \(format.rawValue) ads expire — app-open ads must be discarded after 4 hours (AdmobAppOpenCoordinator.expiration)."
        case .duplicateRequest:
            return "Another `present()` call is awaiting dismissal. Await its completion before invoking `present()` again — controllers serialize one presentation at a time."
        case .disabledByConfiguration:
            return "Use `AdmobConfiguration.development()` for test ads, or build a `.production` configuration with real ad unit IDs. `.disabled` blocks all ad requests intentionally."
        }
    }

    /// Short failure category, suitable for analytics tagging. Stable across
    /// release versions even if `errorDescription` wording is tuned.
    public var failureReason: String? {
        switch self {
        case .missingHostConfiguration: return "missing_host_configuration"
        case .sdkNotStarted: return "sdk_not_started"
        case .consentNotResolved: return "consent_not_resolved"
        case .missingAdUnitID: return "missing_ad_unit_id"
        case .loadFailed: return "load_failed"
        case .presentationUnavailable: return "presentation_unavailable"
        case .adExpired: return "ad_expired"
        case .duplicateRequest: return "duplicate_request"
        case .disabledByConfiguration: return "disabled_by_configuration"
        }
    }
}

// MARK: - Events

public enum AdmobEvent: Sendable, Equatable {
    case sdkStarted
    case consentUpdated(canRequestAds: Bool, privacyOptionsRequired: Bool)
    case adLoadStarted(AdmobAdFormat)
    case adLoadSucceeded(AdmobAdFormat)
    case adLoadFailed(AdmobAdFormat, message: String)
    case adPresented(AdmobAdFormat)
    case adDismissed(AdmobAdFormat)
    case adImpressed(AdmobAdFormat)
    case adClicked(AdmobAdFormat)
    case rewardEarned(amount: Double, type: String)
    case diagnosticWarning(String)
}

public struct AdmobEventSink: Sendable {
    public typealias Handler = @Sendable (AdmobEvent) -> Void

    public let send: Handler

    public init(handler: @escaping Handler) {
        self.send = handler
    }

    public static let none = AdmobEventSink { _ in }

    public static func logging(label: String = "SwiftUIAdmob") -> AdmobEventSink {
        let logger = AdmobLogger(label: label)
        return AdmobEventSink { event in
            logger.log(event: event)
        }
    }
}

// MARK: - Logger

public struct AdmobLogger: Sendable {
    private let logger: Logger

    public init(label: String = "SwiftUIAdmob") {
        self.logger = Logger(subsystem: "io.swiftuiadmob", category: label)
    }

    public func log(event: AdmobEvent) {
        switch event {
        case .sdkStarted:
            logger.info("[Admob] SDK started")
        case .consentUpdated(let canRequestAds, let privacyOptionsRequired):
            logger.info("[Admob] consent updated. canRequestAds=\(canRequestAds, privacy: .public) privacyOptionsRequired=\(privacyOptionsRequired, privacy: .public)")
        case .adLoadStarted(let format):
            logger.debug("[Admob] load started: \(format.rawValue, privacy: .public)")
        case .adLoadSucceeded(let format):
            logger.info("[Admob] load succeeded: \(format.rawValue, privacy: .public)")
        case .adLoadFailed(let format, let message):
            logger.error("[Admob] load failed: \(format.rawValue, privacy: .public) — \(message, privacy: .public)")
        case .adPresented(let format):
            logger.info("[Admob] presented: \(format.rawValue, privacy: .public)")
        case .adDismissed(let format):
            logger.info("[Admob] dismissed: \(format.rawValue, privacy: .public)")
        case .adImpressed(let format):
            logger.debug("[Admob] impressed: \(format.rawValue, privacy: .public)")
        case .adClicked(let format):
            logger.debug("[Admob] clicked: \(format.rawValue, privacy: .public)")
        case .rewardEarned(let amount, let type):
            logger.info("[Admob] reward earned: \(amount, privacy: .public) \(type, privacy: .public)")
        case .diagnosticWarning(let message):
            logger.warning("[Admob] \(message, privacy: .public)")
        }
    }
}

// MARK: - Root view controller locator

@MainActor
public enum RootViewControllerLocator {
    /// Returns the top-most view controller of the currently active foreground scene.
    /// Falls back to the first available window scene if no foreground scene is active.
    public static func find() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene = activeScene else { return nil }
        let keyWindow = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        guard let root = keyWindow?.rootViewController else { return nil }

        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
