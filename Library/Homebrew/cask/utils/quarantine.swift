#!/usr/bin/swift

import Foundation

struct SwiftErr: TextOutputStream {
    public static var stream = SwiftErr()

    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}

// TODO: tell which arguments have to be provided
guard CommandLine.arguments.count >= 4 else {
    exit(2)
}

var dataLocationURL = URL(fileURLWithPath: CommandLine.arguments[1])

let quarantineProperties: [String: Any] = [
    kLSQuarantineAgentNameKey as String: "Homebrew Cask",
    kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload,
    kLSQuarantineDataURLKey as String: CommandLine.arguments[2],
    kLSQuarantineOriginURLKey as String: CommandLine.arguments[3]
]

// Check for if the data location URL is reachable
do {
    let isDataLocationURLReachable = try dataLocationURL.checkResourceIsReachable()
    guard isDataLocationURLReachable else {
        print("URL \(dataLocationURL.path) is not reachable. Not proceeding.", to: &SwiftErr.stream)
        exit(1)
    }
} catch {
    print(error.localizedDescription, to: &SwiftErr.stream)
    exit(1)
}

// Quarantine the file
do {
    var resourceValues = URLResourceValues()
    resourceValues.quarantineProperties = quarantineProperties
    try dataLocationURL.setResourceValues(resourceValues)
} catch {
    print(error.localizedDescription, to: &SwiftErr.stream)
    exit(1)
}
