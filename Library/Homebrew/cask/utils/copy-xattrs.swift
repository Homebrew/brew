#!/usr/bin/swift

import Foundation

struct SwiftErr: TextOutputStream {
    public static var stream = SwiftErr()

    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}

guard CommandLine.arguments.count >= 3 else {
    print("Usage: swift copy-xattrs.swift <source> <dest>")
    exit(2)
}

CommandLine.arguments[2].withCString { destinationPath in
    let destinationNamesLength = listxattr(destinationPath, nil, 0, 0)
    if destinationNamesLength == -1 {
        print("listxattr for destination failed: \(errno)", to: &SwiftErr.stream)
        exit(1)
    }
    let destinationNamesBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: destinationNamesLength)
    if listxattr(destinationPath, destinationNamesBuffer, destinationNamesLength, 0) != destinationNamesLength {
        print("Attributes changed during system call", to: &SwiftErr.stream)
        exit(1)
    }

    var destinationNamesIndex = 0
    while destinationNamesIndex < destinationNamesLength {
        let attribute = destinationNamesBuffer + destinationNamesIndex

        if removexattr(destinationPath, attribute, 0) != 0 {
            print("removexattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
            exit(1)
        }

        destinationNamesIndex += strlen(attribute) + 1
    }
    destinationNamesBuffer.deallocate()

    CommandLine.arguments[1].withCString { sourcePath in
        let sourceNamesLength = listxattr(sourcePath, nil, 0, 0)
        if sourceNamesLength == -1 {
            print("listxattr for source failed: \(errno)", to: &SwiftErr.stream)
            exit(1)
        }
        let sourceNamesBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: sourceNamesLength)
        if listxattr(sourcePath, sourceNamesBuffer, sourceNamesLength, 0) != sourceNamesLength {
            print("Attributes changed during system call", to: &SwiftErr.stream)
            exit(1)
        }

        var sourceNamesIndex = 0
        while sourceNamesIndex < sourceNamesLength {
            let attribute = sourceNamesBuffer + sourceNamesIndex

            let valueLength = getxattr(sourcePath, attribute, nil, 0, 0, 0)
            if valueLength == -1 {
                print("getxattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
                exit(1)
            }
            let valueBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: valueLength)
            if getxattr(sourcePath, attribute, valueBuffer, valueLength, 0, 0) != valueLength {
                print("Attributes changed during system call", to: &SwiftErr.stream)
                exit(1)
            }

            if setxattr(destinationPath, attribute, valueBuffer, valueLength, 0, 0) != 0 {
                print("setxattr for \(String(cString: attribute)) failed: \(errno)", to: &SwiftErr.stream)
                exit(1)
            }

            valueBuffer.deallocate()
            sourceNamesIndex += strlen(attribute) + 1
        }
        sourceNamesBuffer.deallocate()
    }
}
