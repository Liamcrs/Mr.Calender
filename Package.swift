// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MrCalenderCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "MrCalenderCore", targets: ["MrCalenderCore"])],
    targets: [
        .target(name: "MrCalenderCore"),
        .testTarget(name: "MrCalenderCoreTests", dependencies: ["MrCalenderCore"])
    ]
)
