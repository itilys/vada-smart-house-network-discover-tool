import Foundation

public struct IPv4Network: Hashable, Codable, Sendable {
    public let original: String
    public let networkAddress: UInt32
    public let prefixLength: Int
    public let explicitHostRange: ClosedRange<UInt32>?

    public init(_ rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IPv4NetworkError.empty }

        original = trimmed

        if trimmed.hasSuffix(".*") {
            let prefix = String(trimmed.dropLast(2))
            let parts = prefix.split(separator: ".")
            guard parts.count == 3 else { throw IPv4NetworkError.invalidSegment(trimmed) }
            let base = try IPv4Address.parse("\(parts[0]).\(parts[1]).\(parts[2]).0")
            networkAddress = base
            prefixLength = 24
            explicitHostRange = (base + 1)...(base + 254)
            return
        }

        if let range = try IPv4Network.parseLastOctetRange(trimmed) {
            networkAddress = range.lowerBound
            prefixLength = 32
            explicitHostRange = range
            return
        }

        if trimmed.contains("/") {
            let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2,
                  let prefix = Int(components[1]),
                  (0...32).contains(prefix)
            else {
                throw IPv4NetworkError.invalidCIDR(trimmed)
            }

            let address = try IPv4Address.parse(String(components[0]))
            let mask = IPv4Network.mask(prefixLength: prefix)
            networkAddress = address & mask
            prefixLength = prefix
            explicitHostRange = nil
            return
        }

        let address = try IPv4Address.parse(trimmed)
        networkAddress = address
        prefixLength = 32
        explicitHostRange = address...address
    }

    public func hosts(maximumHosts: Int = 4096) throws -> [String] {
        let range: ClosedRange<UInt32>
        if let explicitHostRange {
            range = explicitHostRange
        } else {
            let hostBits = 32 - prefixLength
            let totalAddresses = hostBits == 32 ? UInt64(UInt32.max) + 1 : UInt64(1) << UInt64(hostBits)
            guard totalAddresses <= UInt64(maximumHosts + 2) else {
                throw IPv4NetworkError.tooManyHosts(Int(min(totalAddresses, UInt64(Int.max))))
            }

            let broadcast = networkAddress + UInt32(totalAddresses - 1)
            if prefixLength <= 30 {
                range = (networkAddress + 1)...(broadcast - 1)
            } else {
                range = networkAddress...broadcast
            }
        }

        let count = UInt64(range.upperBound) - UInt64(range.lowerBound) + 1
        guard count <= UInt64(maximumHosts) else {
            throw IPv4NetworkError.tooManyHosts(Int(min(count, UInt64(Int.max))))
        }

        return range.map { IPv4Address.string(from: $0) }
    }

    private static func parseLastOctetRange(_ value: String) throws -> ClosedRange<UInt32>? {
        let parts = value.split(separator: ".")
        guard parts.count == 4, parts[3].contains("-") else { return nil }

        let prefix = parts.prefix(3).joined(separator: ".")
        let bounds = parts[3].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let lower = Int(bounds[0]),
              let upper = Int(bounds[1]),
              (0...255).contains(lower),
              (0...255).contains(upper),
              lower <= upper
        else {
            throw IPv4NetworkError.invalidRange(value)
        }

        let lowerAddress = try IPv4Address.parse("\(prefix).\(lower)")
        let upperAddress = try IPv4Address.parse("\(prefix).\(upper)")
        return lowerAddress...upperAddress
    }

    private static func mask(prefixLength: Int) -> UInt32 {
        guard prefixLength > 0 else { return 0 }
        return UInt32.max << UInt32(32 - prefixLength)
    }
}

public enum IPv4Address {
    public static func parse(_ rawValue: String) throws -> UInt32 {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { throw IPv4NetworkError.invalidAddress(rawValue) }

        var address: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else {
                throw IPv4NetworkError.invalidAddress(rawValue)
            }
            address = (address << 8) | octet
        }
        return address
    }

    public static func string(from address: UInt32) -> String {
        [
            (address >> 24) & 0xff,
            (address >> 16) & 0xff,
            (address >> 8) & 0xff,
            address & 0xff
        ]
        .map(String.init)
        .joined(separator: ".")
    }

    public static func sortKey(for rawValue: String) -> UInt32 {
        (try? parse(rawValue)) ?? UInt32.max
    }
}

public enum IPv4NetworkError: LocalizedError, Equatable {
    case empty
    case invalidAddress(String)
    case invalidCIDR(String)
    case invalidSegment(String)
    case invalidRange(String)
    case tooManyHosts(Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Introduce un segmento de red."
        case .invalidAddress(let value):
            return "Dirección IPv4 no válida: \(value)."
        case .invalidCIDR(let value):
            return "CIDR no válido: \(value). Usa un formato como 192.168.1.0/24."
        case .invalidSegment(let value):
            return "Segmento no válido: \(value)."
        case .invalidRange(let value):
            return "Rango IPv4 no válido: \(value). Usa un formato como 192.168.1.1-254."
        case .tooManyHosts(let count):
            return "El segmento contiene \(count) direcciones. Reduce el rango o aumenta maximumHosts."
        }
    }
}
