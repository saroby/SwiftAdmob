import SwiftUI
import UIKit
import GoogleMobileAds

// MARK: - Public events

/// View-local banner lifecycle events delivered to the `onEvent` closure.
///
/// These mirror a subset of ``AdmobEvent`` shaped for the banner surface.
/// Use the bootstrapper-level event sink for cross-cutting analytics.
public enum AdmobBannerEvent: Sendable {
    /// A banner ad payload finished loading.
    case loaded
    /// The banner failed to load. `message` is the SDK's localized description.
    case failed(message: String)
    /// An impression was recorded for the displayed ad.
    case impressed
    /// The user tapped the banner.
    case clicked
}

// MARK: - Banner view

/// SwiftUI banner view that lays out using AdMob's standard 320x50 anchored banner.
///
/// Reads ``AdmobBootstrapper`` from the environment and gates ad requests on
/// ``AdmobBootstrapper/canRequestAds``. Width is observed via
/// `onGeometryChange`; the underlying banner reloads only when the resolved
/// width or ad unit ID changes.
///
/// - Important: Never hard-code a height for adaptive banners. Use
///   ``height(forWidth:)`` if you need the value outside this view.
/// - Note: When ``AdmobBootstrapper/canRequestAds`` flips to `false`
///   mid-session, the underlying banner is hidden until it flips back.
@MainActor
public struct AdmobBanner: View {
    private let explicitAdUnitID: String?
    private let onEvent: ((AdmobBannerEvent) -> Void)?

    @Environment(AdmobBootstrapper.self) private var bootstrapper
    @State private var measuredWidth: CGFloat = 0

    /// Create a banner view.
    /// - Parameters:
    ///   - adUnitID: Explicit ad unit ID. When `nil`, falls back to
    ///     ``AdUnitIDMap/banner`` from the environment bootstrapper.
    ///   - onEvent: Optional per-instance event callback.
    public init(
        adUnitID: String? = nil,
        onEvent: ((AdmobBannerEvent) -> Void)? = nil
    ) {
        self.explicitAdUnitID = adUnitID
        self.onEvent = onEvent
    }

    public var body: some View {
        let resolvedID = explicitAdUnitID ?? bootstrapper.configuration.adUnits.banner
        let height = AdmobBanner.height(forWidth: measuredWidth)

        BannerHost(
            adUnitID: resolvedID,
            adSize: AdSizeBanner,
            width: measuredWidth,
            isEnabled: bootstrapper.canRequestAds,
            eventSink: bootstrapper.eventSink,
            onEvent: onEvent
        )
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 1))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width.rounded()
        } action: { newValue in
            measuredWidth = newValue
        }
    }

    /// Compute the banner height in points for a given container width.
    ///
    /// Returns the standard 320x50 anchored banner height (50pt) for any
    /// positive width. Use this when laying out placeholders so the
    /// surrounding content doesn't shift when the banner loads.
    /// - Parameter width: Container width in points.
    /// - Returns: Banner height in points, or `0` for non-positive widths.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return AdSizeBanner.size.height
    }
}

// MARK: - Adaptive banner view

/// SwiftUI banner view that lays out using AdMob's
/// ``largeAnchoredAdaptiveBanner(width:)`` size.
///
/// Width is observed via `onGeometryChange` and the underlying banner
/// reloads only when the resolved width or ad unit ID changes. Height is
/// dynamic — between 50 and 150 points depending on the container width
/// and current interface orientation — so the surrounding layout must
/// tolerate variable banner height. Use ``height(forWidth:)`` to reserve
/// the exact height for a given width.
///
/// AdMob recommends an anchored adaptive size (this view) over the fixed
/// ``AdmobBanner`` (320x50) when the host can give the banner more
/// vertical room — taller anchored sizes typically fill higher-value
/// inventory. The trade-off is layout fragility: pinning this view to a
/// toolbar / floating button area can cause overlap. Prefer the
/// ``SwiftUICore/View/adAdaptiveBanner(_:adUnitID:onEvent:)`` modifier or
/// place this view inside a container whose layout already accounts for
/// a variable-height ad slot.
///
/// Reads ``AdmobBootstrapper`` from the environment and gates ad requests
/// on ``AdmobBootstrapper/canRequestAds``. When `canRequestAds` flips to
/// `false` mid-session, the underlying banner is hidden until it flips
/// back.
///
/// - Important: Never hard-code a height for adaptive banners. Use
///   ``height(forWidth:)`` if you need the value outside this view.
@MainActor
public struct AdmobAdaptiveBanner: View {
    private let explicitAdUnitID: String?
    private let onEvent: ((AdmobBannerEvent) -> Void)?

    @Environment(AdmobBootstrapper.self) private var bootstrapper
    @State private var measuredWidth: CGFloat = 0

    /// Create an anchored adaptive banner view.
    /// - Parameters:
    ///   - adUnitID: Explicit ad unit ID. When `nil`, falls back to
    ///     ``AdUnitIDMap/banner`` from the environment bootstrapper.
    ///   - onEvent: Optional per-instance event callback.
    public init(
        adUnitID: String? = nil,
        onEvent: ((AdmobBannerEvent) -> Void)? = nil
    ) {
        self.explicitAdUnitID = adUnitID
        self.onEvent = onEvent
    }

    public var body: some View {
        let resolvedID = explicitAdUnitID ?? bootstrapper.configuration.adUnits.banner
        let adSize = AdmobAdaptiveBanner.adSize(forWidth: measuredWidth)
        let height = adSize.size.height

        BannerHost(
            adUnitID: resolvedID,
            adSize: adSize,
            width: measuredWidth,
            isEnabled: bootstrapper.canRequestAds,
            eventSink: bootstrapper.eventSink,
            onEvent: onEvent
        )
        .frame(maxWidth: .infinity)
        .frame(height: max(height, 1))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width.rounded()
        } action: { newValue in
            measuredWidth = newValue
        }
    }

    /// Compute the anchored adaptive banner height in points for a given
    /// container width.
    ///
    /// Returns the SDK-resolved height (50–150pt range) for any positive
    /// width, or `0` for non-positive widths. Use this when laying out
    /// placeholders so the surrounding content doesn't shift when the
    /// banner loads.
    /// - Parameter width: Container width in points.
    /// - Returns: Banner height in points, or `0` for non-positive widths.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return adSize(forWidth: width).size.height
    }

    /// Resolve the AdMob ``AdSize`` used by ``AdmobAdaptiveBanner`` for a
    /// given container width. Returns ``AdSizeBanner`` (320x50) for
    /// non-positive widths so callers always get a valid request size.
    static func adSize(forWidth width: CGFloat) -> AdSize {
        guard width > 0 else { return AdSizeBanner }
        return largeAnchoredAdaptiveBanner(width: width)
    }
}

// MARK: - Vertical banner view

/// SwiftUI banner view that lays out using AdMob's fixed 120x600
/// ``AdSizeSkyscraper`` size.
///
/// AdMob does not ship a true "vertical adaptive" banner — `Skyscraper`
/// (120x600) is the canonical vertical fixed format still exposed by the
/// current Swift SDK (`AdSizeWideSkyscraper` / 160x600 was removed). Use
/// this for sidebar placements where a tall, narrow ad slot is desired.
/// The view reserves `120x600` regardless of container; the host layout
/// must be wide enough to fit 120pt without clipping.
///
/// Reads ``AdmobBootstrapper`` from the environment and gates ad requests on
/// ``AdmobBootstrapper/canRequestAds``. When `canRequestAds` flips to `false`
/// mid-session, the underlying banner is hidden until it flips back.
///
/// - Note: Falls back to ``AdUnitIDMap/banner`` when `adUnitID` is `nil`. For
///   production you should usually pass an explicit ad unit ID configured for
///   the 120x600 slot, since AdMob serves different inventory by size.
@MainActor
public struct AdmobVerticalBanner: View {
    private let explicitAdUnitID: String?
    private let onEvent: ((AdmobBannerEvent) -> Void)?

    @Environment(AdmobBootstrapper.self) private var bootstrapper

    /// Fixed ``AdSizeSkyscraper`` size (120x600) used by ``AdmobVerticalBanner``.
    public static let size: CGSize = AdSizeSkyscraper.size

    /// Create a vertical banner view.
    /// - Parameters:
    ///   - adUnitID: Explicit ad unit ID. When `nil`, falls back to
    ///     ``AdUnitIDMap/banner`` from the environment bootstrapper.
    ///   - onEvent: Optional per-instance event callback.
    public init(
        adUnitID: String? = nil,
        onEvent: ((AdmobBannerEvent) -> Void)? = nil
    ) {
        self.explicitAdUnitID = adUnitID
        self.onEvent = onEvent
    }

    public var body: some View {
        let resolvedID = explicitAdUnitID ?? bootstrapper.configuration.adUnits.banner
        let size = AdmobVerticalBanner.size

        BannerHost(
            adUnitID: resolvedID,
            adSize: AdSizeSkyscraper,
            width: size.width,
            isEnabled: bootstrapper.canRequestAds,
            eventSink: bootstrapper.eventSink,
            onEvent: onEvent
        )
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Modifier

/// Placement edge used by ``SwiftUICore/View/adBanner(_:adUnitID:onEvent:)``.
public enum AdmobBannerPlacement: Sendable {
    /// Pin the banner to the top safe-area edge.
    case top
    /// Pin the banner to the bottom safe-area edge.
    case bottom
}

public extension View {
    /// Pin a SwiftUI-native AdMob banner to a safe-area edge of this view.
    ///
    /// Uses `safeAreaInset(edge:spacing:)` so the banner does not overlap
    /// content. Width is driven by the container; height is the adaptive
    /// banner height. See ``AdmobBanner`` for the underlying behavior.
    ///
    /// - Parameters:
    ///   - placement: Which safe-area edge to pin to. Defaults to `.bottom`.
    ///   - adUnitID: Explicit ad unit ID. When `nil`, the environment
    ///     bootstrapper's banner ID is used.
    ///   - onEvent: Optional per-instance event callback.
    func adBanner(
        _ placement: AdmobBannerPlacement = .bottom,
        adUnitID: String? = nil,
        onEvent: ((AdmobBannerEvent) -> Void)? = nil
    ) -> some View {
        modifier(AdmobBannerModifier(
            placement: placement,
            adUnitID: adUnitID,
            onEvent: onEvent
        ))
    }
}

/// `ViewModifier` backing ``SwiftUICore/View/adBanner(_:adUnitID:onEvent:)``.
@MainActor
public struct AdmobBannerModifier: ViewModifier {
    /// Edge to pin the banner to.
    public let placement: AdmobBannerPlacement
    /// Optional explicit ad unit ID; falls back to environment when `nil`.
    public let adUnitID: String?
    /// Per-instance event callback.
    public let onEvent: ((AdmobBannerEvent) -> Void)?

    public func body(content: Content) -> some View {
        content.safeAreaInset(edge: placement == .top ? .top : .bottom, spacing: 0) {
            AdmobBanner(adUnitID: adUnitID, onEvent: onEvent)
        }
    }
}

public extension View {
    /// Pin a SwiftUI-native AdMob *anchored adaptive* banner to a
    /// safe-area edge of this view.
    ///
    /// Uses `safeAreaInset(edge:spacing:)` so the banner does not overlap
    /// content. Width is driven by the container; height is the anchored
    /// adaptive height (50–150pt) — see ``AdmobAdaptiveBanner`` for the
    /// underlying behavior. Prefer this modifier over ``adBanner(_:adUnitID:onEvent:)``
    /// when the layout can absorb taller inventory.
    ///
    /// - Parameters:
    ///   - placement: Which safe-area edge to pin to. Defaults to `.bottom`.
    ///   - adUnitID: Explicit ad unit ID. When `nil`, the environment
    ///     bootstrapper's banner ID is used.
    ///   - onEvent: Optional per-instance event callback.
    func adAdaptiveBanner(
        _ placement: AdmobBannerPlacement = .bottom,
        adUnitID: String? = nil,
        onEvent: ((AdmobBannerEvent) -> Void)? = nil
    ) -> some View {
        modifier(AdmobAdaptiveBannerModifier(
            placement: placement,
            adUnitID: adUnitID,
            onEvent: onEvent
        ))
    }
}

/// `ViewModifier` backing ``SwiftUICore/View/adAdaptiveBanner(_:adUnitID:onEvent:)``.
@MainActor
public struct AdmobAdaptiveBannerModifier: ViewModifier {
    /// Edge to pin the banner to.
    public let placement: AdmobBannerPlacement
    /// Optional explicit ad unit ID; falls back to environment when `nil`.
    public let adUnitID: String?
    /// Per-instance event callback.
    public let onEvent: ((AdmobBannerEvent) -> Void)?

    public func body(content: Content) -> some View {
        content.safeAreaInset(edge: placement == .top ? .top : .bottom, spacing: 0) {
            AdmobAdaptiveBanner(adUnitID: adUnitID, onEvent: onEvent)
        }
    }
}

// MARK: - UIViewRepresentable host

@MainActor
struct BannerHost: UIViewRepresentable {
    let adUnitID: String?
    /// Ad size to request. ``AdmobBanner`` passes ``AdSizeBanner`` (320x50);
    /// ``AdmobVerticalBanner`` passes ``AdSizeSkyscraper`` (120x600).
    let adSize: AdSize
    let width: CGFloat
    let isEnabled: Bool
    let eventSink: AdmobEventSink
    let onEvent: ((AdmobBannerEvent) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(eventSink: eventSink, onEvent: onEvent)
    }

    func makeUIView(context: Context) -> BannerView {
        let view = BannerView()
        view.delegate = context.coordinator
        view.rootViewController = RootViewControllerLocator.find()
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // Always refresh the coordinator's captures so SwiftUI parents that pass
        // a new closure (or new eventSink) on each render get fresh callbacks.
        // Must happen BEFORE any early return so disabled state still propagates.
        context.coordinator.eventSink = eventSink
        context.coordinator.onEvent = onEvent

        // Hide the existing ad surface when the host disables ad requests
        // (e.g. consent revoked mid-session). Future re-enable will unhide.
        uiView.isHidden = !isEnabled

        guard isEnabled,
              width > 1,
              let adUnitID,
              !adUnitID.isEmpty
        else {
            return
        }

        if uiView.rootViewController == nil {
            uiView.rootViewController = RootViewControllerLocator.find()
        }

        let widthChanged = abs(context.coordinator.lastRequestedWidth - width) >= 1
        let unitChanged = uiView.adUnitID != adUnitID
        let sizeChanged = !adSizesEqual(uiView.adSize, adSize)
        let needsReload = unitChanged || widthChanged || sizeChanged

        guard needsReload else { return }

        uiView.adUnitID = adUnitID
        uiView.adSize = adSize
        context.coordinator.lastRequestedWidth = width

        eventSink.send(.adLoadStarted(.banner))
        uiView.load(Request())
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        var lastRequestedWidth: CGFloat = 0
        var eventSink: AdmobEventSink
        var onEvent: ((AdmobBannerEvent) -> Void)?

        init(eventSink: AdmobEventSink, onEvent: ((AdmobBannerEvent) -> Void)?) {
            self.eventSink = eventSink
            self.onEvent = onEvent
        }

        nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventSink.send(.adLoadSucceeded(.banner))
                self.onEvent?(.loaded)
            }
        }

        nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventSink.send(.adLoadFailed(.banner, message: message))
                self.onEvent?(.failed(message: message))
            }
        }

        nonisolated func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventSink.send(.adImpressed(.banner))
                self.onEvent?(.impressed)
            }
        }

        nonisolated func bannerViewDidRecordClick(_ bannerView: BannerView) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.eventSink.send(.adClicked(.banner))
                self.onEvent?(.clicked)
            }
        }
    }
}

/// Compare two ``AdSize`` values by their resolved ``CGSize``.
///
/// `AdSize` does not conform to `Equatable`; comparing the underlying
/// `size` keeps the reload-decision logic in
/// ``BannerHost/updateUIView(_:context:)`` correct when callers swap between
/// e.g. ``AdSizeBanner`` and ``AdSizeSkyscraper``.
private func adSizesEqual(_ lhs: AdSize, _ rhs: AdSize) -> Bool {
    lhs.size == rhs.size
}
