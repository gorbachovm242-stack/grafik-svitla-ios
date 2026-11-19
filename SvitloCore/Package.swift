// swift-tools-version:5.10
// Ядро «Графіка світла» для iPhone: уся логіка без UIKit/SwiftUI/WidgetKit, тож її можна перевіряти
// тестами будь-де, де є Swift (macOS на GitHub Actions, Windows чи Linux).
import PackageDescription

let package = Package(
    name: "SvitloCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SvitloCore", targets: ["SvitloCore"]),
    ],
    targets: [
        .target(name: "SvitloCore"),
        .testTarget(name: "SvitloCoreTests", dependencies: ["SvitloCore"]),
    ]
)
