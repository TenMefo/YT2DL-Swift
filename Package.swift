// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "YT2DL", platforms: [.macOS(.v14)], products: [.executable(name: "YT2DL", targets: ["YT2DL"])], targets: [.executableTarget(name: "YT2DL"), .testTarget(name: "YT2DLTests", dependencies: ["YT2DL"])])
