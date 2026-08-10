import Foundation
import NetworkDiscoveryCore
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum HostSortOption: String, CaseIterable, Identifiable {
    case ip
    case name
    case type
    case port

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ip: return "IP"
        case .name: return "Nombre"
        case .type: return "Tipo"
        case .port: return "Puerto"
        }
    }
}

struct HostActionFeedback: Identifiable, Equatable {
    enum Kind {
        case opened
        case unavailable
        case info
    }

    let id = UUID()
    let message: String
    let hostID: HostDiscovery.ID?
    let kind: Kind
}

struct RefreshStatusSummary: Equatable {
    let newHosts: Int
    let updatedHosts: Int
    let unchangedHosts: Int
    let missingHosts: Int

    var changeCount: Int { newHosts + updatedHosts + missingHosts }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var segment: String = LocalNetwork.suggestedCIDR() ?? "192.168.1.0/24" { didSet { markDirtyIfNeeded() } }
    @Published var portsText: String = PortCatalog.defaultPorts.map { String($0.port) }.joined(separator: ",") { didSet { markDirtyIfNeeded() } }
    @Published var timeout: Double = 0.7 { didSet { markDirtyIfNeeded() } }
    @Published var concurrency: Int = 64 { didSet { markDirtyIfNeeded() } }
    @Published var includePing: Bool = true { didSet { markDirtyIfNeeded() } }
    @Published var searchText: String = "" { didSet { refreshVisibleHosts() } }
    @Published var selectedTypeFilter: String = "Todos" { didSet { refreshVisibleHosts() } }
    @Published var selectedPortFilter: Int? { didSet { refreshVisibleHosts() } }
    @Published var selectedRefreshFilter: HostRefreshFilter = .all { didSet { refreshVisibleHosts() } }
    @Published var sortOption: HostSortOption = .ip { didSet { refreshVisibleHosts() } }
    @Published var sortAscending: Bool = true { didSet { refreshVisibleHosts() } }
    @Published var routerHostIDs: Set<HostDiscovery.ID> = [] { didSet { markDirtyIfNeeded() } }
    @Published var defaultInternetHostID: HostDiscovery.ID? { didSet { markDirtyIfNeeded() } }
    @Published var dhcpRanges: [DHCPRange] = [] { didSet { markDirtyIfNeeded() } }
    @Published var hostAnnotations: [HostDiscovery.ID: HostAnnotation] = [:] {
        didSet {
            markDirtyIfNeeded()
            refreshVisibleHosts()
        }
    }
    @Published private(set) var refreshComparison: RefreshComparison? {
        didSet { refreshVisibleHosts() }
    }
    @Published var mapOrganization: NetworkMapOrganization = .flat { didSet { markDirtyIfNeeded() } }
    @Published private(set) var hosts: [HostDiscovery] = [] {
        didSet {
            refreshFilterOptions()
            refreshVisibleHosts()
        }
    }
    @Published private(set) var visibleHosts: [HostDiscovery] = []
    @Published private(set) var typeFilters: [String] = ["Todos"]
    @Published private(set) var portFilters: [Int] = []
    @Published private(set) var progress = ScanProgress(completedHosts: 0, totalHosts: 0)
    @Published private(set) var isScanning = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var selectedHostID: HostDiscovery.ID?
    @Published var errorMessage: String?
    @Published var isRescanConfirmationPresented = false
    @Published var isRemoveMissingConfirmationPresented = false
    @Published private(set) var actionFeedback: HostActionFeedback?

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var pendingDiscoveredHosts: [HostDiscovery] = []
    private var pendingHostFlushTask: Task<Void, Never>?
    private var lastProgressUpdate = Date.distantPast
    private var isApplyingDocument = false

    var selectedHost: HostDiscovery? {
        guard let selectedHostID else { return nil }
        return hosts.first(where: { $0.id == selectedHostID })
    }

    var progressText: String {
        guard progress.totalHosts > 0 else { return "Listo" }
        return "\(progress.completedHosts)/\(progress.totalHosts)"
    }

    var mermaidMap: String {
        NetworkMapRenderer.mermaid(
            segment: segment,
            hosts: visibleHosts,
            routerHostIDs: routerHostIDs,
            defaultInternetHostID: defaultInternetHostID,
            annotations: hostAnnotations,
            organization: mapOrganization
        )
    }

    var refreshStatuses: [HostDiscovery.ID: HostRefreshStatus] {
        refreshComparison?.statuses ?? [:]
    }

    var refreshSummary: RefreshStatusSummary? {
        guard let refreshComparison else { return nil }
        return RefreshStatusSummary(
            newHosts: refreshComparison.count(for: .new),
            updatedHosts: refreshComparison.count(for: .updated),
            unchangedHosts: refreshComparison.count(for: .unchanged),
            missingHosts: refreshComparison.count(for: .missing)
        )
    }

    var hasActiveHostFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedTypeFilter != "Todos"
            || selectedPortFilter != nil
            || selectedRefreshFilter != .all
    }

    func refreshStatus(for host: HostDiscovery) -> HostRefreshStatus? {
        guard refreshComparison != nil else { return nil }
        return refreshStatuses[host.id] ?? .unchanged
    }

    func resetHostFilters() {
        searchText = ""
        selectedTypeFilter = "Todos"
        selectedPortFilter = nil
        selectedRefreshFilter = .all
    }

    func requestRemoveMissingHosts() {
        guard refreshSummary?.missingHosts ?? 0 > 0 else { return }
        isRemoveMissingConfirmationPresented = true
    }

    func removeMissingHosts() {
        let missingHostIDs = Set(refreshStatuses.compactMap { item in
            item.value == .missing ? item.key : nil
        })
        guard !missingHostIDs.isEmpty else { return }

        isApplyingDocument = true
        hosts.removeAll { missingHostIDs.contains($0.id) }
        hostAnnotations = hostAnnotations.filter { !missingHostIDs.contains($0.key) }
        routerHostIDs = routerHostIDs.filter { !missingHostIDs.contains($0) }
        if let defaultInternetHostID, missingHostIDs.contains(defaultInternetHostID) {
            self.defaultInternetHostID = nil
        }

        if let comparison = refreshComparison {
            let remainingStatuses = comparison.statuses.filter { !missingHostIDs.contains($0.key) }
            refreshComparison = remainingStatuses.isEmpty ? nil : RefreshComparison(
                completedAt: comparison.completedAt,
                statuses: remainingStatuses
            )
        }
        isApplyingDocument = false

        if refreshComparison == nil || selectedRefreshFilter == .missing {
            selectedRefreshFilter = .all
        }
        selectedHostID = selectedHostID.flatMap { missingHostIDs.contains($0) ? nil : $0 }
            ?? defaultInternetHostID
            ?? routerHostIDs.sorted().first
            ?? visibleHosts.first?.id
        hasUnsavedChanges = true
        isRemoveMissingConfirmationPresented = false
        showFeedback("\(missingHostIDs.count) equipos no detectados eliminados.", hostID: nil, kind: .info)
    }

    var visibleMapGroupCount: Int {
        guard mapOrganization != .flat else { return 0 }
        let groupedHosts = visibleHosts.filter { !routerHostIDs.contains($0.id) }
        let labels = Set(groupedHosts.map { host in
            mapGroupLabel(for: host)
        })
        return max(1, labels.count)
    }

    func requestStartScan() {
        if !hosts.isEmpty, hasUnsavedChanges, !isScanning {
            isRescanConfirmationPresented = true
        } else {
            startScan()
        }
    }

    func requestRefreshScan() {
        guard !hosts.isEmpty else {
            requestStartScan()
            return
        }

        refreshScan()
    }

    func saveAndStartScan() {
        guard saveScan() else { return }
        startScan()
    }

    func startScan() {
        scanTask?.cancel()
        pendingHostFlushTask?.cancel()
        pendingHostFlushTask = nil
        pendingDiscoveredHosts = []
        scanGeneration += 1
        let generation = scanGeneration

        do {
            let ports = try PortCatalog.parsePorts(portsText)
            let configuration = ScanConfiguration(
                segment: segment,
                ports: ports,
                timeout: timeout,
                concurrency: concurrency,
                includePing: includePing
            )

            hosts = []
            selectedHostID = nil
            routerHostIDs = []
            defaultInternetHostID = nil
            dhcpRanges = []
            hostAnnotations = [:]
            refreshComparison = nil
            selectedRefreshFilter = .all
            hasUnsavedChanges = false
            progress = ScanProgress(completedHosts: 0, totalHosts: 0)
            errorMessage = nil
            actionFeedback = nil
            lastProgressUpdate = .distantPast
            isScanning = true
            isRefreshing = false

            scanTask = Task { [configuration, generation] in
                let scanner = NetworkScanner()
                do {
                    let results = try await scanner.scan(
                        configuration: configuration,
                        progress: { [weak self] progress in
                            await MainActor.run {
                                self?.updateProgress(progress, generation: generation)
                            }
                        },
                        hostDiscovered: { [weak self] host in
                            await MainActor.run {
                                self?.queue(host, generation: generation)
                            }
                        }
                    )

                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        self.flushPendingHosts()
                        self.hosts = results
                        self.selectedHostID = self.selectedHostID ?? results.first?.id
                        self.hasUnsavedChanges = !results.isEmpty
                        self.showFeedback("\(results.count) equipos encontrados.", hostID: nil, kind: .info)
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                } catch {
                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        self.errorMessage = error.localizedDescription
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isScanning = false
        }
    }

    func refreshScan() {
        guard !hosts.isEmpty else {
            startScan()
            return
        }

        scanTask?.cancel()
        pendingHostFlushTask?.cancel()
        pendingHostFlushTask = nil
        pendingDiscoveredHosts = []
        scanGeneration += 1
        let generation = scanGeneration
        let previousHosts = hosts
        let previousAnnotations = hostAnnotations
        let previousRouterHostIDs = routerHostIDs
        let previousDefaultInternetHostID = defaultInternetHostID
        let previousSelectedHostID = selectedHostID

        do {
            let ports = try PortCatalog.parsePorts(portsText)
            let configuration = ScanConfiguration(
                segment: segment,
                ports: ports,
                timeout: timeout,
                concurrency: concurrency,
                includePing: includePing
            )

            progress = ScanProgress(completedHosts: 0, totalHosts: 0)
            errorMessage = nil
            actionFeedback = nil
            lastProgressUpdate = .distantPast
            selectedRefreshFilter = .all
            isScanning = true
            isRefreshing = true

            scanTask = Task { [configuration, generation, previousHosts, previousAnnotations, previousRouterHostIDs, previousDefaultInternetHostID, previousSelectedHostID] in
                let scanner = NetworkScanner()
                do {
                    let results = try await scanner.scan(
                        configuration: configuration,
                        progress: { [weak self] progress in
                            await MainActor.run {
                                self?.updateProgress(progress, generation: generation)
                            }
                        }
                    )

                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        let comparison = self.applyRefreshResults(
                            results,
                            previousHosts: previousHosts,
                            previousAnnotations: previousAnnotations,
                            previousRouterHostIDs: previousRouterHostIDs,
                            previousDefaultInternetHostID: previousDefaultInternetHostID,
                            previousSelectedHostID: previousSelectedHostID
                        )
                        self.hasUnsavedChanges = true
                        self.showFeedback(self.refreshMessage(for: comparison), hostID: nil, kind: .info)
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                } catch {
                    await MainActor.run {
                        guard self.scanGeneration == generation else { return }
                        self.errorMessage = error.localizedDescription
                        self.isScanning = false
                        self.isRefreshing = false
                        self.scanTask = nil
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isScanning = false
            isRefreshing = false
        }
    }

    func stopScan() {
        let wasRefreshing = isRefreshing
        scanTask?.cancel()
        pendingHostFlushTask?.cancel()
        pendingHostFlushTask = nil
        flushPendingHosts()
        scanTask = nil
        isScanning = false
        isRefreshing = false
        if wasRefreshing {
            showFeedback("Refresco detenido. Se conserva la vista anterior.", hostID: nil, kind: .info)
        } else if !hosts.isEmpty {
            hasUnsavedChanges = true
            showFeedback("Escaneo detenido con \(hosts.count) resultados parciales.", hostID: nil, kind: .info)
        }
    }

    func markRouter(_ host: HostDiscovery) {
        routerHostIDs.insert(host.id)
        selectedHostID = host.id
    }

    func clearRouter(_ host: HostDiscovery) {
        routerHostIDs.remove(host.id)
        if defaultInternetHostID == host.id {
            defaultInternetHostID = nil
        }
    }

    func markDefaultInternet(_ host: HostDiscovery) {
        routerHostIDs.insert(host.id)
        defaultInternetHostID = host.id
        selectedHostID = host.id
    }

    func clearDefaultInternet() {
        defaultInternetHostID = nil
    }

    func annotation(for host: HostDiscovery) -> HostAnnotation {
        hostAnnotations[host.id] ?? HostAnnotation()
    }

    func setAddressAssignment(_ assignment: HostAddressAssignment, for host: HostDiscovery) {
        var annotation = annotation(for: host)
        annotation.addressAssignment = assignment
        setAnnotation(annotation, for: host)
    }

    func setSection(_ section: String, for host: HostDiscovery) {
        var annotation = annotation(for: host)
        annotation.section = section.trimmingCharacters(in: .whitespacesAndNewlines)
        setAnnotation(annotation, for: host)
    }

    private func setAnnotation(_ annotation: HostAnnotation, for host: HostDiscovery) {
        if annotation.isDefault {
            hostAnnotations.removeValue(forKey: host.id)
        } else {
            hostAnnotations[host.id] = annotation
        }
    }

    private func mapGroupLabel(for host: HostDiscovery) -> String {
        mapOrganization.groupLabel(for: host, annotation: annotation(for: host))
    }

    @discardableResult
    func openBestWebPort(for host: HostDiscovery) -> Bool {
        guard let url = bestWebURL(for: host) else {
            showFeedback("Sin HTTP/HTTPS detectado en \(host.ipAddress).", hostID: host.id, kind: .unavailable)
            return false
        }

#if os(macOS)
        let didOpen = NSWorkspace.shared.open(url)
        showFeedback(
            didOpen ? "Abriendo \(url.absoluteString)." : "No se pudo abrir \(url.absoluteString).",
            hostID: host.id,
            kind: didOpen ? .opened : .unavailable
        )
        return didOpen
#elseif os(iOS)
        UIApplication.shared.open(url)
        showFeedback("Abriendo \(url.absoluteString).", hostID: host.id, kind: .opened)
        return true
#else
        showFeedback("No se pudo abrir \(url.absoluteString).", hostID: host.id, kind: .unavailable)
        return false
#endif
    }

    func bestWebURL(for host: HostDiscovery) -> URL? {
        let preferredPorts = [443, 8443, 9443, 80, 8080, 3000, 8000, 8888]
        let openPortSet = Set(host.openPorts.map(\.port))
        guard let port = preferredPorts.first(where: { openPortSet.contains($0) }) else {
            return nil
        }

        let scheme = PortCatalog.isHTTPS(port) ? "https" : "http"
        let defaultPort = scheme == "https" ? 443 : 80
        let portSuffix = port == defaultPort ? "" : ":\(port)"
        return URL(string: "\(scheme)://\(host.ipAddress)\(portSuffix)")
    }

    func copyMermaidMap() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mermaidMap, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = mermaidMap
#endif
    }

    func makeFreeAddressReport() throws -> IPAvailabilityReport {
        try IPAvailabilityReport.build(
            segment: segment,
            occupiedIPAddresses: hosts.map(\.ipAddress),
            dhcpRanges: dhcpRanges
        )
    }

    func addDHCPRange(startAddress: String, endAddress: String) {
        let trimmedStart = startAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEnd = endAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let network = try IPv4Network(segment)
            let usableAddresses = Set(try network.hosts().compactMap { try? IPv4Address.parse($0) })
            let range = DHCPRange(startAddress: trimmedStart, endAddress: trimmedEnd)
            let parsedRange = try range.parsedRange()

            guard usableAddresses.contains(parsedRange.lowerBound),
                  usableAddresses.contains(parsedRange.upperBound)
            else {
                errorMessage = "El rango DHCP debe estar dentro del segmento \(segment)."
                return
            }

            dhcpRanges.removeAll { $0.id == range.id }
            dhcpRanges.append(range)
            dhcpRanges.sort {
                IPv4Address.sortKey(for: $0.startAddress) < IPv4Address.sortKey(for: $1.startAddress)
            }
            showFeedback("Rango DHCP añadido.", hostID: nil, kind: .info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeDHCPRange(_ range: DHCPRange) {
        dhcpRanges.removeAll { $0.id == range.id }
        showFeedback("Rango DHCP eliminado.", hostID: nil, kind: .info)
    }

    func copyFreeAddressReport(_ report: IPAvailabilityReport) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.plainText, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = report.plainText
#endif
        showFeedback("Rangos libres copiados.", hostID: nil, kind: .info)
    }

    func exportFreeAddressReport(_ report: IPAvailabilityReport) {
#if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "vada-free-ips-\(segment.safeFilenameComponent).csv"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try report.csvText.write(to: url, atomically: true, encoding: .utf8)
            showFeedback("Informe de IPs libres exportado.", hostID: nil, kind: .info)
        } catch {
            errorMessage = error.localizedDescription
        }
#else
        _ = report
        errorMessage = "Exportar CSV en iPad se implementará con el sistema de compartir."
#endif
    }

    @discardableResult
    func saveScan() -> Bool {
        do {
            let ports = try PortCatalog.parsePorts(portsText)
            let hostIDs = Set(hosts.map(\.id))
            let persistedComparison = refreshComparison.map { comparison in
                RefreshComparison(
                    completedAt: comparison.completedAt,
                    statuses: comparison.statuses.filter { hostIDs.contains($0.key) }
                )
            }
            let document = SavedScan(
                configuration: ScanConfiguration(
                    segment: segment,
                    ports: ports,
                    timeout: timeout,
                    concurrency: concurrency,
                    includePing: includePing
                ),
                hosts: hosts,
                routerHostID: defaultInternetHostID ?? routerHostIDs.sorted().first,
                routerHostIDs: routerHostIDs,
                defaultInternetHostID: defaultInternetHostID,
                dhcpRanges: dhcpRanges,
                annotations: hostAnnotations.filter { item in
                    hosts.contains(where: { $0.id == item.key })
                },
                mapOrganization: mapOrganization,
                refreshComparison: persistedComparison
            )

#if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = defaultSaveName()

            guard panel.runModal() == .OK, let url = panel.url else {
                return false
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(document).write(to: url, options: .atomic)
            hasUnsavedChanges = false
            showFeedback("Escaneo guardado.", hostID: nil, kind: .info)
            return true
#else
            _ = document
            errorMessage = "Guardar escaneos en iPad se implementará con el exportador de documentos."
            return false
#endif
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadScan() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(SavedScan.self, from: data)
            apply(document)
            showFeedback("Escaneo cargado.", hostID: nil, kind: .info)
        } catch {
            errorMessage = error.localizedDescription
        }
#else
        errorMessage = "Abrir escaneos en iPad se implementará con el importador de documentos."
#endif
    }

    private func updateProgress(_ nextProgress: ScanProgress, generation: Int) {
        guard scanGeneration == generation else { return }
        let now = Date()
        guard nextProgress.completedHosts == nextProgress.totalHosts ||
                now.timeIntervalSince(lastProgressUpdate) > 0.08
        else {
            return
        }

        progress = nextProgress
        lastProgressUpdate = now
    }

    private func queue(_ host: HostDiscovery, generation: Int) {
        guard scanGeneration == generation else { return }
        pendingDiscoveredHosts.removeAll { $0.id == host.id }
        pendingDiscoveredHosts.append(host)

        guard pendingHostFlushTask == nil else { return }
        pendingHostFlushTask = Task { [weak self, generation] in
            try? await Task.sleep(for: .milliseconds(160))
            await MainActor.run {
                guard let self, self.scanGeneration == generation else { return }
                self.flushPendingHosts()
            }
        }
    }

    private func flushPendingHosts() {
        guard !pendingDiscoveredHosts.isEmpty else {
            pendingHostFlushTask = nil
            return
        }

        var updatedHosts = hosts
        for host in pendingDiscoveredHosts {
            updatedHosts.removeAll { $0.id == host.id }
            updatedHosts.append(host)
        }
        updatedHosts.sort { IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress) }

        pendingDiscoveredHosts = []
        pendingHostFlushTask = nil
        hosts = updatedHosts
        selectedHostID = selectedHostID ?? updatedHosts.first?.id
    }

    private func append(_ host: HostDiscovery) {
        var updatedHosts = hosts
        updatedHosts.removeAll { $0.id == host.id }
        updatedHosts.append(host)
        updatedHosts.sort { IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress) }
        hosts = updatedHosts
        selectedHostID = selectedHostID ?? host.id
    }

    private func applyRefreshResults(
        _ discoveredHosts: [HostDiscovery],
        previousHosts: [HostDiscovery],
        previousAnnotations: [HostDiscovery.ID: HostAnnotation],
        previousRouterHostIDs: Set<HostDiscovery.ID>,
        previousDefaultInternetHostID: HostDiscovery.ID?,
        previousSelectedHostID: HostDiscovery.ID?
    ) -> RefreshComparison {
        let now = Date()
        let sortedDiscoveredHosts = discoveredHosts.sorted {
            IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
        }
        var consumedPreviousHostIDs = Set<HostDiscovery.ID>()
        var mergedHosts: [HostDiscovery] = []
        var mergedAnnotations: [HostDiscovery.ID: HostAnnotation] = [:]
        var nextRefreshStatuses: [HostDiscovery.ID: HostRefreshStatus] = [:]
        var newRouterHostIDs = previousRouterHostIDs
        var newDefaultInternetHostID = previousDefaultInternetHostID
        var newSelectedHostID = previousSelectedHostID

        for discoveredHost in sortedDiscoveredHosts {
            if let previousHost = bestPreviousMatch(
                for: discoveredHost,
                in: previousHosts,
                consumedHostIDs: consumedPreviousHostIDs
            ) {
                consumedPreviousHostIDs.insert(previousHost.id)
                mergedHosts.append(discoveredHost)

                var annotation = previousAnnotations[previousHost.id] ?? HostAnnotation()
                annotation.isMissing = false
                annotation.lastSeen = now
                mergedAnnotations[discoveredHost.id] = annotation

                if previousHost.id != discoveredHost.id {
                    if previousRouterHostIDs.contains(previousHost.id) {
                        newRouterHostIDs.remove(previousHost.id)
                        newRouterHostIDs.insert(discoveredHost.id)
                    }
                    if previousDefaultInternetHostID == previousHost.id {
                        newDefaultInternetHostID = discoveredHost.id
                    }
                    if previousSelectedHostID == previousHost.id {
                        newSelectedHostID = discoveredHost.id
                    }
                }

                if hostDidChange(from: previousHost, to: discoveredHost) {
                    nextRefreshStatuses[discoveredHost.id] = .updated
                } else {
                    nextRefreshStatuses[discoveredHost.id] = .unchanged
                }
            } else {
                mergedHosts.append(discoveredHost)
                mergedAnnotations[discoveredHost.id] = HostAnnotation(lastSeen: now)
                nextRefreshStatuses[discoveredHost.id] = .new
            }
        }

        for previousHost in previousHosts where !consumedPreviousHostIDs.contains(previousHost.id) {
            var annotation = previousAnnotations[previousHost.id] ?? HostAnnotation()

            annotation.isMissing = true
            annotation.lastSeen = annotation.lastSeen ?? previousHost.discoveredAt
            mergedHosts.append(previousHost)
            mergedAnnotations[previousHost.id] = annotation
            nextRefreshStatuses[previousHost.id] = .missing
        }

        mergedHosts.sort {
            IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
        }
        let mergedHostIDs = Set(mergedHosts.map(\.id))
        routerHostIDs = newRouterHostIDs.filter { mergedHostIDs.contains($0) }
        if let newDefaultInternetHostID, mergedHostIDs.contains(newDefaultInternetHostID) {
            defaultInternetHostID = newDefaultInternetHostID
            routerHostIDs.insert(newDefaultInternetHostID)
        } else {
            defaultInternetHostID = nil
        }

        if let newSelectedHostID, mergedHostIDs.contains(newSelectedHostID) {
            selectedHostID = newSelectedHostID
        } else {
            selectedHostID = defaultInternetHostID ?? routerHostIDs.sorted().first ?? mergedHosts.first?.id
        }

        hosts = mergedHosts
        hostAnnotations = mergedAnnotations.filter { mergedHostIDs.contains($0.key) }
        let comparison = RefreshComparison(
            completedAt: now,
            statuses: nextRefreshStatuses.filter { mergedHostIDs.contains($0.key) }
        )
        refreshComparison = comparison
        selectedRefreshFilter = .all

        return comparison
    }

    private func refreshMessage(for comparison: RefreshComparison) -> String {
        let summary = RefreshStatusSummary(
            newHosts: comparison.count(for: .new),
            updatedHosts: comparison.count(for: .updated),
            unchangedHosts: comparison.count(for: .unchanged),
            missingHosts: comparison.count(for: .missing)
        )
        guard summary.changeCount > 0 else {
            return "Refresco completado: \(summary.unchangedHosts) sin cambios."
        }

        var parts: [String] = []
        if summary.newHosts > 0 { parts.append("\(summary.newHosts) nuevos") }
        if summary.updatedHosts > 0 { parts.append("\(summary.updatedHosts) modificados") }
        if summary.missingHosts > 0 { parts.append("\(summary.missingHosts) no detectados") }
        if summary.unchangedHosts > 0 { parts.append("\(summary.unchangedHosts) sin cambios") }
        return "Refresco: " + parts.joined(separator: ", ") + "."
    }

    private func bestPreviousMatch(
        for discoveredHost: HostDiscovery,
        in previousHosts: [HostDiscovery],
        consumedHostIDs: Set<HostDiscovery.ID>
    ) -> HostDiscovery? {
        if let macAddress = discoveredHost.normalizedMACAddress,
           let macMatch = previousHosts.first(where: { host in
               !consumedHostIDs.contains(host.id) && host.normalizedMACAddress == macAddress
           }) {
            return macMatch
        }

        return previousHosts.first(where: { host in
            !consumedHostIDs.contains(host.id) && host.ipAddress == discoveredHost.ipAddress
        })
    }

    private func hostDidChange(from previousHost: HostDiscovery, to discoveredHost: HostDiscovery) -> Bool {
        previousHost.ipAddress != discoveredHost.ipAddress ||
            previousHost.hostname != discoveredHost.hostname ||
            previousHost.macAddress != discoveredHost.macAddress ||
            previousHost.pingResponded != discoveredHost.pingResponded ||
            previousHost.systemType != discoveredHost.systemType ||
            previousHost.openPorts != discoveredHost.openPorts
    }

    private func apply(_ document: SavedScan) {
        isApplyingDocument = true
        defer { isApplyingDocument = false }

        segment = document.configuration.segment
        portsText = document.configuration.ports.map(String.init).joined(separator: ",")
        timeout = document.configuration.timeout
        concurrency = document.configuration.concurrency
        includePing = document.configuration.includePing
        hosts = document.hosts.sorted { IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress) }
        let hostIDs = Set(hosts.map(\.id))
        routerHostIDs = document.routerHostIDs.filter { hostIDs.contains($0) }
        if let legacyRouterHostID = document.routerHostID, hostIDs.contains(legacyRouterHostID) {
            routerHostIDs.insert(legacyRouterHostID)
        }
        defaultInternetHostID = document.defaultInternetHostID.flatMap { hostIDs.contains($0) ? $0 : nil }
        if let defaultInternetHostID {
            routerHostIDs.insert(defaultInternetHostID)
        }
        dhcpRanges = document.dhcpRanges
        hostAnnotations = document.annotations.filter { item in hosts.contains(where: { $0.id == item.key }) }
        mapOrganization = document.mapOrganization
        selectedHostID = defaultInternetHostID ?? routerHostIDs.sorted().first ?? hosts.first?.id
        progress = ScanProgress(completedHosts: hosts.count, totalHosts: hosts.count)
        errorMessage = nil
        isScanning = false
        isRefreshing = false
        if let persistedComparison = document.refreshComparison {
            let statuses = Dictionary(uniqueKeysWithValues: hosts.map { host in
                let fallback: HostRefreshStatus = hostAnnotations[host.id]?.isMissing == true ? .missing : .unchanged
                return (host.id, persistedComparison.statuses[host.id] ?? fallback)
            })
            refreshComparison = RefreshComparison(
                completedAt: persistedComparison.completedAt,
                statuses: statuses
            )
        } else {
            refreshComparison = nil
        }
        selectedRefreshFilter = .all
        hasUnsavedChanges = false

        if selectedTypeFilter != "Todos", !typeFilters.contains(selectedTypeFilter) {
            selectedTypeFilter = "Todos"
        }
        if let selectedPortFilter, !portFilters.contains(selectedPortFilter) {
            self.selectedPortFilter = nil
        }
    }

    private func defaultSaveName() -> String {
        let safeSegment = segment
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "*", with: "x")
            .replacingOccurrences(of: ":", with: "-")
        return "network-scan-\(safeSegment).json"
    }

    private func refreshFilterOptions() {
        typeFilters = ["Todos"] + Set(hosts.map(\.systemType)).sorted()
        portFilters = Set(hosts.flatMap { $0.openPorts.map(\.port) }).sorted()

        if selectedTypeFilter != "Todos", !typeFilters.contains(selectedTypeFilter) {
            selectedTypeFilter = "Todos"
        }
        if let selectedPortFilter, !portFilters.contains(selectedPortFilter) {
            self.selectedPortFilter = nil
        }
    }

    private func refreshVisibleHosts() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = hosts.filter { host in
            let matchesQuery = query.isEmpty || host.searchableText.contains(query)
                || annotation(for: host).searchableText.contains(query)
                || (refreshStatuses[host.id]?.searchableText.contains(query) ?? false)
            let matchesType = selectedTypeFilter == "Todos" || host.systemType == selectedTypeFilter
            let matchesPort = selectedPortFilter == nil || host.openPorts.contains { $0.port == selectedPortFilter }
            let matchesRefresh = selectedRefreshFilter.includes(refreshStatus(for: host))
            return matchesQuery && matchesType && matchesPort && matchesRefresh
        }

        visibleHosts = filtered.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sortOption {
            case .ip:
                let lhsKey = IPv4Address.sortKey(for: lhs.ipAddress)
                let rhsKey = IPv4Address.sortKey(for: rhs.ipAddress)
                comparison = lhsKey == rhsKey ? .orderedSame : (lhsKey < rhsKey ? .orderedAscending : .orderedDescending)
            case .name:
                comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            case .type:
                comparison = lhs.systemType.localizedStandardCompare(rhs.systemType)
            case .port:
                let lhsPort = lhs.openPorts.map(\.port).min() ?? Int.max
                let rhsPort = rhs.openPorts.map(\.port).min() ?? Int.max
                if lhsPort == rhsPort {
                    let lhsKey = IPv4Address.sortKey(for: lhs.ipAddress)
                    let rhsKey = IPv4Address.sortKey(for: rhs.ipAddress)
                    comparison = lhsKey == rhsKey ? .orderedSame : (lhsKey < rhsKey ? .orderedAscending : .orderedDescending)
                } else {
                    comparison = lhsPort < rhsPort ? .orderedAscending : .orderedDescending
                }
            }

            if comparison == .orderedSame {
                return IPv4Address.sortKey(for: lhs.ipAddress) < IPv4Address.sortKey(for: rhs.ipAddress)
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }

        if let selectedHostID, !visibleHosts.contains(where: { $0.id == selectedHostID }) {
            self.selectedHostID = visibleHosts.first?.id
        } else if selectedHostID == nil, !visibleHosts.isEmpty {
            selectedHostID = visibleHosts.first?.id
        }
    }

    private func markDirtyIfNeeded() {
        guard !isApplyingDocument, !hosts.isEmpty else { return }
        hasUnsavedChanges = true
    }

    private func showFeedback(_ message: String, hostID: HostDiscovery.ID?, kind: HostActionFeedback.Kind) {
        let feedback = HostActionFeedback(message: message, hostID: hostID, kind: kind)
        actionFeedback = feedback

        Task { [weak self, feedback] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if self?.actionFeedback?.id == feedback.id {
                    self?.actionFeedback = nil
                }
            }
        }
    }
}

private extension HostDiscovery {
    var displayName: String {
        hostname ?? ipAddress
    }

    var searchableText: String {
        ([
            ipAddress,
            hostname,
            macAddress,
            systemType
        ] + openPorts.flatMap { port in
            [
                String(port.port),
                port.name,
                port.server,
                port.title
            ]
        })
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}

private extension HostAnnotation {
    var searchableText: String {
        [
            addressAssignment.label,
            section,
            isMissing ? "no detectado no visto desaparecido ausente offline" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}

private extension HostDiscovery {
    var normalizedMACAddress: String? {
        macAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension HostRefreshStatus {
    var searchableText: String {
        switch self {
        case .unchanged: return "sin cambios igual estable"
        case .new: return "nuevo aparecido"
        case .updated: return "modificado actualizado cambiado cambio"
        case .missing: return "no detectado no visto desaparecido ausente offline"
        }
    }
}

private extension String {
    var safeFilenameComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).description : "-"
        }
        .joined()
    }
}
