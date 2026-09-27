// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LearnChess",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LearnChess", targets: ["LearnChess"])],
    targets: [.executableTarget(name: "LearnChess")]
)
