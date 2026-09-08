// swift-tools-version: 6.3

import PackageDescription

let linuxCore: [Target] = [
    .systemLibrary(
        name: "CSQLite",
        pkgConfig: "sqlite3",
        providers: [.apt(["libsqlite3-dev"])]
    ),
    .target(name: "CoreDomain"),
    .target(name: "CoreTemporal", dependencies: ["CoreDomain"]),
    .target(name: "EnginePorts", dependencies: ["CoreDomain", "CoreTemporal"]),
    .target(name: "MetricCatalog", dependencies: ["CoreDomain"]),
    .target(name: "WireFormat", dependencies: ["CoreDomain", "CoreTemporal", "MetricCatalog"]),
    .target(name: "RequestTemplate"),
    .target(name: "CompanionWire", dependencies: ["CoreDomain", "WireFormat"]),
    .target(name: "Redaction", dependencies: ["CoreDomain"]),
    .target(
        name: "StorageSQLite",
        dependencies: ["EnginePorts", "CoreDomain", "CoreTemporal", "CSQLite", "RunJournal"],
        linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .target(name: "RunJournal", dependencies: ["EnginePorts", "CoreDomain", "Redaction", "WireFormat"]),
    .target(name: "CorrectnessEngine", dependencies: ["EnginePorts", "MetricCatalog", "CoreDomain", "CoreTemporal", "WireFormat", "FileWriteKit", "DestinationTrust", "Watchdog", "RunJournal"]),
    .target(name: "Watchdog", dependencies: ["EnginePorts", "CoreDomain", "CoreTemporal"]),
    .target(name: "DiagnosticBundle", dependencies: ["EnginePorts", "Redaction", "CoreDomain"]),
    .target(name: "FileWriteKit"),
    .target(name: "SinkLocalFile", dependencies: ["EnginePorts", "FileWriteKit", "CoreDomain", "WireFormat", "DestinationTrust"]),
    .target(name: "NetEgress", dependencies: ["WireFormat", "EnginePorts", "RunJournal"]),
    .target(name: "DestinationTrust", dependencies: ["EnginePorts", "NetEgress"]),
    .target(name: "SinkHTTP", dependencies: ["EnginePorts", "NetEgress", "WireFormat", "CoreDomain", "MetricCatalog", "RequestTemplate", "FileWriteKit", "DestinationTrust"]),
    .target(name: "SinkCompanion", dependencies: ["CompanionWire", "EnginePorts", "NetEgress", "WireFormat", "CoreDomain", "FileWriteKit", "DestinationTrust"]),
    .target(name: "CompanionReceive", dependencies: ["CompanionWire", "FileWriteKit", "NetEgress", "WireFormat"]),
    .target(name: "MQTTCodec"),
    .target(name: "SinkMQTT", dependencies: ["MQTTCodec", "EnginePorts", "NetEgress", "WireFormat", "CoreDomain"]),
    .target(
        name: "TestSupport",
        dependencies: [
            "CoreDomain",
            "CoreTemporal",
            "EnginePorts",
            "MetricCatalog",
            "WireFormat",
            "StorageSQLite",
            "RunJournal",
            "CorrectnessEngine",
            "Watchdog",
            "FileWriteKit",
            "SinkLocalFile",
            "NetEgress",
            "SinkHTTP",
            "RequestTemplate",
            "DestinationTrust",
            "MQTTCodec",
            "SinkMQTT",
            "CompanionWire",
            "SinkCompanion",
            "CompanionReceive",
        ]
    ),
    .executableTarget(
        name: "corpusgen",
        dependencies: ["CoreDomain", "MetricCatalog", "WireFormat"],
        path: "Tools/corpusgen"
    ),
    .executableTarget(
        name: "policycheck",
        dependencies: ["MetricCatalog", "WireFormat"],
        path: "Tools/policycheck"
    ),
    .executableTarget(name: "m0harness", path: "Tools/m0harness"),
    .executableTarget(
        name: "receiver",
        dependencies: ["WireFormat"],
        path: "Tools/receiver"
    ),
    .executableTarget(
        name: "wirefuzz",
        dependencies: ["CompanionWire", "MQTTCodec", "WireFormat"],
        path: "Tools/wirefuzz"
    ),
    .testTarget(
        name: "ExportCoreTests",
        dependencies: [
            "CoreDomain",
            "CoreTemporal",
            "EnginePorts",
            "MetricCatalog",
            "WireFormat",
            "StorageSQLite",
            "RunJournal",
            "DiagnosticBundle",
            "Redaction",
            "CorrectnessEngine",
            "Watchdog",
            "TestSupport",
            "FileWriteKit",
            "SinkLocalFile",
            "NetEgress",
            "SinkHTTP",
            "RequestTemplate",
            "DestinationTrust",
            "MQTTCodec",
            "SinkMQTT",
            "CompanionWire",
            "SinkCompanion",
            "CompanionReceive",
        ]
    ),
]

var targets = linuxCore

#if !os(Linux)
targets.append(contentsOf: [
    .target(
        name: "HealthKitSource",
        dependencies: ["EnginePorts", "CoreDomain", "CoreTemporal", "MetricCatalog", "RunJournal"],
        swiftSettings: [.define("OHE_HAS_HEALTHKIT")]
    ),
    .testTarget(
        name: "HealthKitSourceTests",
        dependencies: ["HealthKitSource", "EnginePorts", "CoreDomain", "CoreTemporal", "MetricCatalog"]
    ),
])
#endif

var products: [Product] = [
    .library(name: "ExportCore", targets: [
        "CoreDomain",
        "CoreTemporal",
        "EnginePorts",
        "MetricCatalog",
        "WireFormat",
        "RequestTemplate",
        "CompanionWire",
        "Redaction",
        "StorageSQLite",
        "RunJournal",
        "CorrectnessEngine",
        "Watchdog",
        "DiagnosticBundle",
        "FileWriteKit",
        "SinkLocalFile",
        "NetEgress",
        "DestinationTrust",
        "SinkHTTP",
        "SinkCompanion",
        "CompanionReceive",
    ]),
    .executable(name: "corpusgen", targets: ["corpusgen"]),
    .executable(name: "policycheck", targets: ["policycheck"]),
    .executable(name: "m0harness", targets: ["m0harness"]),
    .executable(name: "receiver", targets: ["receiver"]),
    .executable(name: "wirefuzz", targets: ["wirefuzz"]),
    .library(name: "SinkMQTT", targets: ["MQTTCodec", "SinkMQTT"]),
]

#if !os(Linux)
products.append(.library(name: "HealthKitSource", targets: ["HealthKitSource"]))
#endif

let package = Package(
    name: "open-health-exporter",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
