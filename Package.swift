// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftUIAdmob",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "SwiftUIAdmob",
            targets: ["SwiftUIAdmob"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            from: "13.3.0"
        )
    ],
    targets: [
        .target(
            name: "SwiftUIAdmob",
            dependencies: [
                .product(
                    name: "GoogleMobileAds",
                    package: "swift-package-manager-google-mobile-ads"
                )
            ],
            path: "Sources/SwiftUIAdmob"
        ),
        .testTarget(
            name: "SwiftUIAdmobTests",
            dependencies: ["SwiftUIAdmob"],
            path: "Tests/SwiftUIAdmobTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
