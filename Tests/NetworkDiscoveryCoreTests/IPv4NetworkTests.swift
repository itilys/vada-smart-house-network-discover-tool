import XCTest
@testable import NetworkDiscoveryCore

final class IPv4NetworkTests: XCTestCase {
    func testCIDRExcludesNetworkAndBroadcastForSlashThirty() throws {
        let network = try IPv4Network("192.168.1.0/30")
        XCTAssertEqual(try network.hosts(), ["192.168.1.1", "192.168.1.2"])
    }

    func testSingleHostCIDRIncludesHost() throws {
        let network = try IPv4Network("10.0.0.8/32")
        XCTAssertEqual(try network.hosts(), ["10.0.0.8"])
    }

    func testWildcardSegmentExpandsUsableRange() throws {
        let network = try IPv4Network("172.16.4.*")
        let hosts = try network.hosts()
        XCTAssertEqual(hosts.first, "172.16.4.1")
        XCTAssertEqual(hosts.last, "172.16.4.254")
        XCTAssertEqual(hosts.count, 254)
    }

    func testLastOctetRange() throws {
        let network = try IPv4Network("192.168.7.20-22")
        XCTAssertEqual(try network.hosts(), ["192.168.7.20", "192.168.7.21", "192.168.7.22"])
    }

    func testPortParsingSupportsRangesAndDeduplication() throws {
        XCTAssertEqual(try PortCatalog.parsePorts("22,80,80,500-502"), [22, 80, 500, 501, 502])
    }

    func testSemanticVersionParsesTagsAndComparesNumerically() throws {
        let current = try XCTUnwrap(SemanticVersion("0.1.9"))
        let update = try XCTUnwrap(SemanticVersion("v0.1.10"))
        let majorUpdate = try XCTUnwrap(SemanticVersion("1.0"))

        XCTAssertLessThan(current, update)
        XCTAssertLessThan(update, majorUpdate)
        XCTAssertEqual(SemanticVersion("V1.2.3"), SemanticVersion("1.2.3"))
        XCTAssertNil(SemanticVersion("release-latest"))
    }

    func testIPAvailabilityReportBuildsFreeRanges() throws {
        let report = try IPAvailabilityReport.build(
            segment: "192.168.1.0/29",
            occupiedIPAddresses: [
                "192.168.1.1",
                "192.168.1.3",
                "192.168.1.6"
            ]
        )

        XCTAssertEqual(report.usableAddressCount, 6)
        XCTAssertEqual(report.occupiedAddressCount, 3)
        XCTAssertEqual(report.freeAddressCount, 3)
        XCTAssertEqual(report.ranges.map(\.addressLabel), [
            "192.168.1.2",
            "192.168.1.4 - 192.168.1.5"
        ])
        XCTAssertTrue(report.plainText.contains("192.168.1.4 - 192.168.1.5"))
        XCTAssertTrue(report.csvText.contains("192.168.1.0/24,192.168.1.4,192.168.1.5,2"))
    }

    func testIPAvailabilityReportMarksFreeAddressesInsideDHCPPool() throws {
        let report = try IPAvailabilityReport.build(
            segment: "192.168.1.0/29",
            occupiedIPAddresses: ["192.168.1.1"],
            dhcpRanges: [
                DHCPRange(startAddress: "192.168.1.4", endAddress: "192.168.1.5")
            ]
        )

        XCTAssertEqual(report.staticFreeAddressCount, 3)
        XCTAssertEqual(report.dhcpFreeAddressCount, 2)
        XCTAssertEqual(report.ranges.map(\.kind), [
            .staticCandidate,
            .dhcpPool,
            .staticCandidate
        ])
        XCTAssertTrue(report.plainText.contains("Libres DHCP: 2"))
        XCTAssertTrue(report.csvText.contains("192.168.1.0/24,192.168.1.4,192.168.1.5,2,DHCP"))
    }

    func testIPAvailabilityReportSplitsLargeSegmentsBySubnet() throws {
        let report = try IPAvailabilityReport.build(
            segment: "192.168.0.0/23",
            occupiedIPAddresses: [
                "192.168.0.1",
                "192.168.1.254"
            ]
        )

        XCTAssertEqual(report.ranges.first?.addressLabel, "192.168.0.2 - 192.168.0.254")
        XCTAssertEqual(report.ranges.last?.addressLabel, "192.168.1.1 - 192.168.1.253")
        XCTAssertEqual(Set(report.ranges.map(\.subnetLabel)), [
            "192.168.0.0/24",
            "192.168.1.0/24"
        ])
    }

    func testVaDaSolarPortIsCataloguedAsHTTPDeviceSignal() {
        let definition = PortCatalog.definition(for: 8090)
        let host = HostDiscovery(
            ipAddress: "192.168.1.90",
            hostname: "solarbrain.local",
            pingResponded: false,
            systemType: SystemClassifier.classify(
                hostname: "solarbrain.local",
                openPorts: [
                    OpenPort(port: definition.port, name: definition.name, category: definition.category)
                ],
                pingResponded: false
            ),
            openPorts: []
        )

        XCTAssertTrue(PortCatalog.defaultPorts.contains { $0.port == 8090 })
        XCTAssertTrue(PortCatalog.isHTTP(8090))
        XCTAssertEqual(definition.name, "VaDa Solar")
        XCTAssertEqual(host.systemType, "VaDa SolarBrain / SolarGenius")
    }

    func testSolarBrandFingerprintsOutrankGenericModbusClassification() {
        let modbus = PortCatalog.definition(for: 502)
        let http = PortCatalog.definition(for: 80)

        let froniusType = SystemClassifier.classify(
            hostname: nil,
            openPorts: [
                OpenPort(port: http.port, name: http.name, category: http.category, title: "webserver - Fronius"),
                OpenPort(port: modbus.port, name: modbus.name, category: modbus.category)
            ],
            pingResponded: false
        )
        let victronType = SystemClassifier.classify(
            hostname: nil,
            openPorts: [
                OpenPort(port: http.port, name: http.name, category: http.category, server: "nginx - Victron GUIv2"),
                OpenPort(port: modbus.port, name: modbus.name, category: modbus.category)
            ],
            pingResponded: false
        )

        XCTAssertEqual(froniusType, "Fronius / solar")
        XCTAssertEqual(victronType, "Victron / solar")
    }

    func testAirzonePortIsCataloguedAsHTTPAndClassifiedFromFingerprint() {
        let definition = PortCatalog.definition(for: 3000)
        let systemType = SystemClassifier.classify(
            hostname: nil,
            openPorts: [
                OpenPort(port: definition.port, name: definition.name, category: definition.category, server: "Airzone-Webserver")
            ],
            pingResponded: false
        )

        XCTAssertTrue(PortCatalog.defaultPorts.contains { $0.port == 3000 })
        XCTAssertTrue(PortCatalog.isHTTP(3000))
        XCTAssertEqual(definition.name, "Airzone HTTP")
        XCTAssertEqual(systemType, "Airzone / climatización")
    }

    func testMermaidMapUsesReadableLineBreaks() {
        let host = HostDiscovery(
            ipAddress: "127.0.0.1",
            hostname: "localhost",
            pingResponded: true,
            systemType: "Equipo con ping",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(segment: "127.0.0.1", hosts: [host])
        XCTAssertTrue(map.contains("127.0.0.1<br/>localhost<br/>Equipo con ping"))
    }

    func testMermaidMapRoutesThroughMarkedRouter() {
        let router = HostDiscovery(
            ipAddress: "192.168.1.1",
            hostname: "router.local",
            pingResponded: true,
            systemType: "Router / gateway",
            openPorts: []
        )
        let host = HostDiscovery(
            ipAddress: "192.168.1.20",
            hostname: nil,
            pingResponded: true,
            systemType: "Equipo con ping",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(
            segment: "192.168.1.0/24",
            hosts: [router, host],
            routerHostID: router.id
        )

        XCTAssertTrue(map.contains("network --> host_192_168_1_1"))
        XCTAssertTrue(map.contains("host_192_168_1_1 --> host_192_168_1_20"))
        XCTAssertTrue(map.contains("router.local<br/>Router<br/>Router / gateway"))
    }

    func testMermaidMapCanGroupByAddressAssignment() {
        let router = HostDiscovery(
            ipAddress: "192.168.1.1",
            hostname: "router.local",
            pingResponded: true,
            systemType: "Router / gateway",
            openPorts: []
        )
        let staticHost = HostDiscovery(
            ipAddress: "192.168.1.20",
            hostname: "camera.local",
            pingResponded: true,
            systemType: "Cámara IP / vídeo",
            openPorts: []
        )
        let dynamicHost = HostDiscovery(
            ipAddress: "192.168.1.51",
            hostname: nil,
            pingResponded: true,
            systemType: "Equipo con ping",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(
            segment: "192.168.1.0/24",
            hosts: [router, staticHost, dynamicHost],
            routerHostID: router.id,
            annotations: [
                staticHost.id: HostAnnotation(addressAssignment: .staticAddress, section: "Planta 1"),
                dynamicHost.id: HostAnnotation(addressAssignment: .dynamicAddress, section: "Planta 2")
            ],
            organization: .addressAssignment
        )

        XCTAssertTrue(map.contains("IP estática"))
        XCTAssertTrue(map.contains("IP dinámica"))
        XCTAssertTrue(map.contains("camera.local<br/>Cámara IP / vídeo<br/>IP estática<br/>Planta 1"))
    }

    func testMermaidMapCanGroupBySystemType() {
        let camera = HostDiscovery(
            ipAddress: "192.168.1.20",
            hostname: "camera.local",
            pingResponded: true,
            systemType: "Cámara IP / vídeo",
            openPorts: []
        )
        let controller = HostDiscovery(
            ipAddress: "192.168.1.30",
            hostname: "solar-controller.local",
            pingResponded: true,
            systemType: "Fronius / solar",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(
            segment: "192.168.1.0/24",
            hosts: [camera, controller],
            organization: .systemType
        )

        XCTAssertTrue(map.contains("network --> group_Cámara_IP___vídeo[\"Cámara IP / vídeo\"]"))
        XCTAssertTrue(map.contains("group_Cámara_IP___vídeo --> host_192_168_1_20"))
        XCTAssertTrue(map.contains("network --> group_Fronius___solar[\"Fronius / solar\"]"))
        XCTAssertTrue(map.contains("group_Fronius___solar --> host_192_168_1_30"))
    }

    func testMermaidMapCanUseMultipleRoutersAndSubnetGroups() {
        let externalRouter = HostDiscovery(
            ipAddress: "192.168.0.1",
            hostname: "wan-router",
            pingResponded: true,
            systemType: "Router / gateway",
            openPorts: []
        )
        let internalRouter = HostDiscovery(
            ipAddress: "192.168.1.254",
            hostname: "velop4400",
            pingResponded: true,
            systemType: "Router / gateway",
            openPorts: []
        )
        let externalHost = HostDiscovery(
            ipAddress: "192.168.0.10",
            hostname: "dmz.local",
            pingResponded: true,
            systemType: "Servicio web / dispositivo",
            openPorts: []
        )
        let internalHost = HostDiscovery(
            ipAddress: "192.168.1.30",
            hostname: "iot.local",
            pingResponded: true,
            systemType: "IoT / broker MQTT",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(
            segment: "192.168.0.0/23",
            hosts: [externalRouter, internalRouter, externalHost, internalHost],
            routerHostIDs: [externalRouter.id, internalRouter.id],
            defaultInternetHostID: externalRouter.id,
            organization: .subnet
        )

        XCTAssertTrue(map.contains("network --> host_192_168_0_1"))
        XCTAssertTrue(map.contains("network --> host_192_168_1_254"))
        XCTAssertTrue(map.contains("Salida Internet"))
        XCTAssertTrue(map.contains("host_192_168_0_1 --> group_192_168_0_0_24"))
        XCTAssertTrue(map.contains("host_192_168_1_254 --> group_192_168_1_0_24"))
        XCTAssertTrue(map.contains("group_192_168_0_0_24 --> host_192_168_0_10"))
        XCTAssertTrue(map.contains("group_192_168_1_0_24 --> host_192_168_1_30"))
    }

    func testMermaidMapUsesNotDetectedLabelForMissingHost() {
        let host = HostDiscovery(
            ipAddress: "192.168.1.20",
            hostname: "device.local",
            pingResponded: true,
            systemType: "Equipo con ping",
            openPorts: []
        )

        let map = NetworkMapRenderer.mermaid(
            segment: "192.168.1.0/24",
            hosts: [host],
            annotations: [host.id: HostAnnotation(isMissing: true)]
        )

        XCTAssertTrue(map.contains("No detectado"))
        XCTAssertFalse(map.contains("No visto"))
    }

    func testSavedScanRoundTripsConfigurationAndRouter() throws {
        let document = SavedScan(
            configuration: ScanConfiguration(
                segment: "10.0.0.0/30",
                ports: [22, 80, 502],
                timeout: 0.5,
                concurrency: 8,
                includePing: true
            ),
            hosts: [
                HostDiscovery(
                    ipAddress: "10.0.0.1",
                    hostname: "router.local",
                    macAddress: "aa:bb:cc:dd:ee:ff",
                    pingResponded: true,
                    systemType: "Router / gateway",
                    openPorts: []
                )
            ],
            routerHostID: "10.0.0.1",
            routerHostIDs: ["10.0.0.1", "10.0.0.2"],
            defaultInternetHostID: "10.0.0.1",
            dhcpRanges: [
                DHCPRange(startAddress: "10.0.0.10", endAddress: "10.0.0.20")
            ],
            annotations: [
                "10.0.0.1": HostAnnotation(
                    addressAssignment: .dhcpReservation,
                    section: "Rack comunicaciones",
                    isMissing: true,
                    lastSeen: Date(timeIntervalSince1970: 42)
                )
            ],
            mapOrganization: .systemType,
            refreshComparison: RefreshComparison(
                completedAt: Date(timeIntervalSince1970: 84),
                statuses: ["10.0.0.1": .missing]
            )
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SavedScan.self, from: data)

        XCTAssertEqual(decoded.configuration.segment, "10.0.0.0/30")
        XCTAssertEqual(decoded.configuration.ports, [22, 80, 502])
        XCTAssertEqual(decoded.routerHostID, "10.0.0.1")
        XCTAssertEqual(decoded.routerHostIDs, ["10.0.0.1", "10.0.0.2"])
        XCTAssertEqual(decoded.defaultInternetHostID, "10.0.0.1")
        XCTAssertEqual(decoded.dhcpRanges.first?.addressLabel, "10.0.0.10 - 10.0.0.20")
        XCTAssertEqual(decoded.hosts.first?.hostname, "router.local")
        XCTAssertEqual(decoded.hosts.first?.macAddress, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(decoded.annotations["10.0.0.1"]?.addressAssignment, .dhcpReservation)
        XCTAssertEqual(decoded.annotations["10.0.0.1"]?.section, "Rack comunicaciones")
        XCTAssertEqual(decoded.annotations["10.0.0.1"]?.isMissing, true)
        XCTAssertEqual(decoded.annotations["10.0.0.1"]?.lastSeen, Date(timeIntervalSince1970: 42))
        XCTAssertEqual(decoded.mapOrganization, .systemType)
        XCTAssertEqual(decoded.schemaVersion, 7)
        XCTAssertEqual(decoded.refreshComparison?.completedAt, Date(timeIntervalSince1970: 84))
        XCTAssertEqual(decoded.refreshComparison?.statuses["10.0.0.1"], .missing)
    }

    func testSavedScanDecodesLegacyDocumentWithoutRefreshMetadata() throws {
        let data = Data(
            """
            {
              "annotations": {
                "192.168.1.241": {
                  "addressAssignment": "staticAddress",
                  "section": "Camaras"
                }
              },
              "configuration": {
                "concurrency": 64,
                "includePing": true,
                "maximumHosts": 4096,
                "ports": [22, 80, 443, 502],
                "segment": "192.168.1.0/24",
                "timeout": 3
              },
              "hosts": [
                {
                  "discoveredAt": "2026-06-03T21:58:29Z",
                  "hostname": "camara.local",
                  "ipAddress": "192.168.1.241",
                  "openPorts": [],
                  "pingResponded": true,
                  "systemType": "Cámara IP / vídeo"
                }
              ],
              "mapOrganization": "section",
              "routerHostID": null,
              "savedAt": "2026-06-03T21:59:00Z",
              "schemaVersion": 2
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedScan.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertNil(decoded.hosts.first?.macAddress)
        XCTAssertEqual(decoded.routerHostIDs, [])
        XCTAssertNil(decoded.defaultInternetHostID)
        XCTAssertEqual(decoded.dhcpRanges, [])
        XCTAssertEqual(decoded.annotations["192.168.1.241"]?.addressAssignment, .staticAddress)
        XCTAssertEqual(decoded.annotations["192.168.1.241"]?.section, "Camaras")
        XCTAssertEqual(decoded.annotations["192.168.1.241"]?.isMissing, false)
        XCTAssertNil(decoded.annotations["192.168.1.241"]?.lastSeen)
        XCTAssertNil(decoded.refreshComparison)
    }

    func testRefreshComparisonCountsEveryStatus() {
        let comparison = RefreshComparison(
            completedAt: Date(timeIntervalSince1970: 100),
            statuses: [
                "192.168.1.10": .new,
                "192.168.1.20": .updated,
                "192.168.1.30": .unchanged,
                "192.168.1.40": .unchanged,
                "192.168.1.50": .missing
            ]
        )

        XCTAssertEqual(comparison.count(for: .new), 1)
        XCTAssertEqual(comparison.count(for: .updated), 1)
        XCTAssertEqual(comparison.count(for: .unchanged), 2)
        XCTAssertEqual(comparison.count(for: .missing), 1)
    }

    func testRefreshFiltersSeparateChangesAndPresentHosts() {
        XCTAssertTrue(HostRefreshFilter.changes.includes(.new))
        XCTAssertTrue(HostRefreshFilter.changes.includes(.updated))
        XCTAssertTrue(HostRefreshFilter.changes.includes(.missing))
        XCTAssertFalse(HostRefreshFilter.changes.includes(.unchanged))

        XCTAssertTrue(HostRefreshFilter.present.includes(.new))
        XCTAssertTrue(HostRefreshFilter.present.includes(.updated))
        XCTAssertTrue(HostRefreshFilter.present.includes(.unchanged))
        XCTAssertFalse(HostRefreshFilter.present.includes(.missing))
        XCTAssertTrue(HostRefreshFilter.all.includes(nil))
        XCTAssertFalse(HostRefreshFilter.new.includes(nil))
    }
}
