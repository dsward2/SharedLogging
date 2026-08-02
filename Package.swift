// swift-tools-version: 5.9
import PackageDescription

// SharedLogging — a shared log store + viewer window for AntennaHead and
// ControlBooth. Writes a per-app plain-text log file into the App Group
// container both apps already declare (group.com.dsward.antennahead) and
// exposes a ready-made SwiftUI viewer so neither app duplicates the UI.
//
// Deliberately has no dependency on PipelineHelpers (or vice versa):
// PipelineHelpers' TaskItem/TaskPipelineManager forward subprocess stderr to
// the host app via plain closures, and the host app is the one that calls
// into LogStore — keeping PipelineHelpers decoupled from any specific
// logging type.
let package = Package(
    name: "SharedLogging",
    platforms: [
        // Matches PipelineHelpers/AirPlayReceiver's minimum (LogStore uses
        // @Observable).
        .macOS(.v14)
    ],
    products: [
        .library(name: "SharedLogging", targets: ["SharedLogging"])
    ],
    targets: [
        .target(name: "SharedLogging"),
        .testTarget(name: "SharedLoggingTests", dependencies: ["SharedLogging"])
    ]
)
