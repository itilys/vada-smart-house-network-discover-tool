import Foundation

public struct DHCPRange: Identifiable, Hashable, Codable, Sendable {
    public let startAddress: String
    public let endAddress: String

    public var id: String { "\(startAddress)-\(endAddress)" }

    public var addressLabel: String {
        startAddress == endAddress ? startAddress : "\(startAddress) - \(endAddress)"
    }

    public var subnetLabel: String {
        (try? IPv4Address.parse(startAddress)).map(Self.subnetLabel(for:)) ?? "Otra subred"
    }

    public init(startAddress: String, endAddress: String) {
        self.startAddress = startAddress
        self.endAddress = endAddress
    }

    public func parsedRange() throws -> ClosedRange<UInt32> {
        let start = try IPv4Address.parse(startAddress)
        let end = try IPv4Address.parse(endAddress)
        guard start <= end else {
            throw IPv4NetworkError.invalidRange(addressLabel)
        }
        return start...end
    }

    private static func subnetLabel(for address: UInt32) -> String {
        let first = (address >> 24) & 0xff
        let second = (address >> 16) & 0xff
        let third = (address >> 8) & 0xff
        return "\(first).\(second).\(third).0/24"
    }
}

public enum FreeAddressRangeKind: String, Hashable, Codable, Sendable {
    case staticCandidate
    case dhcpPool

    public var label: String {
        switch self {
        case .staticCandidate: return "Libre estática"
        case .dhcpPool: return "DHCP"
        }
    }
}

public struct FreeAddressRange: Identifiable, Hashable, Codable, Sendable {
    public let startAddress: String
    public let endAddress: String
    public let count: Int
    public let subnetLabel: String
    public let kind: FreeAddressRangeKind

    public var id: String { "\(startAddress)-\(endAddress)-\(kind.rawValue)" }

    public var addressLabel: String {
        startAddress == endAddress ? startAddress : "\(startAddress) - \(endAddress)"
    }

    public init(
        startAddress: String,
        endAddress: String,
        count: Int,
        subnetLabel: String,
        kind: FreeAddressRangeKind = .staticCandidate
    ) {
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.count = count
        self.subnetLabel = subnetLabel
        self.kind = kind
    }
}

public struct IPAvailabilityReport: Identifiable, Hashable, Codable, Sendable {
    public let segment: String
    public let usableAddressCount: Int
    public let occupiedAddressCount: Int
    public let freeAddressCount: Int
    public let staticFreeAddressCount: Int
    public let dhcpFreeAddressCount: Int
    public let dhcpRanges: [DHCPRange]
    public let ranges: [FreeAddressRange]

    public var id: String {
        "\(segment)-\(usableAddressCount)-\(occupiedAddressCount)-\(freeAddressCount)-\(dhcpRanges.map(\.id).joined(separator: "|"))"
    }

    public init(
        segment: String,
        usableAddressCount: Int,
        occupiedAddressCount: Int,
        freeAddressCount: Int,
        staticFreeAddressCount: Int,
        dhcpFreeAddressCount: Int,
        dhcpRanges: [DHCPRange],
        ranges: [FreeAddressRange]
    ) {
        self.segment = segment
        self.usableAddressCount = usableAddressCount
        self.occupiedAddressCount = occupiedAddressCount
        self.freeAddressCount = freeAddressCount
        self.staticFreeAddressCount = staticFreeAddressCount
        self.dhcpFreeAddressCount = dhcpFreeAddressCount
        self.dhcpRanges = dhcpRanges
        self.ranges = ranges
    }

    public static func build(
        segment: String,
        occupiedIPAddresses: [String],
        dhcpRanges: [DHCPRange] = [],
        maximumHosts: Int = 4096
    ) throws -> IPAvailabilityReport {
        let network = try IPv4Network(segment)
        let allUsableAddresses = try network.hosts(maximumHosts: maximumHosts).compactMap { try? IPv4Address.parse($0) }
        let usableAddresses = allUsableAddresses.filter { address in
            guard network.prefixLength < 24, network.explicitHostRange == nil else {
                return true
            }
            return !isConservativeSubnetBoundary(address)
        }
        let usableAddressSet = Set(usableAddresses)
        let occupiedAddresses = Set(occupiedIPAddresses.compactMap { try? IPv4Address.parse($0) })
            .intersection(usableAddressSet)
        let parsedDHCPRanges = try dhcpRanges.map { try $0.parsedRange() }
        let ranges = buildRanges(
            from: usableAddresses,
            occupiedAddresses: occupiedAddresses,
            dhcpRanges: parsedDHCPRanges
        )
        let dhcpFreeAddressCount = ranges
            .filter { $0.kind == .dhcpPool }
            .reduce(0) { $0 + $1.count }
        let freeAddressCount = usableAddresses.count - occupiedAddresses.count

        return IPAvailabilityReport(
            segment: segment,
            usableAddressCount: usableAddresses.count,
            occupiedAddressCount: occupiedAddresses.count,
            freeAddressCount: freeAddressCount,
            staticFreeAddressCount: freeAddressCount - dhcpFreeAddressCount,
            dhcpFreeAddressCount: dhcpFreeAddressCount,
            dhcpRanges: dhcpRanges,
            ranges: ranges
        )
    }

    public var plainText: String {
        var lines = [
            "Rangos libres - \(segment)",
            "Usables: \(usableAddressCount)",
            "Ocupadas: \(occupiedAddressCount)",
            "Libres: \(freeAddressCount)",
            "Libres estáticas: \(staticFreeAddressCount)",
            "Libres DHCP: \(dhcpFreeAddressCount)",
            ""
        ]

        if !dhcpRanges.isEmpty {
            lines.append("Pools DHCP:")
            for range in dhcpRanges {
                lines.append("- \(range.subnetLabel): \(range.addressLabel)")
            }
            lines.append("")
        }

        if ranges.isEmpty {
            lines.append("No hay direcciones libres en el segmento.")
        } else {
            for range in ranges {
                lines.append("\(range.subnetLabel): \(range.addressLabel) (\(range.count)) - \(range.kind.label)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public var csvText: String {
        let rows = ranges.map { range in
            [
                csvEscape(range.subnetLabel),
                csvEscape(range.startAddress),
                csvEscape(range.endAddress),
                String(range.count),
                csvEscape(range.kind.label)
            ].joined(separator: ",")
        }

        return (["subred,inicio,fin,cantidad,tipo"] + rows).joined(separator: "\n")
    }

    private static func buildRanges(
        from usableAddresses: [UInt32],
        occupiedAddresses: Set<UInt32>,
        dhcpRanges: [ClosedRange<UInt32>]
    ) -> [FreeAddressRange] {
        var ranges: [FreeAddressRange] = []
        var startAddress: UInt32?
        var previousAddress: UInt32?
        var currentKind: FreeAddressRangeKind?

        func closeRange() {
            guard let startAddress, let previousAddress, let currentKind else { return }
            ranges.append(FreeAddressRange(
                startAddress: IPv4Address.string(from: startAddress),
                endAddress: IPv4Address.string(from: previousAddress),
                count: Int(previousAddress - startAddress + 1),
                subnetLabel: subnetLabel(for: startAddress),
                kind: currentKind
            ))
        }

        for address in usableAddresses {
            if occupiedAddresses.contains(address) {
                closeRange()
                startAddress = nil
                previousAddress = nil
                currentKind = nil
                continue
            }

            let addressKind = kind(for: address, dhcpRanges: dhcpRanges)
            if let previous = previousAddress,
               address == previous + 1,
               subnetLabel(for: address) == subnetLabel(for: previous),
               addressKind == currentKind {
                previousAddress = address
            } else {
                closeRange()
                startAddress = address
                previousAddress = address
                currentKind = addressKind
            }
        }

        closeRange()
        return ranges
    }

    private static func kind(
        for address: UInt32,
        dhcpRanges: [ClosedRange<UInt32>]
    ) -> FreeAddressRangeKind {
        dhcpRanges.contains { $0.contains(address) } ? .dhcpPool : .staticCandidate
    }

    private static func subnetLabel(for address: UInt32) -> String {
        let first = (address >> 24) & 0xff
        let second = (address >> 16) & 0xff
        let third = (address >> 8) & 0xff
        return "\(first).\(second).\(third).0/24"
    }

    private static func isConservativeSubnetBoundary(_ address: UInt32) -> Bool {
        let lastOctet = address & 0xff
        return lastOctet == 0 || lastOctet == 255
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
