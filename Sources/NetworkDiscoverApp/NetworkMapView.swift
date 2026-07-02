import SwiftUI
import NetworkDiscoveryCore

struct NetworkMapView: View {
    @Environment(\.colorScheme) private var colorScheme

    let segment: String
    let hosts: [HostDiscovery]
    @Binding var selectedHostID: HostDiscovery.ID?
    let routerHostIDs: Set<HostDiscovery.ID>
    let defaultInternetHostID: HostDiscovery.ID?
    let annotations: [HostDiscovery.ID: HostAnnotation]
    let refreshStatuses: [HostDiscovery.ID: HostRefreshStatus]
    let organization: NetworkMapOrganization
    let onOpen: (HostDiscovery) -> Void
    let onMarkRouter: (HostDiscovery) -> Void

    static func preferredSize(
        hosts: [HostDiscovery],
        routerHostIDs: Set<HostDiscovery.ID>,
        annotations: [HostDiscovery.ID: HostAnnotation],
        organization: NetworkMapOrganization
    ) -> CGSize {
        NetworkMapLayout.preferredSize(
            hosts: hosts,
            routerHostIDs: routerHostIDs,
            annotations: annotations,
            organization: organization
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = NetworkMapLayout(
                segment: segment,
                hosts: hosts,
                routerHostIDs: routerHostIDs,
                annotations: annotations,
                organization: organization,
                selectedHostID: selectedHostID,
                size: proxy.size
            )

            ZStack {
                background

                ForEach(layout.edges) { edge in
                    Path { path in
                        path.move(to: edge.from)
                        let delta = max(36, abs(edge.to.y - edge.from.y) * 0.38)
                        path.addCurve(
                            to: edge.to,
                            control1: CGPoint(x: edge.from.x, y: edge.from.y + delta),
                            control2: CGPoint(x: edge.to.x, y: edge.to.y - delta)
                        )
                    }
                    .stroke(edge.isSelected ? Color.accentColor.opacity(0.62) : edge.color.opacity(0.24), lineWidth: edge.isSelected ? 2.2 : 1.3)
                }

                HubNode(title: segment, subtitle: "\(hosts.count) equipos")
                    .position(layout.hubPoint)

                ForEach(layout.groupNodes) { node in
                    GroupMapNode(title: node.label, count: node.hostCount)
                        .position(node.point)
                }

                ForEach(layout.routerNodes) { routerNode in
                    MapNodeButton(
                        host: routerNode.host,
                        selectedHostID: $selectedHostID,
                        onOpen: onOpen,
                        onMarkRouter: onMarkRouter
                    ) {
                        MapHostNode(
                            host: routerNode.host,
                            annotation: annotations[routerNode.host.id] ?? HostAnnotation(),
                            refreshStatus: refreshStatuses[routerNode.host.id],
                            isSelected: routerNode.host.id == selectedHostID,
                            isRouter: true,
                            isDefaultInternet: routerNode.host.id == defaultInternetHostID,
                            width: routerNode.size.width
                        )
                    }
                    .position(routerNode.point)
                }

                ForEach(layout.leafNodes) { node in
                    MapNodeButton(
                        host: node.host,
                        selectedHostID: $selectedHostID,
                        onOpen: onOpen,
                        onMarkRouter: onMarkRouter
                    ) {
                        MapHostNode(
                            host: node.host,
                            annotation: annotations[node.host.id] ?? HostAnnotation(),
                            refreshStatus: refreshStatuses[node.host.id],
                            isSelected: node.host.id == selectedHostID,
                            isRouter: false,
                            isDefaultInternet: false,
                            width: node.size.width
                        )
                    }
                    .position(node.point)
                }
            }
            .clipped()
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GridLines()
                .stroke(.secondary.opacity(colorScheme == .light ? 0.11 : 0.08), lineWidth: 1)
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.975, green: 0.980, blue: 0.984),
                Color(red: 0.952, green: 0.960, blue: 0.968),
                Color(red: 0.986, green: 0.988, blue: 0.990)
            ]
        }

        return [
            Color(red: 0.075, green: 0.085, blue: 0.095),
            Color(red: 0.095, green: 0.105, blue: 0.118),
            Color(red: 0.070, green: 0.078, blue: 0.088)
        ]
    }
}

private struct MapNodeButton<LabelContent: View>: View {
    let host: HostDiscovery
    @Binding var selectedHostID: HostDiscovery.ID?
    let onOpen: (HostDiscovery) -> Void
    let onMarkRouter: (HostDiscovery) -> Void
    @ViewBuilder var label: () -> LabelContent

    var body: some View {
        Button {
            selectedHostID = host.id
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                selectedHostID = host.id
                onOpen(host)
            }
        )
        .contextMenu {
            Button {
                selectedHostID = host.id
                onMarkRouter(host)
            } label: {
                Label("Marcar como router", systemImage: "network")
            }

            Button {
                selectedHostID = host.id
                onOpen(host)
            } label: {
                Label("Abrir web", systemImage: "safari")
            }
        }
        .help("\(host.ipAddress) - click para seleccionar, doble click para abrir web")
    }
}

private struct HubNode: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "network")
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 220, height: 86)
        .glassPanel(cornerRadius: 18)
    }
}

private struct MapHostNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let host: HostDiscovery
    let annotation: HostAnnotation
    let refreshStatus: HostRefreshStatus?
    let isSelected: Bool
    let isRouter: Bool
    let isDefaultInternet: Bool
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isRouter ? "network" : host.mapSymbol)
                    .foregroundStyle(isRouter ? .accentColor : host.mapColor)
                Text(host.ipAddress)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if annotation.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("No visto en el último refresco")
                } else if let refreshStatus {
                    Image(systemName: refreshStatus.symbolName)
                        .font(.caption2)
                        .foregroundStyle(refreshStatus.tint)
                        .accessibilityLabel(refreshStatus.accessibilityLabel)
                }
                if isRouter {
                    Text("R")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                if isDefaultInternet {
                    Image(systemName: "globe")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .accessibilityLabel("Salida principal a Internet")
                }
                Spacer(minLength: 0)
            }

            Text(deviceName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(nodeDetail)
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(width: width, height: NetworkMapLayout.nodeHeight, alignment: .leading)
        .background(nodeFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor.opacity(isSelected ? 0.8 : 0.24), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.15 : 0.06), radius: isSelected ? 8 : 3, y: 2)
        .opacity(annotation.isMissing ? 0.66 : 1)
    }

    private var deviceName: String {
        host.hostname ?? host.systemType
    }

    private var nodeDetail: String {
        let ports = host.openPorts.map { String($0.port) }.joined(separator: ", ").ifBlank("ping")
        var parts: [String] = []

        if host.hostname != nil {
            parts.append(host.systemType)
        }

        if !annotation.section.isEmpty {
            parts.append(annotation.section)
        }

        if annotation.isMissing {
            parts.append("no visto")
        } else if let refreshStatus {
            parts.append(refreshStatus.shortMapLabel)
        } else if annotation.addressAssignment != .unknown {
            parts.append(annotation.addressAssignment.shortLabel)
        }

        parts.append(ports)
        return parts.joined(separator: " · ")
    }

    private var borderColor: Color {
        if annotation.isMissing { return .orange }
        if let refreshStatus { return refreshStatus.tint }
        if isDefaultInternet { return .cyan }
        return isRouter ? .accentColor : host.mapColor
    }

    private var nodeFill: Color {
        if colorScheme == .light {
            return isSelected
                ? Color(red: 0.925, green: 0.955, blue: 0.995)
                : Color.white
        }

        return isSelected
            ? Color(red: 0.105, green: 0.150, blue: 0.220)
            : Color(red: 0.150, green: 0.160, blue: 0.172)
    }
}

private struct GroupMapNode: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(count) equipos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: NetworkMapLayout.groupWidth, height: NetworkMapLayout.groupHeight, alignment: .leading)
        .background(groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
        }
    }

    private var groupFill: Color {
        if colorScheme == .light {
            return Color.white
        }

        return Color(red: 0.155, green: 0.165, blue: 0.178)
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 34

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}

private struct NetworkMapLayout {
    static let hubWidth: CGFloat = 220
    static let hubHeight: CGFloat = 86
    static let minimumNodeWidth: CGFloat = 210
    static let maximumNodeWidth: CGFloat = 300
    static let nodeHeight: CGFloat = 86
    static let nodeGapX: CGFloat = 34
    static let nodeGapY: CGFloat = 30
    static let groupWidth: CGFloat = 188
    static let groupHeight: CGFloat = 56
    static let groupGapX: CGFloat = 72
    static let subtreeGapX: CGFloat = 118
    static let marginX: CGFloat = 64
    static let bottomPadding: CGFloat = 72
    static let rootY: CGFloat = 72
    static let routerY: CGFloat = 180
    static let flatHostYWithoutRouters: CGFloat = 198
    static let flatHostYWithRouters: CGFloat = 340
    static let groupYWithoutRouters: CGFloat = 198
    static let groupYWithRouters: CGFloat = 310
    static let groupToHostCenterGapY: CGFloat = 142

    struct Node: Identifiable {
        let id: HostDiscovery.ID
        let host: HostDiscovery
        let point: CGPoint
        let size: CGSize
        let groupID: String?
    }

    struct GroupNode: Identifiable {
        let id: String
        let label: String
        let hostCount: Int
        let point: CGPoint
        let parentRouterID: HostDiscovery.ID?
    }

    struct Edge: Identifiable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let color: Color
        let isSelected: Bool
    }

    let hubPoint: CGPoint
    let routerNodes: [Node]
    let groupNodes: [GroupNode]
    let leafNodes: [Node]
    let edges: [Edge]

    static func preferredSize(
        hosts: [HostDiscovery],
        routerHostIDs: Set<HostDiscovery.ID>,
        annotations: [HostDiscovery.ID: HostAnnotation],
        organization: NetworkMapOrganization
    ) -> CGSize {
        guard !hosts.isEmpty else { return CGSize(width: 760, height: 320) }

        let sortedHosts = hosts.sorted {
            IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
        }
        let routerHosts = sortedHosts.filter { routerHostIDs.contains($0.id) }
        let leafHosts = sortedHosts.filter { !routerHostIDs.contains($0.id) }

        if organization == .flat {
            let trees = flatTrees(
                leafHosts: leafHosts,
                routers: routerHosts,
                annotations: annotations
            )
            let contentWidth = totalTreeWidth(trees.map(\.width))
            let maxRows = trees.map(\.metrics.rows).max() ?? 0
            let width = max(
                760,
                contentWidth + marginX * 2
            )
            let startY: CGFloat = routerHosts.isEmpty ? flatHostYWithoutRouters : flatHostYWithRouters
            let hostBottom = bottomOfRows(startY: startY, rows: maxRows)
            let routerBottom = routerHosts.isEmpty ? rootY + hubHeight / 2 : routerY + nodeHeight / 2
            let height = max(hostBottom, routerBottom) + bottomPadding
            return CGSize(width: width, height: max(360, height))
        }

        let grouped = groupedHosts(
            hosts: leafHosts,
            annotations: annotations,
            organization: organization,
            routers: routerHosts
        )
        let trees = groupTrees(
            groupedHosts: grouped,
            routers: routerHosts,
            annotations: annotations
        )
        let contentWidth = totalTreeWidth(trees.map(\.width))
        let maxRows = trees.flatMap { $0.lanes.map(\.metrics.rows) }.max() ?? 0
        let width = max(CGFloat(860), contentWidth + marginX * 2)
        let groupY: CGFloat = routerHosts.isEmpty ? groupYWithoutRouters : groupYWithRouters
        let hostY = groupY + groupToHostCenterGapY
        let hostBottom = bottomOfRows(startY: hostY, rows: maxRows)
        let groupBottom = groupY + groupHeight / 2
        let routerBottom = routerHosts.isEmpty ? rootY + hubHeight / 2 : routerY + nodeHeight / 2
        let height = max(hostBottom, groupBottom, routerBottom) + bottomPadding
        return CGSize(width: width, height: max(420, height))
    }

    init(
        segment: String,
        hosts: [HostDiscovery],
        routerHostIDs: Set<HostDiscovery.ID>,
        annotations: [HostDiscovery.ID: HostAnnotation],
        organization: NetworkMapOrganization,
        selectedHostID: HostDiscovery.ID?,
        size: CGSize
    ) {
        hubPoint = CGPoint(x: size.width / 2, y: Self.rootY)

        let sortedHosts = hosts.sorted {
            IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
        }

        let routerHosts = sortedHosts.filter { routerHostIDs.contains($0.id) }
        let leafHosts = sortedHosts.filter { !routerHostIDs.contains($0.id) }

        if organization == .flat {
            let trees = Self.flatTrees(
                leafHosts: leafHosts,
                routers: routerHosts,
                annotations: annotations
            )
            let totalWidth = Self.totalTreeWidth(trees.map(\.width))
            var cursorX = (size.width - totalWidth) / 2
            let hostY: CGFloat = routerHosts.isEmpty ? Self.flatHostYWithoutRouters : Self.flatHostYWithRouters
            var builtRouterNodes: [Node] = []
            var builtLeafNodes: [Node] = []

            for tree in trees {
                let treeCenterX = cursorX + tree.width / 2
                if let router = tree.router {
                    let routerWidth = Self.nodeWidth(for: router, annotation: annotations[router.id])
                    builtRouterNodes.append(Node(
                        id: router.id,
                        host: router,
                        point: CGPoint(x: treeCenterX, y: Self.routerY),
                        size: CGSize(width: routerWidth, height: Self.nodeHeight),
                        groupID: nil
                    ))
                }

                if tree.metrics.columns > 0 {
                    let startX = cursorX + (tree.width - tree.metrics.hostGridWidth) / 2 + tree.metrics.itemWidth / 2
                    for (index, host) in tree.hosts.enumerated() {
                        let column = index % tree.metrics.columns
                        let row = index / tree.metrics.columns
                        let x = startX + CGFloat(column) * (tree.metrics.itemWidth + Self.nodeGapX)
                        let y = hostY + CGFloat(row) * (Self.nodeHeight + Self.nodeGapY)
                        builtLeafNodes.append(Node(
                            id: host.id,
                            host: host,
                            point: CGPoint(x: x, y: y),
                            size: CGSize(width: tree.metrics.itemWidth, height: Self.nodeHeight),
                            groupID: tree.router?.id
                        ))
                    }
                }

                cursorX += tree.width + Self.subtreeGapX
            }

            groupNodes = []
            routerNodes = builtRouterNodes
            leafNodes = builtLeafNodes
            edges = Self.makeEdges(
                hubPoint: hubPoint,
                routerNodes: builtRouterNodes,
                groupNodes: [],
                leafNodes: builtLeafNodes,
                selectedHostID: selectedHostID
            )
            return
        }

        let grouped = Self.groupedHosts(
            hosts: leafHosts,
            annotations: annotations,
            organization: organization,
            routers: routerHosts
        )
        let trees = Self.groupTrees(
            groupedHosts: grouped,
            routers: routerHosts,
            annotations: annotations
        )
        let totalWidth = Self.totalTreeWidth(trees.map(\.width))
        var cursorX = (size.width - totalWidth) / 2
        let groupY: CGFloat = routerHosts.isEmpty ? Self.groupYWithoutRouters : Self.groupYWithRouters
        let hostY = groupY + Self.groupToHostCenterGapY
        var builtRouterNodes: [Node] = []
        var builtGroupNodes: [GroupNode] = []
        var builtLeafNodes: [Node] = []

        for tree in trees {
            let treeCenterX = cursorX + tree.width / 2
            if let router = tree.router {
                let routerWidth = Self.nodeWidth(for: router, annotation: annotations[router.id])
                builtRouterNodes.append(Node(
                    id: router.id,
                    host: router,
                    point: CGPoint(x: treeCenterX, y: Self.routerY),
                    size: CGSize(width: routerWidth, height: Self.nodeHeight),
                    groupID: nil
                ))
            }

            let lanesWidth = Self.totalLaneWidth(tree.lanes.map(\.metrics))
            var laneCursorX = cursorX + (tree.width - lanesWidth) / 2

            for lane in tree.lanes {
                let laneCenterX = laneCursorX + lane.metrics.width / 2
                let groupID = Self.groupID(
                    for: lane.group.label,
                    parentRouterID: lane.group.parentRouterID
                )
                builtGroupNodes.append(GroupNode(
                    id: groupID,
                    label: lane.group.label,
                    hostCount: lane.group.hosts.count,
                    point: CGPoint(x: laneCenterX, y: groupY),
                    parentRouterID: lane.group.parentRouterID
                ))

                if lane.metrics.columns > 0 {
                    let hostStartX = laneCenterX - lane.metrics.hostGridWidth / 2 + lane.metrics.itemWidth / 2
                    for (index, host) in lane.group.hosts.enumerated() {
                        let column = index % lane.metrics.columns
                        let row = index / lane.metrics.columns
                        let x = hostStartX + CGFloat(column) * (lane.metrics.itemWidth + Self.nodeGapX)
                        let y = hostY + CGFloat(row) * (Self.nodeHeight + Self.nodeGapY)
                        builtLeafNodes.append(Node(
                            id: host.id,
                            host: host,
                            point: CGPoint(x: x, y: y),
                            size: CGSize(width: lane.metrics.itemWidth, height: Self.nodeHeight),
                            groupID: groupID
                        ))
                    }
                }

                laneCursorX += lane.metrics.width + Self.groupGapX
            }

            cursorX += tree.width + Self.subtreeGapX
        }

        routerNodes = builtRouterNodes
        groupNodes = builtGroupNodes
        leafNodes = builtLeafNodes
        edges = Self.makeEdges(
            hubPoint: hubPoint,
            routerNodes: builtRouterNodes,
            groupNodes: builtGroupNodes,
            leafNodes: builtLeafNodes,
            selectedHostID: selectedHostID
        )
    }

    func groupNode(for groupID: String?) -> GroupNode? {
        guard let groupID else { return nil }
        return groupNodes.first(where: { $0.id == groupID })
    }

    private struct GroupedHosts {
        let label: String
        let hosts: [HostDiscovery]
        let parentRouterID: HostDiscovery.ID?
    }

    private struct LaneMetrics {
        let columns: Int
        let rows: Int
        let itemWidth: CGFloat
        let hostGridWidth: CGFloat
        let width: CGFloat
    }

    private struct FlatTree {
        let router: HostDiscovery?
        let hosts: [HostDiscovery]
        let metrics: LaneMetrics
        let width: CGFloat
    }

    private struct GroupLane {
        let group: GroupedHosts
        let metrics: LaneMetrics
    }

    private struct GroupTree {
        let router: HostDiscovery?
        let lanes: [GroupLane]
        let width: CGFloat
    }

    private struct GroupKey: Hashable {
        let parentRouterID: HostDiscovery.ID?
        let label: String
    }

    private static func laneMetrics(
        for hosts: [HostDiscovery],
        annotations: [HostDiscovery.ID: HostAnnotation],
        maximumColumns: Int = 4,
        minimumWidth: CGFloat = 0
    ) -> LaneMetrics {
        guard !hosts.isEmpty else {
            return LaneMetrics(
                columns: 0,
                rows: 0,
                itemWidth: minimumNodeWidth,
                hostGridWidth: 0,
                width: minimumWidth
            )
        }

        let itemWidth = hosts
            .map { nodeWidth(for: $0, annotation: annotations[$0.id]) }
            .max() ?? minimumNodeWidth
        let count = hosts.count
        let columns = min(maximumColumns, max(1, Int(ceil(sqrt(Double(count))))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let hostGridWidth = CGFloat(columns) * itemWidth + CGFloat(columns - 1) * nodeGapX
        return LaneMetrics(
            columns: columns,
            rows: rows,
            itemWidth: itemWidth,
            hostGridWidth: hostGridWidth,
            width: max(minimumWidth, hostGridWidth)
        )
    }

    private static func groupedHosts(
        hosts: [HostDiscovery],
        annotations: [HostDiscovery.ID: HostAnnotation],
        organization: NetworkMapOrganization,
        routers: [HostDiscovery]
    ) -> [GroupedHosts] {
        let grouped = Dictionary(grouping: hosts) { host in
            GroupKey(
                parentRouterID: parentRouterID(for: [host], routers: routers),
                label: groupLabel(for: host, annotations: annotations, organization: organization)
            )
        }

        return grouped.keys.sorted { lhs, rhs in
            if lhs.parentRouterID == rhs.parentRouterID {
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }

            return parentSortKey(lhs.parentRouterID) < parentSortKey(rhs.parentRouterID)
        }.map { key in
            GroupedHosts(
                label: key.label,
                hosts: (grouped[key] ?? []).sorted {
                    IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
                },
                parentRouterID: key.parentRouterID
            )
        }
    }

    private static func flatTrees(
        leafHosts: [HostDiscovery],
        routers: [HostDiscovery],
        annotations: [HostDiscovery.ID: HostAnnotation]
    ) -> [FlatTree] {
        guard !routers.isEmpty else {
            let metrics = laneMetrics(
                for: leafHosts,
                annotations: annotations,
                maximumColumns: 6
            )
            return [
                FlatTree(
                    router: nil,
                    hosts: leafHosts,
                    metrics: metrics,
                    width: metrics.width
                )
            ]
        }

        let hostsByRouter = Dictionary(grouping: leafHosts) { host in
            parentRouterID(for: [host], routers: routers)
        }
        var trees = routers.map { router in
            let hosts = hostsByRouter[router.id] ?? []
            let metrics = laneMetrics(
                for: hosts,
                annotations: annotations,
                maximumColumns: 4
            )
            let routerWidth = nodeWidth(for: router, annotation: annotations[router.id])
            return FlatTree(
                router: router,
                hosts: hosts,
                metrics: metrics,
                width: max(routerWidth, metrics.width)
            )
        }

        let orphanHosts = hostsByRouter[nil] ?? []
        if !orphanHosts.isEmpty {
            let metrics = laneMetrics(
                for: orphanHosts,
                annotations: annotations,
                maximumColumns: 4
            )
            trees.append(FlatTree(
                router: nil,
                hosts: orphanHosts,
                metrics: metrics,
                width: metrics.width
            ))
        }

        return trees
    }

    private static func groupTrees(
        groupedHosts: [GroupedHosts],
        routers: [HostDiscovery],
        annotations: [HostDiscovery.ID: HostAnnotation]
    ) -> [GroupTree] {
        let lanes = groupedHosts.map { group in
            GroupLane(
                group: group,
                metrics: laneMetrics(
                    for: group.hosts,
                    annotations: annotations,
                    minimumWidth: groupWidth
                )
            )
        }

        guard !routers.isEmpty else {
            return [
                GroupTree(
                    router: nil,
                    lanes: lanes,
                    width: totalLaneWidth(lanes.map(\.metrics))
                )
            ]
        }

        let lanesByRouter = Dictionary(grouping: lanes) { lane in
            lane.group.parentRouterID
        }
        var trees = routers.map { router in
            let routerLanes = lanesByRouter[router.id] ?? []
            let routerWidth = nodeWidth(for: router, annotation: annotations[router.id])
            return GroupTree(
                router: router,
                lanes: routerLanes,
                width: max(routerWidth, totalLaneWidth(routerLanes.map(\.metrics)))
            )
        }

        let orphanLanes = lanesByRouter[nil] ?? []
        if !orphanLanes.isEmpty {
            trees.append(GroupTree(
                router: nil,
                lanes: orphanLanes,
                width: totalLaneWidth(orphanLanes.map(\.metrics))
            ))
        }

        return trees
    }

    private static func totalTreeWidth(_ widths: [CGFloat]) -> CGFloat {
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(CGFloat(0), +) + CGFloat(widths.count - 1) * subtreeGapX
    }

    private static func totalLaneWidth(_ metrics: [LaneMetrics]) -> CGFloat {
        guard !metrics.isEmpty else { return 0 }
        return metrics.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(metrics.count - 1) * groupGapX
    }

    private static func bottomOfRows(startY: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return startY + CGFloat(rows - 1) * (nodeHeight + nodeGapY) + nodeHeight / 2
    }

    private static func nodeWidth(for host: HostDiscovery, annotation: HostAnnotation?) -> CGFloat {
        let displayName = host.hostname ?? host.systemType
        let detail = nodeDetail(for: host, annotation: annotation)
        let detailLength = max(displayName.count, detail.count, host.ipAddress.count + 6)
        let estimatedWidth = CGFloat(detailLength) * 6.7 + 50
        return min(max(minimumNodeWidth, estimatedWidth), maximumNodeWidth)
    }

    private static func nodeDetail(for host: HostDiscovery, annotation: HostAnnotation?) -> String {
        let ports = host.openPorts.map { String($0.port) }.joined(separator: ", ").ifBlank("ping")
        var parts: [String] = []

        if host.hostname != nil {
            parts.append(host.systemType)
        }
        if let section = annotation?.section, !section.isEmpty {
            parts.append(section)
        }
        if annotation?.isMissing == true {
            parts.append("no visto")
        } else if let assignment = annotation?.addressAssignment, assignment != .unknown {
            parts.append(assignment.shortLabel)
        }
        parts.append(ports)

        return parts.joined(separator: " · ")
    }

    private static func parentSortKey(_ id: HostDiscovery.ID?) -> UInt32 {
        id.map(IPv4Address.sortKey(for:)) ?? UInt32.max
    }

    private static func makeEdges(
        hubPoint: CGPoint,
        routerNodes: [Node],
        groupNodes: [GroupNode],
        leafNodes: [Node],
        selectedHostID: HostDiscovery.ID?
    ) -> [Edge] {
        var edges: [Edge] = []
        let hubOutputPoint = bottomAnchor(hubPoint, height: hubHeight)
        let selectedGroupID = selectedHostID.flatMap { id in
            leafNodes.first(where: { $0.id == id })?.groupID
        }
        let selectedRouterID = selectedHostID.flatMap { id -> HostDiscovery.ID? in
            if routerNodes.contains(where: { $0.id == id }) {
                return id
            }

            guard let selectedLeaf = leafNodes.first(where: { $0.id == id }),
                  let parentID = selectedLeaf.groupID
            else {
                return nil
            }

            if let groupParentID = groupNodes.first(where: { $0.id == parentID })?.parentRouterID {
                return groupParentID
            }

            return routerNodes.contains(where: { $0.id == parentID }) ? parentID : nil
        }

        for routerNode in routerNodes {
            edges.append(Edge(
                id: "edge-root-router-\(routerNode.id)",
                from: hubOutputPoint,
                to: topAnchor(routerNode.point, height: nodeHeight),
                color: .accentColor,
                isSelected: routerNode.id == selectedRouterID
            ))
        }

        for groupNode in groupNodes {
            let parent = groupNode.parentRouterID
                .flatMap { id in routerNodes.first(where: { $0.id == id })?.point }
                .map { bottomAnchor($0, height: nodeHeight) } ??
                hubOutputPoint
            edges.append(Edge(
                id: "edge-group-\(groupNode.id)",
                from: parent,
                to: topAnchor(groupNode.point, height: groupHeight),
                color: .accentColor,
                isSelected: groupNode.id == selectedGroupID
            ))
        }

        for node in leafNodes {
            let parent = node.groupID
                .flatMap { id in groupNodes.first(where: { $0.id == id })?.point }
                .map { bottomAnchor($0, height: groupHeight) } ??
                node.groupID
                    .flatMap { id in routerNodes.first(where: { $0.id == id })?.point }
                    .map { bottomAnchor($0, height: nodeHeight) } ??
                hubOutputPoint
            edges.append(Edge(
                id: "edge-host-\(node.id)",
                from: parent,
                to: topAnchor(node.point, height: nodeHeight),
                color: node.host.mapColor,
                isSelected: node.id == selectedHostID
            ))
        }

        return edges
    }

    private static func topAnchor(_ point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y - height / 2)
    }

    private static func bottomAnchor(_ point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y + height / 2)
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

    private static func groupID(for label: String, parentRouterID: HostDiscovery.ID?) -> String {
        let parentPrefix = parentRouterID.map { "router_\(sanitizeID($0))" } ?? "root"
        return "\(parentPrefix)_group_\(sanitizeID(label))"
    }

    private static func sanitizeID(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        .map(String.init)
        .joined()
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
}

private extension HostDiscovery {
    var mapSymbol: String {
        let ports = Set(openPorts.map(\.port))
        if systemType.localizedCaseInsensitiveContains("airzone") { return "thermometer" }
        if systemType.localizedCaseInsensitiveContains("fronius") || systemType.localizedCaseInsensitiveContains("victron") {
            return "sun.max"
        }
        if ports.contains(8090) { return "sun.max" }
        if ports.contains(502) { return "cpu" }
        if ports.contains(9100) { return "printer" }
        if ports.contains(554) { return "video" }
        if ports.contains(3389) || ports.contains(445) { return "desktopcomputer" }
        if ports.contains(1883) { return "sensor" }
        if ports.contains(22) { return "terminal" }
        if ports.contains(80) || ports.contains(443) || ports.contains(3000) || ports.contains(8080) || ports.contains(8443) { return "globe" }
        return "network"
    }

    var mapColor: Color {
        let ports = Set(openPorts.map(\.port))
        if systemType.localizedCaseInsensitiveContains("airzone") { return .cyan }
        if systemType.localizedCaseInsensitiveContains("fronius") || systemType.localizedCaseInsensitiveContains("victron") {
            return Color(red: 0.05, green: 0.48, blue: 0.36)
        }
        if ports.contains(8090) { return Color(red: 0.05, green: 0.48, blue: 0.36) }
        if ports.contains(502) { return .orange }
        if ports.contains(9100) { return .purple }
        if ports.contains(554) { return .pink }
        if ports.contains(22) { return .green }
        if ports.contains(80) || ports.contains(443) || ports.contains(3000) { return .blue }
        return .secondary
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private extension HostAddressAssignment {
    var shortLabel: String {
        switch self {
        case .unknown: return ""
        case .staticAddress: return "estática"
        case .dynamicAddress: return "dinámica"
        case .dhcpReservation: return "reserva"
        }
    }
}

private extension HostRefreshStatus {
    var shortMapLabel: String {
        switch self {
        case .new: return "nuevo"
        case .updated: return "cambio"
        case .missing: return "no visto"
        }
    }

    var tint: Color {
        switch self {
        case .new: return .green
        case .updated: return .blue
        case .missing: return .orange
        }
    }

    var symbolName: String {
        switch self {
        case .new: return "plus.circle.fill"
        case .updated: return "arrow.triangle.2.circlepath.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .new: return "Nuevo en el último refresco"
        case .updated: return "Actualizado en el último refresco"
        case .missing: return "No visto en el último refresco"
        }
    }
}
