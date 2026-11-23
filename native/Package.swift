// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Minesweeper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Minesweeper", targets: ["Minesweeper"])],
    targets: [.executableTarget(name: "Minesweeper", path: "Sources")]
)
