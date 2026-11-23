import Foundation

struct ReleaseTag: Decodable {
    let tag: String

    struct Version: Comparable {
        let major: UInt64
        let minor: UInt64
        let patch: UInt64

        init?(_ version: String) {
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  parts.allSatisfy({ !$0.isEmpty && ($0.count == 1 || $0.first != "0")
                      && $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  let major = UInt64(parts[0]), let minor = UInt64(parts[1]), let patch = UInt64(parts[2])
            else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        static func < (left: Self, right: Self) -> Bool {
            (left.major, left.minor, left.patch) < (right.major, right.minor, right.patch)
        }
    }

    var version: String? {
        let prefix = "minesweeper-v"
        guard tag.hasPrefix(prefix) else { return nil }
        let value = String(tag.dropFirst(prefix.count))
        return Version(value) == nil ? nil : value
    }
}
