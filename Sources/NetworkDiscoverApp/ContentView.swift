import SwiftUI
import NetworkDiscoveryCore
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var model = AppModel()
#if os(macOS)
    @EnvironmentObject private var updateManager: UpdateManager
#endif
#if os(iOS)
    @State private var isAboutPresented = false
#endif

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } content: {
            HostListView(model: model)
                .navigationSplitViewColumnWidth(min: 430, ideal: 520)
        } detail: {
            DetailPanel(model: model)
                .navigationSplitViewColumnWidth(min: 540, ideal: 700)
        }
        .alert(
            "No se pudo escanear",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Reemplazar escaneo actual", isPresented: $model.isRescanConfirmationPresented) {
            Button("Guardar y escanear") {
                model.saveAndStartScan()
            }
            Button("Escanear sin guardar", role: .destructive) {
                model.startScan()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El escaneo actual tiene cambios sin guardar. Si continúas, se perderán de la vista actual.")
        }
#if os(macOS)
        .task {
            await updateManager.checkIfNeeded()
        }
        .alert(item: $updateManager.notice) { notice in
            updateAlert(for: notice)
        }
#endif
#if os(iOS)
        .sheet(isPresented: $isAboutPresented) {
            VaDaAboutView()
        }
#endif
    }

#if os(macOS)
    private func updateAlert(for notice: UpdateNotice) -> Alert {
        switch notice {
        case .available(let release, let currentVersion):
            let releaseName = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayVersion = releaseName.flatMap { $0.isEmpty ? nil : $0 } ?? release.tagName
            return Alert(
                title: Text("Nueva versión disponible"),
                message: Text("\(displayVersion) está disponible. Tienes instalada la versión \(currentVersion)."),
                primaryButton: .default(Text("Ver en GitHub")) {
                    NSWorkspace.shared.open(release.pageURL)
                },
                secondaryButton: .cancel(Text("Más tarde"))
            )
        case .upToDate(let currentVersion):
            return Alert(
                title: Text("VaDa Network Discover está actualizado"),
                message: Text("Tienes instalada la última versión disponible (\(currentVersion))."),
                dismissButton: .default(Text("OK"))
            )
        case .failed(let message):
            return Alert(
                title: Text("No se pudieron buscar actualizaciones"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
#endif

    @ViewBuilder
    private var sidebar: some View {
#if os(iOS)
        ScanSidebar(model: model) {
            isAboutPresented = true
        }
#else
        ScanSidebar(model: model)
#endif
    }
}

private struct ScanSidebar: View {
    @ObservedObject var model: AppModel
#if os(iOS)
    let onAbout: () -> Void
#endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                GlassGroup {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Segmento", text: $model.segment)
                            .textFieldStyle(.roundedBorder)

                        TextField("Puertos TCP", text: $model.portsText)
                            .textFieldStyle(.roundedBorder)

                        Toggle(isOn: $model.includePing) {
                            Label("Ping ICMP", systemImage: "waveform.path.ecg")
                        }
                    }
                    .padding(14)
                    .glassPanel()
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Timeout", systemImage: "timer")
                        Spacer()
                        Text("\(model.timeout, specifier: "%.1f") s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.timeout, in: 0.2...3.0, step: 0.1)

                    Stepper(value: $model.concurrency, in: 1...256, step: 1) {
                        Label("Concurrencia \(model.concurrency)", systemImage: "speedometer")
                    }
                }
                .padding(14)
                .glassPanel()

                VStack(spacing: 12) {
                    if model.isScanning {
                        Button {
                            model.stopScan()
                        } label: {
                            Label(model.isRefreshing ? "Detener refresco" : "Detener", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        ProgressView(value: model.progress.fraction)
                        Text(model.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            PrimaryGlassButton(action: model.requestStartScan) {
                                Label("Escanear", systemImage: "dot.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)

                            Button {
                                model.requestRefreshScan()
                            } label: {
                                Label("Refrescar", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(model.hosts.isEmpty)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        model.loadScan()
                    } label: {
                        Label("Abrir", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.saveScan()
                    } label: {
                        Label(model.hasUnsavedChanges ? "Guardar *" : "Guardar", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.hosts.isEmpty)
                }

                if model.hasUnsavedChanges {
                    Label("Cambios sin guardar", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SummaryStrip(hosts: model.hosts, isScanning: model.isScanning)

#if os(iOS)
                Button(action: onAbout) {
                    Label("Acerca de VaDa Network Discover", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
#endif
            }
            .padding(18)
        }
        .navigationTitle("Discover")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VaDaLogoMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VaDa Network Discover")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text("Utilidad gratuita para redes locales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text("VaDa SmartHouse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VaDaLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.42, blue: 0.33),
                            Color(red: 0.10, green: 0.58, blue: 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.25))
                .offset(x: size * 0.14, y: -size * 0.13)
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: -size * 0.08, y: size * 0.08)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("VaDa SmartHouse")
    }
}

private struct VaDaAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                VaDaLogoMark(size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("VaDa Network Discover")
                        .font(.title2.weight(.semibold))
                    Text("Una utilidad gratuita de VaDa SmartHouse")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Descubre equipos, puertos abiertos y dispositivos VaDa SolarBrain o VaDa SolarGenius en redes locales autorizadas.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Detecta HTTP, HTTPS, SSH, Modbus, MQTT, Airzone y equipos solares.", systemImage: "network")
                Label("Permite guardar, refrescar y exportar mapas de red.", systemImage: "map")
                Label("VaDa SmartHouse - https://vadasmarthouse.com/", systemImage: "globe")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cerrar") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct VaDaBrandFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            VaDaLogoMark(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("VaDa SmartHouse")
                    .font(.caption.weight(.semibold))
                Text("https://vadasmarthouse.com/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryStrip: View {
    let hosts: [HostDiscovery]
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 10) {
            SummaryMetric(title: "Equipos", value: "\(hosts.count)", symbol: "desktopcomputer")
            SummaryMetric(title: "HTTP", value: "\(countPorts([80, 443, 3000, 8080, 8443]))", symbol: "globe")
            SummaryMetric(title: "VaDa", value: "\(countPorts([8090]))", symbol: "sun.max")
            SummaryMetric(title: "Modbus", value: "\(countPorts([502]))", symbol: "cpu")
        }
        .padding(12)
        .glassPanel(cornerRadius: 14)
        .opacity(isScanning && hosts.isEmpty ? 0.72 : 1)
    }

    private func countPorts(_ ports: Set<Int>) -> Int {
        hosts.filter { host in
            host.openPorts.contains { ports.contains($0.port) }
        }.count
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HostListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            listHeader

            if model.hosts.isEmpty {
                ContentUnavailableView(
                    model.isRefreshing ? "Refrescando" : (model.isScanning ? "Escaneando" : "Sin equipos"),
                    systemImage: model.isScanning ? "dot.radiowaves.left.and.right" : "network",
                    description: Text(model.isRefreshing ? "Comparando el escaneo actual con la red." : (model.isScanning ? "Buscando hosts y puertos abiertos." : "Introduce un segmento y ejecuta el escaneo."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleHosts.isEmpty {
                ContentUnavailableView(
                    "Sin coincidencias",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Ajusta el texto, tipo o puerto del filtro.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.visibleHosts) { host in
                                HostRow(
                                    host: host,
                                    annotation: model.annotation(for: host),
                                    refreshStatus: model.refreshStatuses[host.id],
                                    isSelected: host.id == model.selectedHostID,
                                    isRouter: model.routerHostIDs.contains(host.id),
                                    isDefaultInternet: host.id == model.defaultInternetHostID,
                                    webURL: model.bestWebURL(for: host),
                                    actionFeedback: model.actionFeedback?.hostID == host.id ? model.actionFeedback : nil
                                )
                                .id(host.id)
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .simultaneousGesture(
                                    TapGesture(count: 1).onEnded {
                                        model.selectedHostID = host.id
                                    }
                                )
                                .highPriorityGesture(
                                    TapGesture(count: 2).onEnded {
                                        model.selectedHostID = host.id
                                        model.openBestWebPort(for: host)
                                    }
                                )
                                .contextMenu {
                                    if model.routerHostIDs.contains(host.id) {
                                        Button {
                                            model.clearRouter(host)
                                        } label: {
                                            Label("Quitar router", systemImage: "xmark.circle")
                                        }
                                    } else {
                                        Button {
                                            model.markRouter(host)
                                        } label: {
                                            Label("Marcar como router", systemImage: "network")
                                        }
                                    }

                                    if host.id == model.defaultInternetHostID {
                                        Button {
                                            model.clearDefaultInternet()
                                        } label: {
                                            Label("Quitar salida Internet", systemImage: "wifi.slash")
                                        }
                                    } else {
                                        Button {
                                            model.markDefaultInternet(host)
                                        } label: {
                                            Label("Salida Internet", systemImage: "globe")
                                        }
                                    }

                                    Button {
                                        model.openBestWebPort(for: host)
                                    } label: {
                                        Label("Abrir web", systemImage: "safari")
                                    }
                                    .disabled(model.bestWebURL(for: host) == nil)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .background(listBackground)
                    .onChange(of: model.selectedHostID) { _, selectedHostID in
                        guard let selectedHostID,
                              model.visibleHosts.contains(where: { $0.id == selectedHostID })
                        else {
                            return
                        }

                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(selectedHostID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(listBackground)
    }

    private var listBackground: Color {
        colorScheme == .light
            ? Color(red: 0.985, green: 0.987, blue: 0.990)
            : Color(red: 0.075, green: 0.080, blue: 0.088)
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equipos")
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.isRefreshing ? "Refresco" : model.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if model.isRefreshing {
                        Text(model.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else if !model.hosts.isEmpty {
                    Text("\(model.visibleHosts.count)/\(model.hosts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !model.hosts.isEmpty {
                TextField("Filtrar por nombre, IP, tipo o puerto", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Picker("Tipo", selection: $model.selectedTypeFilter) {
                        ForEach(model.typeFilters, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Picker(
                        "Puerto",
                        selection: Binding(
                            get: { model.selectedPortFilter ?? -1 },
                            set: { model.selectedPortFilter = $0 == -1 ? nil : $0 }
                        )
                    ) {
                        Text("Todos").tag(-1)
                        ForEach(model.portFilters, id: \.self) { port in
                            Text("\(port)").tag(port)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 105)
                }

                HStack(spacing: 8) {
                    Picker("Orden", selection: $model.sortOption) {
                        ForEach(HostSortOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()

                    Button {
                        model.sortAscending.toggle()
                    } label: {
                        Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
                    }
                    .help(model.sortAscending ? "Orden ascendente" : "Orden descendente")
                }
            }

            if let feedback = model.actionFeedback {
                FeedbackBanner(feedback: feedback)
            }
        }
        .padding([.horizontal, .top], 18)
        .padding(.bottom, 10)
    }
}

private struct HostRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let host: HostDiscovery
    let annotation: HostAnnotation
    let refreshStatus: HostRefreshStatus?
    let isSelected: Bool
    let isRouter: Bool
    let isDefaultInternet: Bool
    let webURL: URL?
    let actionFeedback: HostActionFeedback?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isRouter ? "network" : host.symbolName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isRouter ? .accentColor : host.tintColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(host.ipAddress)
                        .font(.headline.monospacedDigit())
                    if annotation.isMissing {
                        RefreshStatusPill(status: .missing)
                    } else if let refreshStatus {
                        RefreshStatusPill(status: refreshStatus)
                    }
                    if host.pingResponded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Ping OK")
                    }
                    if isRouter {
                        statusPill("router", color: .blue)
                    }
                    if isDefaultInternet {
                        statusPill("internet", color: .cyan)
                    }
                    if webURL != nil {
                        Image(systemName: "safari")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Web disponible")
                    }
                    if let actionFeedback {
                        Text(actionFeedback.kind == .opened ? "abriendo" : "sin web")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(actionFeedback.kind.tint.opacity(0.16), in: Capsule())
                            .foregroundStyle(actionFeedback.kind.tint)
                    }
                }

                Text(host.hostname ?? host.systemType)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                PortBadges(ports: host.openPorts)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowStroke, lineWidth: isSelected ? 1.2 : 1)
        }
        .opacity(annotation.isMissing ? missingOpacity : 1)
    }

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .light ? 0.18 : 0.15)
        }

        if colorScheme == .light {
            return Color(red: 0.955, green: 0.962, blue: 0.970)
        }

        return Color.white.opacity(0.025)
    }

    private var rowStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .light ? 0.54 : 0.46)
        }

        return Color.primary.opacity(colorScheme == .light ? 0.08 : 0.10)
    }

    private var missingOpacity: Double {
        colorScheme == .light ? 0.78 : 0.66
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    private var metadataText: String {
        [
            annotation.isMissing ? "No visto en el último refresco" : nil,
            refreshStatus?.metadataText,
            annotation.addressAssignment == .unknown ? nil : annotation.addressAssignment.label,
            annotation.section.isEmpty ? nil : annotation.section,
            host.macAddress
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct RefreshStatusPill: View {
    let status: HostRefreshStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.16), in: Capsule())
            .foregroundStyle(status.tint)
    }
}

private struct PortBadges: View {
    let ports: [OpenPort]

    var body: some View {
        HStack(spacing: 6) {
            if ports.isEmpty {
                Text("ping")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.12), in: Capsule())
            } else {
                ForEach(ports.prefix(4), id: \.port) { port in
                    Text("\(port.port) \(port.name)")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(port.badgeColor.opacity(0.14), in: Capsule())
                }

                if ports.count > 4 {
                    Text("+\(ports.count - 4)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

private struct FeedbackBanner: View {
    let feedback: HostActionFeedback

    var body: some View {
        Label(feedback.message, systemImage: feedback.kind.symbolName)
            .font(.caption)
            .lineLimit(2)
            .foregroundStyle(feedback.kind.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(feedback.kind.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DetailPanel: View {
    @ObservedObject var model: AppModel
    @State private var mapZoom: CGFloat = 1
    @State private var gestureBaseZoom: CGFloat = 1
    @State private var freeAddressReport: IPAvailabilityReport?

    var body: some View {
        let mapSize = NetworkMapView.preferredSize(
            hosts: model.visibleHosts,
            routerHostIDs: model.routerHostIDs,
            annotations: model.hostAnnotations,
            organization: model.mapOrganization
        )

        VStack(spacing: 14) {
            mapHeader(mapSize: mapSize)

            splitContent(mapSize: mapSize)
                .frame(minHeight: 640)
        }
        .padding(18)
        .sheet(item: $freeAddressReport) { report in
            FreeAddressReportView(
                report: report,
                onAddDHCPRange: { startAddress, endAddress in
                    model.addDHCPRange(startAddress: startAddress, endAddress: endAddress)
                    refreshFreeAddressReport()
                },
                onRemoveDHCPRange: { range in
                    model.removeDHCPRange(range)
                    refreshFreeAddressReport()
                },
                onCopy: model.copyFreeAddressReport,
                onExport: model.exportFreeAddressReport
            )
        }
    }

    private func mapHeader(mapSize: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mapa")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Text(mapHeaderSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            ViewThatFits(in: .horizontal) {
                mapToolbar(mapSize: mapSize)

                ScrollView(.horizontal, showsIndicators: false) {
                    mapToolbar(mapSize: mapSize)
                }
            }
        }
    }

    private var mapHeaderSummary: String {
        if model.hosts.isEmpty {
            return model.segment
        }

        return "\(model.visibleHosts.count)/\(model.hosts.count) equipos"
    }

    private func mapToolbar(mapSize: CGSize) -> some View {
        HStack(spacing: 10) {
            Picker("Organización", selection: $model.mapOrganization) {
                ForEach(NetworkMapOrganization.allCases, id: \.rawValue) { organization in
                    Text(organization.label).tag(organization)
                }
            }
            .labelsHidden()
            .frame(width: 128)

            MapZoomControls(
                zoom: Binding(
                    get: { mapZoom },
                    set: { newValue in
                        mapZoom = newValue
                        gestureBaseZoom = newValue
                    }
                ),
                onReset: resetZoom
            )
            .disabled(model.visibleHosts.isEmpty)

            Spacer(minLength: 0)

            Button {
                presentFreeAddressReport()
            } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Rangos libres", systemImage: "list.bullet.rectangle")
                    Image(systemName: "list.bullet.rectangle")
                }
            }
            .disabled(model.hosts.isEmpty)
            .help("Ver rangos de IP libres")

            Button {
                exportMapImage(mapSize: mapSize)
            } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Exportar PNG", systemImage: "photo")
                    Image(systemName: "photo")
                }
            }
            .disabled(model.hosts.isEmpty)
            .help("Exportar mapa como imagen PNG")

            Button {
                model.copyMermaidMap()
            } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Copiar Mermaid", systemImage: "doc.on.doc")
                    Image(systemName: "doc.on.doc")
                }
            }
            .disabled(model.hosts.isEmpty)
            .help("Copiar Mermaid")
        }
        .controlSize(.regular)
    }

    @ViewBuilder
    private func splitContent(mapSize: CGSize) -> some View {
#if os(macOS)
        VSplitView {
            mapPane(mapSize: mapSize)
                .padding(.bottom, 10)

            detailPane
                .padding(.top, 10)
        }
#else
        VStack(spacing: 12) {
            mapPane(mapSize: mapSize)
                .frame(minHeight: 380)

            detailPane
                .frame(minHeight: 280)
        }
#endif
    }

    @ViewBuilder
    private func mapPane(mapSize: CGSize) -> some View {
        if model.visibleHosts.isEmpty {
            EmptyMapPane(segment: model.segment)
                .frame(minHeight: 420, idealHeight: 560)
                .layoutPriority(1)
        } else {
            GeometryReader { proxy in
                let canvasWidth = max(mapSize.width, proxy.size.width / mapZoom)
                let canvasHeight = max(mapSize.height, proxy.size.height / mapZoom)

                ScrollView([.vertical, .horizontal]) {
                    NetworkMapView(
                        segment: model.segment,
                        hosts: model.visibleHosts,
                        selectedHostID: $model.selectedHostID,
                        routerHostIDs: model.routerHostIDs,
                        defaultInternetHostID: model.defaultInternetHostID,
                        annotations: model.hostAnnotations,
                        refreshStatuses: model.refreshStatuses,
                        organization: model.mapOrganization,
                        onOpen: { host in
                            model.openBestWebPort(for: host)
                        },
                        onMarkRouter: { host in
                            model.markRouter(host)
                        }
                    )
                    .frame(
                        width: canvasWidth,
                        height: canvasHeight
                    )
                    .scaleEffect(mapZoom, anchor: .topLeading)
                    .frame(
                        width: canvasWidth * mapZoom,
                        height: canvasHeight * mapZoom,
                        alignment: .topLeading
                    )
                }
                .background(MapPanelBackground())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }
            .frame(minHeight: 420, idealHeight: 560)
            .layoutPriority(1)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        mapZoom = clampZoom(gestureBaseZoom * value)
                    }
                    .onEnded { _ in
                        gestureBaseZoom = mapZoom
                    }
            )
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if model.hosts.isEmpty {
            EmptyDetailPane()
                .frame(minHeight: 180, idealHeight: 220)
        } else {
            SelectedHostDetail(
                host: model.selectedHost,
                isRouter: model.selectedHostID.map { model.routerHostIDs.contains($0) } ?? false,
                isDefaultInternet: model.selectedHostID == model.defaultInternetHostID,
                annotation: model.selectedHost.map { model.annotation(for: $0) } ?? HostAnnotation(),
                refreshStatus: model.selectedHostID.flatMap { model.refreshStatuses[$0] },
                webURL: model.selectedHost.flatMap(model.bestWebURL),
                onOpen: {
                    if let host = model.selectedHost {
                        model.openBestWebPort(for: host)
                    }
                },
                onMarkRouter: {
                    if let host = model.selectedHost {
                        model.markRouter(host)
                    }
                },
                onClearRouter: {
                    if let host = model.selectedHost {
                        model.clearRouter(host)
                    }
                },
                onMarkDefaultInternet: {
                    if let host = model.selectedHost {
                        model.markDefaultInternet(host)
                    }
                },
                onClearDefaultInternet: model.clearDefaultInternet,
                onAddressAssignmentChange: { assignment in
                    if let host = model.selectedHost {
                        model.setAddressAssignment(assignment, for: host)
                    }
                },
                onSectionChange: { section in
                    if let host = model.selectedHost {
                        model.setSection(section, for: host)
                    }
                }
            )
            .frame(minHeight: 240, idealHeight: 300)
        }
    }

    private func resetZoom() {
        mapZoom = 1
        gestureBaseZoom = 1
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.35), 2.4)
    }

    private func presentFreeAddressReport() {
        refreshFreeAddressReport()
    }

    private func refreshFreeAddressReport() {
        do {
            freeAddressReport = try model.makeFreeAddressReport()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportMapImage(mapSize: CGSize) {
#if os(macOS)
        let exportMapSize = CGSize(
            width: max(1_200, mapSize.width),
            height: max(820, mapSize.height)
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "vada-network-map-\(model.segment.safeFilenameComponent).png"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let pngData = try renderMapPNG(exportMapSize: exportMapSize)
            try pngData.write(to: url, options: .atomic)
        } catch {
            model.errorMessage = error.localizedDescription
        }
#else
        model.errorMessage = "La exportación PNG se implementará con el sistema de compartir de iPad."
#endif
    }

#if os(macOS)
    @MainActor
    private func renderMapPNG(exportMapSize: CGSize) throws -> Data {
        let exportViewSize = CGSize(width: exportMapSize.width, height: exportMapSize.height + 74)
        let renderScale = pngRenderScale(for: exportViewSize)
        let content = NetworkMapExportView(
            segment: model.segment,
            hosts: model.visibleHosts,
            selectedHostID: model.selectedHostID,
            routerHostIDs: model.routerHostIDs,
            defaultInternetHostID: model.defaultInternetHostID,
            annotations: model.hostAnnotations,
            refreshStatuses: model.refreshStatuses,
            organization: model.mapOrganization,
            mapSize: exportMapSize
        )
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(exportViewSize)
        renderer.scale = renderScale
        renderer.isOpaque = true

        if let cgImage = renderer.cgImage {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
        }

        if let image = renderer.nsImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return pngData
        }

        throw MapPNGExportError.renderFailed(size: exportViewSize, scale: renderScale)
    }

    private func pngRenderScale(for size: CGSize) -> CGFloat {
        let preferredScale: CGFloat = 2
        let maximumPixelDimension: CGFloat = 14_000
        let maximumPixelArea: CGFloat = 70_000_000
        let safeWidthScale = maximumPixelDimension / max(1, size.width)
        let safeHeightScale = maximumPixelDimension / max(1, size.height)
        let safeAreaScale = sqrt(maximumPixelArea / max(1, size.width * size.height))
        return max(0.1, min(preferredScale, safeWidthScale, safeHeightScale, safeAreaScale))
    }
#endif
}

#if os(macOS)
private enum MapPNGExportError: LocalizedError {
    case renderFailed(size: CGSize, scale: CGFloat)

    var errorDescription: String? {
        switch self {
        case let .renderFailed(size, scale):
            let pixelWidth = Int((size.width * scale).rounded())
            let pixelHeight = Int((size.height * scale).rounded())
            return "No se pudo renderizar el mapa como imagen (\(pixelWidth)x\(pixelHeight) px)."
        }
    }
}
#endif

private struct MapZoomControls: View {
    @Binding var zoom: CGFloat
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                zoom = max(0.35, zoom - 0.15)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Alejar")

            Slider(value: $zoom, in: 0.35...2.4, step: 0.05)
                .frame(width: 92)

            Button {
                zoom = min(2.4, zoom + 0.15)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Acercar")

            Button {
                onReset()
            } label: {
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            }
            .help("Restablecer zoom")
        }
    }
}

private struct FreeAddressReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var dhcpStartAddress = ""
    @State private var dhcpEndAddress = ""

    let report: IPAvailabilityReport
    let onAddDHCPRange: (String, String) -> Void
    let onRemoveDHCPRange: (DHCPRange) -> Void
    let onCopy: (IPAvailabilityReport) -> Void
    let onExport: (IPAvailabilityReport) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rangos libres")
                        .font(.title2.weight(.semibold))
                    Text(report.segment)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cerrar")
            }

            HStack(spacing: 10) {
                FreeReportMetric(title: "Usables", value: report.usableAddressCount, symbol: "number")
                FreeReportMetric(title: "Ocupadas", value: report.occupiedAddressCount, symbol: "checkmark.circle")
                FreeReportMetric(title: "Estáticas", value: report.staticFreeAddressCount, symbol: "circle")
                FreeReportMetric(title: "DHCP", value: report.dhcpFreeAddressCount, symbol: "arrow.triangle.2.circlepath")
            }

            dhcpConfiguration

            if report.ranges.isEmpty {
                ContentUnavailableView(
                    "Sin IPs libres",
                    systemImage: "checkmark.seal",
                    description: Text("El segmento no tiene direcciones disponibles según el escaneo actual.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedRanges, id: \.subnet) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(group.subnet)
                                        .font(.headline.monospacedDigit())
                                    Spacer()
                                    Text(groupSummary(for: group.ranges))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(group.ranges) { range in
                                    HStack(spacing: 12) {
                                        Text(range.addressLabel)
                                            .font(.callout.monospacedDigit())
                                            .lineLimit(1)
                                        Spacer()
                                        Text(range.kind.label)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(range.kind.tint)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(range.kind.tint.opacity(0.14), in: Capsule())
                                        Text("\(range.count)")
                                            .font(.caption.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(.secondary.opacity(0.12), in: Capsule())
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            .padding(12)
                            .glassPanel(cornerRadius: 14)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Button {
                    onCopy(report)
                } label: {
                    Label("Copiar informe", systemImage: "doc.on.doc")
                }

#if os(macOS)
                Button {
                    onExport(report)
                } label: {
                    Label("Exportar CSV", systemImage: "square.and.arrow.down")
                }
#endif

                Spacer()
            }
        }
        .padding(22)
#if os(macOS)
        .frame(width: 720, height: 640)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }

    private var dhcpConfiguration: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pool DHCP", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                if report.dhcpRanges.isEmpty {
                    Text("Sin configurar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !report.dhcpRanges.isEmpty {
                VStack(spacing: 6) {
                    ForEach(report.dhcpRanges) { range in
                        HStack(spacing: 10) {
                            Text(range.subnetLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 112, alignment: .leading)
                            Text(range.addressLabel)
                                .font(.callout.monospacedDigit())
                            Spacer()
                            Button {
                                onRemoveDHCPRange(range)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Eliminar pool DHCP")
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Inicio DHCP", text: $dhcpStartAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                TextField("Fin DHCP", text: $dhcpEndAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                Button {
                    onAddDHCPRange(dhcpStartAddress, dhcpEndAddress)
                    dhcpStartAddress = ""
                    dhcpEndAddress = ""
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                .disabled(dhcpStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          dhcpEndAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14)
    }

    private var groupedRanges: [(subnet: String, ranges: [FreeAddressRange])] {
        let grouped = Dictionary(grouping: report.ranges, by: \.subnetLabel)
        return grouped.keys.sorted().map { subnet in
            (subnet, grouped[subnet] ?? [])
        }
    }

    private func groupSummary(for ranges: [FreeAddressRange]) -> String {
        let staticCount = ranges
            .filter { $0.kind == .staticCandidate }
            .reduce(0) { $0 + $1.count }
        let dhcpCount = ranges
            .filter { $0.kind == .dhcpPool }
            .reduce(0) { $0 + $1.count }

        if dhcpCount == 0 {
            return "\(staticCount) estáticas"
        }
        if staticCount == 0 {
            return "\(dhcpCount) DHCP"
        }
        return "\(staticCount) estáticas · \(dhcpCount) DHCP"
    }
}

private struct FreeReportMetric: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 14)
    }
}

private extension FreeAddressRangeKind {
    var tint: Color {
        switch self {
        case .staticCandidate: return .green
        case .dhcpPool: return .blue
        }
    }
}

private struct MapPanelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var colors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.975, green: 0.980, blue: 0.984),
                Color(red: 0.950, green: 0.958, blue: 0.966)
            ]
        }

        return [
            Color(red: 0.075, green: 0.085, blue: 0.095),
            Color(red: 0.105, green: 0.115, blue: 0.125)
        ]
    }
}

private struct EmptyMapPane: View {
    @Environment(\.colorScheme) private var colorScheme

    let segment: String

    var body: some View {
        ZStack {
            MapPanelBackground()

            SubtleMapGrid()
                .stroke(.secondary.opacity(colorScheme == .light ? 0.10 : 0.08), lineWidth: 1)

            VStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(segment)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("0 equipos")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
            .frame(width: 280)
            .glassPanel(cornerRadius: 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct EmptyDetailPane: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Sin selección")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .glassPanel(cornerRadius: 18)
    }
}

private struct SubtleMapGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 44

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }

        return path
    }
}

private struct NetworkMapExportView: View {
    let segment: String
    let hosts: [HostDiscovery]
    let selectedHostID: HostDiscovery.ID?
    let routerHostIDs: Set<HostDiscovery.ID>
    let defaultInternetHostID: HostDiscovery.ID?
    let annotations: [HostDiscovery.ID: HostAnnotation]
    let refreshStatuses: [HostDiscovery.ID: HostRefreshStatus]
    let organization: NetworkMapOrganization
    let mapSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            NetworkMapView(
                segment: segment,
                hosts: hosts,
                selectedHostID: .constant(selectedHostID),
                routerHostIDs: routerHostIDs,
                defaultInternetHostID: defaultInternetHostID,
                annotations: annotations,
                refreshStatuses: refreshStatuses,
                organization: organization,
                onOpen: { _ in },
                onMarkRouter: { _ in }
            )
            .frame(width: mapSize.width, height: mapSize.height)

            Divider()

            HStack {
                VaDaBrandFooter()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Mapa de red")
                        .font(.caption.weight(.semibold))
                    Text("\(segment) · \(hosts.count) equipos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white)
        }
        .frame(width: mapSize.width, height: mapSize.height + 74)
        .background(Color.white)
    }
}

private struct SelectedHostDetail: View {
    let host: HostDiscovery?
    let isRouter: Bool
    let isDefaultInternet: Bool
    let annotation: HostAnnotation
    let refreshStatus: HostRefreshStatus?
    let webURL: URL?
    let onOpen: () -> Void
    let onMarkRouter: () -> Void
    let onClearRouter: () -> Void
    let onMarkDefaultInternet: () -> Void
    let onClearDefaultInternet: () -> Void
    let onAddressAssignmentChange: (HostAddressAssignment) -> Void
    let onSectionChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let host {
                HStack {
                    Label(host.ipAddress, systemImage: isRouter ? "network" : host.symbolName)
                        .font(.headline)
                    Spacer()
                    if annotation.isMissing {
                        Label("No visto", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if let refreshStatus {
                        Label(refreshStatus.label, systemImage: refreshStatus.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(refreshStatus.tint)
                    }
                    if isDefaultInternet {
                        Label("Internet", systemImage: "globe")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                    Text(host.systemType)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        onOpen()
                    } label: {
                        Label("Abrir web", systemImage: "safari")
                    }
                    .disabled(webURL == nil)

                    if isRouter {
                        Button {
                            onClearRouter()
                        } label: {
                            Label("Quitar router", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            onMarkRouter()
                        } label: {
                            Label("Marcar router", systemImage: "network")
                        }
                    }

                    if isDefaultInternet {
                        Button {
                            onClearDefaultInternet()
                        } label: {
                            Label("Quitar Internet", systemImage: "wifi.slash")
                        }
                    } else {
                        Button {
                            onMarkDefaultInternet()
                        } label: {
                            Label("Salida Internet", systemImage: "globe")
                        }
                    }
                }

                HStack(spacing: 10) {
                    Picker("IP", selection: Binding(
                        get: { annotation.addressAssignment },
                        set: onAddressAssignmentChange
                    )) {
                        ForEach(HostAddressAssignment.allCases, id: \.rawValue) { assignment in
                            Text(assignment.label).tag(assignment)
                        }
                    }
                    .frame(width: 178)

                    TextField(
                        "Planta o sección",
                        text: Binding(
                            get: { annotation.section },
                            set: onSectionChange
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                if let hostname = host.hostname {
                    Label(hostname, systemImage: "text.badge.checkmark")
                        .foregroundStyle(.secondary)
                }

                if let macAddress = host.macAddress {
                    Label(macAddress, systemImage: "barcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if annotation.isMissing, let lastSeen = annotation.lastSeen {
                    Label("Última vez visto: \(lastSeen.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Puerto")
                            .foregroundStyle(.secondary)
                        Text("Servicio")
                            .foregroundStyle(.secondary)
                        Text("Huella")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(host.openPorts) { port in
                        GridRow {
                            Text("\(port.port)")
                                .monospacedDigit()
                            Text(port.name)
                            Text([port.server, port.title].compactMap { $0 }.joined(separator: " · "))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if host.openPorts.isEmpty {
                    Text("Solo respondió a ping.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Selecciona un equipo", systemImage: "cursorarrow.click")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: 18)
    }
}

private extension HostDiscovery {
    var symbolName: String {
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

    var tintColor: Color {
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
    var safeFilenameComponent: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

private extension ServiceCategory {
    var badgeColor: Color {
        switch self {
        case .remoteAccess: return .green
        case .web: return .blue
        case .industrial: return .orange
        case .fileSharing: return .teal
        case .database: return .purple
        case .messaging: return .mint
        case .media: return .pink
        case .printing: return .indigo
        case .network: return .cyan
        case .unknown: return .secondary
        }
    }
}

private extension OpenPort {
    var badgeColor: Color {
        port == 8090 ? Color(red: 0.05, green: 0.48, blue: 0.36) : (port == 3000 ? .cyan : category.badgeColor)
    }
}

private extension HostActionFeedback.Kind {
    var tint: Color {
        switch self {
        case .opened: return .green
        case .unavailable: return .orange
        case .info: return .blue
        }
    }

    var symbolName: String {
        switch self {
        case .opened: return "safari"
        case .unavailable: return "exclamationmark.circle"
        case .info: return "info.circle"
        }
    }
}

private extension HostRefreshStatus {
    var label: String {
        switch self {
        case .new: return "nuevo"
        case .updated: return "actualizado"
        case .missing: return "no visto"
        }
    }

    var metadataText: String {
        switch self {
        case .new: return "Nuevo en el último refresco"
        case .updated: return "Actualizado en el último refresco"
        case .missing: return "No visto en el último refresco"
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
}
