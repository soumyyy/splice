// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "SpliceCore",
  platforms: [.iOS(.v26), .macOS(.v15)],
  products: [.library(name: "SpliceCore", targets: ["SpliceCore"])],
  targets: [
    .target(name: "SpliceCore"),
    .testTarget(name: "SpliceCoreTests", dependencies: ["SpliceCore"]),
  ]
)
