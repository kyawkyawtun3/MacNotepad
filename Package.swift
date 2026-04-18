// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacNotepad",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacNotepad", targets: ["MacNotepad"])
    ],
    targets: [
        .executableTarget(
            name: "MacNotepad",
            path: "Sources/MacNotepad"
        )
    ]
)
