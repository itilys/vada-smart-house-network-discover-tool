import Foundation

public enum NetworkMapRenderer {
    public static func mermaid(
        segment: String,
        hosts: [HostDiscovery],
        routerHostID: HostDiscovery.ID? = nil,
        routerHostIDs: Set<HostDiscovery.ID> = [],
        defaultInternetHostID: HostDiscovery.ID? = nil,
        annotations: [HostDiscovery.ID: HostAnnotation] = [:],
        organization: NetworkMapOrganization = .flat
    ) -> String {
        var lines = [
            "flowchart LR",
            "  network[\"\(escape(segment))\"]"
        ]

        let hostIDs = Set(hosts.map(\.id))
        var validRouterHostIDs = routerHostIDs.filter { hostIDs.contains($0) }
        if let routerHostID, hostIDs.contains(routerHostID) {
            validRouterHostIDs.insert(routerHostID)
        }
        if let defaultInternetHostID, hostIDs.contains(defaultInternetHostID) {
            validRouterHostIDs.insert(defaultInternetHostID)
        }
        let validDefaultInternetHostID = defaultInternetHostID.flatMap { validRouterHostIDs.contains($0) ? $0 : nil }
        let sortedHosts = hosts.sorted(by: { IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress) })

        let routers = sortedHosts.filter { validRouterHostIDs.contains($0.id) }
        for router in routers {
            let routerLabel = label(
                for: router,
                annotations: annotations,
                isRouter: true,
                isDefaultInternet: router.id == validDefaultInternetHostID
            )
            lines.append("  network --> \(nodeID(for: router))[\"\(escape(routerLabel))\"]")
        }

        if organization == .flat {
            for host in sortedHosts {
                guard !validRouterHostIDs.contains(host.id) else { continue }
                let label = label(for: host, annotations: annotations, isRouter: false, isDefaultInternet: false)
                if let parentRouterID = parentRouterID(for: [host], routers: routers) {
                    lines.append("  \(nodeID(forID: parentRouterID)) --> \(nodeID(for: host))[\"\(escape(label))\"]")
                } else {
                    lines.append("  network --> \(nodeID(for: host))[\"\(escape(label))\"]")
                }
            }

            return lines.joined(separator: "\n")
        }

        let groupedHosts = Dictionary(grouping: sortedHosts.filter { !validRouterHostIDs.contains($0.id) }) { host in
            groupLabel(for: host, annotations: annotations, organization: organization)
        }

        for group in groupedHosts.keys.sorted() {
            let groupID = "group_\(sanitizeID(group))"
            let parentID = parentRouterID(for: groupedHosts[group] ?? [], routers: routers).map(nodeID(forID:)) ?? "network"
            lines.append("  \(parentID) --> \(groupID)[\"\(escape(group))\"]")

            for host in (groupedHosts[group] ?? []) {
                let hostLabel = label(
                    for: host,
                    annotations: annotations,
                    isRouter: false,
                    isDefaultInternet: false
                )
                lines.append("  \(groupID) --> \(nodeID(for: host))[\"\(escape(hostLabel))\"]")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func plainText(segment: String, hosts: [HostDiscovery]) -> String {
        var lines = ["\(segment)"]
        for host in hosts.sorted(by: { IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress) }) {
            let ports = host.openPorts.map { "\($0.port)/\($0.name)" }.joined(separator: ", ")
            lines.append("+- \(host.ipAddress) \(host.hostname ?? "") \(host.systemType) \(ports)")
        }
        return lines.joined(separator: "\n")
    }

    private static func label(
        for host: HostDiscovery,
        annotations: [HostDiscovery.ID: HostAnnotation],
        isRouter: Bool,
        isDefaultInternet: Bool
    ) -> String {
        let services = host.openPorts.map { "\($0.port) \($0.name)" }.joined(separator: ", ")
        let annotation = annotations[host.id]

        return [
            host.ipAddress,
            host.hostname,
            host.macAddress,
            isRouter ? "Router" : nil,
            isDefaultInternet ? "Salida Internet" : nil,
            host.systemType,
            annotation?.isMissing == true ? "No visto" : nil,
            annotation?.addressAssignment == .unknown ? nil : annotation?.addressAssignment.label,
            annotation?.section.isEmpty == false ? annotation?.section : nil,
            services.isEmpty ? nil : services
        ]
        .compactMap { $0 }
        .joined(separator: "<br/>")
    }

    private static func groupLabel(
        for host: HostDiscovery,
        annotations: [HostDiscovery.ID: HostAnnotation],
        organization: NetworkMapOrganization
    ) -> String {
        let annotation = annotations[host.id] ?? HostAnnotation()
        switch organization {
        case .flat:
            return "Equipos"
        case .subnet:
            return subnetLabel(for: host.ipAddress)
        case .addressAssignment:
            return annotation.addressAssignment.label
        case .section:
            return annotation.section.isEmpty ? "Sin sección" : annotation.section
        }
    }

    private static func nodeID(for host: HostDiscovery) -> String {
        nodeID(forID: host.id)
    }

    private static func nodeID(forID id: String) -> String {
        "host_\(sanitizeID(id))"
    }

    private static func parentRouterID(for hosts: [HostDiscovery], routers: [HostDiscovery]) -> HostDiscovery.ID? {
        guard !routers.isEmpty else { return nil }
        guard routers.count > 1 else { return routers.first?.id }

        let hostSubnets = Dictionary(grouping: hosts, by: { subnetLabel(for: $0.ipAddress) })
            .mapValues(\.count)
        guard !hostSubnets.isEmpty else { return nil }

        return routers.max { lhs, rhs in
            let lhsScore = hostSubnets[subnetLabel(for: lhs.ipAddress)] ?? 0
            let rhsScore = hostSubnets[subnetLabel(for: rhs.ipAddress)] ?? 0
            if lhsScore == rhsScore {
                return IPv4Address.sortKey(for: lhs.ipAddress) > IPv4Address.sortKey(for: rhs.ipAddress)
            }
            return lhsScore < rhsScore
        }?.id
    }

    private static func subnetLabel(for ipAddress: String) -> String {
        let parts = ipAddress.split(separator: ".")
        guard parts.count == 4 else { return "Otra subred" }
        return "\(parts[0]).\(parts[1]).\(parts[2]).0/24"
    }

    private static func sanitizeID(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .map(String.init)
        .joined()
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
