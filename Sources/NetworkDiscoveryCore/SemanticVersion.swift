import Foundation

public struct SemanticVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let numericPart = normalized.split(separator: "-", maxSplits: 1).first ?? ""
        let components = numericPart.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

        var numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count, numbers.allSatisfy({ $0 >= 0 }) else {
            return nil
        }

        while numbers.count < 3 {
            numbers.append(0)
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
