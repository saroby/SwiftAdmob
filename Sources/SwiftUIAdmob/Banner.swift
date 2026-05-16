import SwiftUI
import UIKit
import GoogleMobileAds

// MARK: - Public events

public enum AdmobBannerEvent: Sendable {
    case loaded
    case failed(message: String)
    case impressed
    case clicked
}

// MARK: - Banner view

@MainActor
public struct AdmobBanner: View {
    private let explicitAdUnitID: String?
    private let onEvent: ((AdmobBannerEvent) -> Void)?

    @Environment(AdmobBootstrapper.self) private var bootstrapper
    @State private var measuredWidth: CGFloat = 0

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

    /// Adaptive banner height in points for a given container width.
    /// Returns `0` for non-positive widths.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return largeAnchoredAdaptiveBanner(width: width).size.height
    }
}

// MARK: - Modifier

public enum AdmobBannerPlacement: Sendable {
    case top
    case bottom
}

public extension View {
    /// Pin a SwiftUI-native AdMob banner to the leading edge of a screen.
    ///
    /// Uses ``View/safeAreaInset(edge:)`` so the banner does not overlap content
    /// and adapts to safe areas automatically.
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

@MainActor
public struct AdmobBannerModifier: ViewModifier {
    let placement: AdmobBannerPlacement
    let adUnitID: String?
    let onEvent: ((AdmobBannerEvent) -> Void)?

    public func body(content: Content) -> some View {
        content.safeAreaInset(edge: placement == .top ? .top : .bottom, spacing: 0) {
            AdmobBanner(adUnitID: adUnitID, onEvent: onEvent)
        }
    }
}

// MARK: - UIViewRepresentable host

@MainActor
struct BannerHost: UIViewRepresentable {
    let adUnitID: String?
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

        let nextSize = largeAnchoredAdaptiveBanner(width: width)
        let widthChanged = abs(context.coordinator.lastRequestedWidth - width) >= 1
        let unitChanged = uiView.adUnitID != adUnitID
        let needsReload = unitChanged || widthChanged

        guard needsReload else { return }

        uiView.adUnitID = adUnitID
        uiView.adSize = nextSize
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
