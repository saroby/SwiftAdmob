import Foundation

/// Namespace marker that exposes the package version string.
///
/// Useful for diagnostic logs and bug reports so the active package version
/// is unambiguous at runtime.
///
/// ## External references
///
/// - Google AdMob iOS quick-start (host-app setup, Info.plist, SKAdNetworkItems):
///   <https://developers.google.com/admob/ios/quick-start>
/// - Host responsibilities this package does **not** absorb: see
///   ``docs/HOST_APP_SETUP.md`` in the repository.
public enum SwiftUIAdmob {
    /// Semantic version string of the currently linked `SwiftUIAdmob` package.
    public static let packageVersion = "1.0.1"
}
