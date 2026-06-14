import Foundation

// Keep per-host TCP pressure low; embedded/industrial devices often drop bursts.
private let maximumPortWorkersPerHost = 4

public struct NetworkScanner: Sendable {
    public init() {}

    public func scan(
        configuration: ScanConfiguration,
        progress: ((ScanProgress) async -> Void)? = nil,
        hostDiscovered: ((HostDiscovery) async -> Void)? = nil
    ) async throws -> [HostDiscovery] {
        let network = try IPv4Network(configuration.segment)
        let ipAddresses = try network.hosts(maximumHosts: configuration.maximumHosts)
        let totalHosts = ipAddresses.count
        var iterator = ipAddresses.makeIterator()
        var completedHosts = 0
        var results: [HostDiscovery] = []

        let workers = max(1, min(configuration.concurrency, totalHosts))

        try await withThrowingTaskGroup(of: HostDiscovery?.self) { group in
            for _ in 0..<workers {
                guard let ipAddress = iterator.next() else { break }
                group.addTask {
                    try Task.checkCancellation()
                    return await scanHost(ipAddress: ipAddress, configuration: configuration)
                }
            }

            while let host = try await group.next() {
                completedHosts += 1

                if let host {
                    results.append(host)
                    if let hostDiscovered {
                        await hostDiscovered(host)
                    }
                }

                if let progress {
                    await progress(ScanProgress(completedHosts: completedHosts, totalHosts: totalHosts))
                }

                if let nextAddress = iterator.next() {
                    group.addTask {
                        try Task.checkCancellation()
                        return await scanHost(ipAddress: nextAddress, configuration: configuration)
                    }
                }
            }
        }

        return results.sorted {
            IPv4Address.sortKey(for: $0.ipAddress) < IPv4Address.sortKey(for: $1.ipAddress)
        }
    }
}

private func scanHost(ipAddress: String, configuration: ScanConfiguration) async -> HostDiscovery? {
    async let pingResponded = configuration.includePing
        ? PingProbe.ping(ipAddress: ipAddress, timeout: configuration.timeout)
        : false
    async let hostname = ReverseDNS.hostname(for: ipAddress)
    let openPorts = await scanPorts(
        ipAddress: ipAddress,
        ports: configuration.ports,
        timeout: configuration.timeout
    )

    let didPingRespond = await pingResponded
    let resolvedHostname = await hostname

    guard didPingRespond || !openPorts.isEmpty else {
        return nil
    }

    let macAddress = await MACAddressProbe.macAddress(for: ipAddress)

    return HostDiscovery(
        ipAddress: ipAddress,
        hostname: resolvedHostname,
        macAddress: macAddress,
        pingResponded: didPingRespond,
        systemType: SystemClassifier.classify(
            hostname: resolvedHostname,
            openPorts: openPorts,
            pingResponded: didPingRespond
        ),
        openPorts: openPorts.sorted { $0.port < $1.port }
    )
}

private func scanPorts(ipAddress: String, ports: [Int], timeout: TimeInterval) async -> [OpenPort] {
    await withTaskGroup(of: OpenPort?.self) { group in
        var iterator = ports.makeIterator()
        let workers = min(maximumPortWorkersPerHost, ports.count)

        for _ in 0..<workers {
            guard let port = iterator.next() else { break }
            group.addTask {
                await scanPort(ipAddress: ipAddress, port: port, timeout: timeout)
            }
        }

        var openPorts: [OpenPort] = []
        for await port in group {
            if let port {
                openPorts.append(port)
            }

            if let nextPort = iterator.next() {
                group.addTask {
                    await scanPort(ipAddress: ipAddress, port: nextPort, timeout: timeout)
                }
            }
        }

        return openPorts
    }
}

private func scanPort(ipAddress: String, port: Int, timeout: TimeInterval) async -> OpenPort? {
    guard await TCPProbe.isOpen(ipAddress: ipAddress, port: port, timeout: timeout) else {
        return nil
    }

    let definition = PortCatalog.definition(for: port)
    var openPort = OpenPort(
        port: definition.port,
        name: definition.name,
        category: definition.category
    )

    if PortCatalog.isHTTP(port) || PortCatalog.isHTTPS(port) {
        let fingerprint = await HTTPFingerprintProbe.fingerprint(
            ipAddress: ipAddress,
            port: port,
            timeout: max(timeout, 1.2)
        )
        openPort.server = fingerprint?.server
        openPort.title = fingerprint?.title
    }

    return openPort
}
