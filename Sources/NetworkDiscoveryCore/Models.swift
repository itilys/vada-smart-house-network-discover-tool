import Foundation

public enum ServiceCategory: String, Codable, Sendable {
    case remoteAccess
    case web
    case industrial
    case fileSharing
    case database
    case messaging
    case media
    case printing
    case network
    case unknown
}

public struct PortDefinition: Identifiable, Hashable, Codable, Sendable {
    public let port: Int
    public let name: String
    public let category: ServiceCategory

    public var id: Int { port }

    public init(port: Int, name: String, category: ServiceCategory) {
        self.port = port
        self.name = name
        self.category = category
    }
}

public struct OpenPort: Identifiable, Hashable, Codable, Sendable {
    public let port: Int
    public let name: String
    public let category: ServiceCategory
    public var server: String?
    public var title: String?

    public var id: Int { port }

    public init(
        port: Int,
        name: String,
        category: ServiceCategory,
        server: String? = nil,
        title: String? = nil
    ) {
        self.port = port
        self.name = name
        self.category = category
        self.server = server
        self.title = title
    }
}

public struct HostDiscovery: Identifiable, Hashable, Codable, Sendable {
    public let ipAddress: String
    public let hostname: String?
    public let macAddress: String?
    public let pingResponded: Bool
    public let systemType: String
    public let openPorts: [OpenPort]
    public let discoveredAt: Date

    public var id: String { ipAddress }

    public init(
        ipAddress: String,
        hostname: String?,
        macAddress: String? = nil,
        pingResponded: Bool,
        systemType: String,
        openPorts: [OpenPort],
        discoveredAt: Date = Date()
    ) {
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.macAddress = macAddress
        self.pingResponded = pingResponded
        self.systemType = systemType
        self.openPorts = openPorts
        self.discoveredAt = discoveredAt
    }
}

public struct ScanConfiguration: Hashable, Codable, Sendable {
    public var segment: String
    public var ports: [Int]
    public var timeout: TimeInterval
    public var concurrency: Int
    public var includePing: Bool
    public var maximumHosts: Int

    public init(
        segment: String,
        ports: [Int] = PortCatalog.defaultPorts.map(\.port),
        timeout: TimeInterval = 0.7,
        concurrency: Int = 64,
        includePing: Bool = true,
        maximumHosts: Int = 4096
    ) {
        self.segment = segment
        self.ports = ports
        self.timeout = timeout
        self.concurrency = concurrency
        self.includePing = includePing
        self.maximumHosts = maximumHosts
    }
}

public struct ScanProgress: Hashable, Codable, Sendable {
    public let completedHosts: Int
    public let totalHosts: Int

    public var fraction: Double {
        guard totalHosts > 0 else { return 0 }
        return Double(completedHosts) / Double(totalHosts)
    }

    public init(completedHosts: Int, totalHosts: Int) {
        self.completedHosts = completedHosts
        self.totalHosts = totalHosts
    }
}

public enum HostAddressAssignment: String, Codable, CaseIterable, Sendable {
    case unknown
    case staticAddress
    case dynamicAddress
    case dhcpReservation

    public var label: String {
        switch self {
        case .unknown: return "Sin definir"
        case .staticAddress: return "IP estática"
        case .dynamicAddress: return "IP dinámica"
        case .dhcpReservation: return "Reserva DHCP"
        }
    }
}

public struct HostAnnotation: Hashable, Codable, Sendable {
    public var addressAssignment: HostAddressAssignment
    public var section: String
    public var isMissing: Bool
    public var lastSeen: Date?

    public init(
        addressAssignment: HostAddressAssignment = .unknown,
        section: String = "",
        isMissing: Bool = false,
        lastSeen: Date? = nil
    ) {
        self.addressAssignment = addressAssignment
        self.section = section
        self.isMissing = isMissing
        self.lastSeen = lastSeen
    }

    public var isDefault: Bool {
        addressAssignment == .unknown && section.isEmpty && !isMissing && lastSeen == nil
    }

    enum CodingKeys: String, CodingKey {
        case addressAssignment
        case section
        case isMissing
        case lastSeen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addressAssignment = try container.decodeIfPresent(HostAddressAssignment.self, forKey: .addressAssignment) ?? .unknown
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? ""
        isMissing = try container.decodeIfPresent(Bool.self, forKey: .isMissing) ?? false
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)
    }
}

public enum NetworkMapOrganization: String, Codable, CaseIterable, Sendable {
    case flat
    case subnet
    case addressAssignment
    case section

    public var label: String {
        switch self {
        case .flat: return "Plano"
        case .subnet: return "Subred"
        case .addressAssignment: return "IP"
        case .section: return "Sección"
        }
    }
}

public struct SavedScan: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public var savedAt: Date
    public var configuration: ScanConfiguration
    public var hosts: [HostDiscovery]
    public var routerHostID: HostDiscovery.ID?
    public var routerHostIDs: Set<HostDiscovery.ID>
    public var defaultInternetHostID: HostDiscovery.ID?
    public var dhcpRanges: [DHCPRange]
    public var annotations: [HostDiscovery.ID: HostAnnotation]
    public var mapOrganization: NetworkMapOrganization

    public init(
        schemaVersion: Int = 5,
        savedAt: Date = Date(),
        configuration: ScanConfiguration,
        hosts: [HostDiscovery],
        routerHostID: HostDiscovery.ID? = nil,
        routerHostIDs: Set<HostDiscovery.ID> = [],
        defaultInternetHostID: HostDiscovery.ID? = nil,
        dhcpRanges: [DHCPRange] = [],
        annotations: [HostDiscovery.ID: HostAnnotation] = [:],
        mapOrganization: NetworkMapOrganization = .flat
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.configuration = configuration
        self.hosts = hosts
        let resolvedRouterHostIDs = routerHostIDs.union(routerHostID.map { [$0] } ?? [])
        self.routerHostID = defaultInternetHostID ?? routerHostID ?? resolvedRouterHostIDs.sorted().first
        self.routerHostIDs = resolvedRouterHostIDs
        self.defaultInternetHostID = defaultInternetHostID
        self.dhcpRanges = dhcpRanges
        self.annotations = annotations
        self.mapOrganization = mapOrganization
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case configuration
        case hosts
        case routerHostID
        case routerHostIDs
        case defaultInternetHostID
        case dhcpRanges
        case annotations
        case mapOrganization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        configuration = try container.decode(ScanConfiguration.self, forKey: .configuration)
        hosts = try container.decode([HostDiscovery].self, forKey: .hosts)
        routerHostID = try container.decodeIfPresent(HostDiscovery.ID.self, forKey: .routerHostID)
        routerHostIDs = try container.decodeIfPresent(Set<HostDiscovery.ID>.self, forKey: .routerHostIDs) ??
            Set(routerHostID.map { [$0] } ?? [])
        defaultInternetHostID = try container.decodeIfPresent(HostDiscovery.ID.self, forKey: .defaultInternetHostID)
        dhcpRanges = try container.decodeIfPresent([DHCPRange].self, forKey: .dhcpRanges) ?? []
        annotations = try container.decodeIfPresent([HostDiscovery.ID: HostAnnotation].self, forKey: .annotations) ?? [:]
        mapOrganization = try container.decodeIfPresent(NetworkMapOrganization.self, forKey: .mapOrganization) ?? .flat

        if let routerHostID, !routerHostIDs.contains(routerHostID) {
            routerHostIDs.insert(routerHostID)
        }
        if let defaultInternetHostID {
            routerHostIDs.insert(defaultInternetHostID)
        }
    }
}
