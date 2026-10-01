// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iOSReleaseDoctor",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ios-release-doctor", targets: ["CLI"])],
    targets: [
        .target(name: "ReleaseDoctorCore"),
        .executableTarget(name: "CLI", dependencies: ["ReleaseDoctorCore"]),
        .testTarget(name: "ReleaseDoctorCoreTests", dependencies: ["ReleaseDoctorCore"],
                    resources: [.copy("Fixtures")])
    ]
)
