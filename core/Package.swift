// swift-tools-version:5.9
// The app's non-UI code as a package, so its tests run on Linux in seconds (CI job `core`). The app target compiles
// the same file (ios/project.yml lists core/Sources/Playlist).
import PackageDescription

let package = Package(
    name: "Playlist",
    targets: [
        .target(name: "Playlist"),
        .testTarget(name: "PlaylistTests", dependencies: ["Playlist"]),
    ]
)
