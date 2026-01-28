#!/usr/bin/swift

import Foundation

let manager = FileManager.default

var success = true

// The command line arguments given but without the script's name
let CMDLineArgs = Array(CommandLine.arguments.dropFirst())

var trashed: [String] = []
var untrashable: [String] = []
for item in CMDLineArgs {
    do {
        let url = URL(fileURLWithPath: item)
        var trashedPath: NSURL!
        try manager.trashItem(at: url, resultingItemURL: &trashedPath)
        trashed.append((trashedPath as URL).path)
        success = true
    } catch {
        untrashable.append(item)
        success = false
    }
}

print(trashed.joined(separator: ":"))
print(untrashable.joined(separator: ":"), terminator: "")

guard success else {
    exit(1)
}
