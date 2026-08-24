import Foundation
import NetworkDiscoveryCore

@main
struct NetDiscoverCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        var parser = ArgumentParser(arguments: Array(CommandLine.arguments.dropFirst()))
        if parser.hasFlag("--help") || parser.hasFlag("-h") || parser.arguments.isEmpty {
            printHelp()
            return
        }

        if parser.arguments.first == "scan" {
            parser.arguments.removeFirst()
        }

        guard let segment = parser.takePositional() else {
            throw CLIError.missingSegment
        }

        let portsText = parser.value(for: "--ports") ?? parser.value(for: "-p") ??
            PortCatalog.defaultPorts.map { String($0.port) }.joined(separator: ",")
        let ports = try PortCatalog.parsePorts(portsText)
        let timeout: TimeInterval
        if let timeoutText = parser.value(for: "--timeout") {
            guard let parsedTimeout = Double(timeoutText),
                  ScanTimeoutPolicy.supportedRange.contains(parsedTimeout)
            else {
                throw CLIError.invalidTimeout(timeoutText)
            }
            timeout = parsedTimeout
        } else {
            timeout = ScanTimeoutPolicy.defaultValue
        }
        let concurrency = Int(parser.value(for: "--concurrency") ?? "") ?? 64
        let includePing = !parser.hasFlag("--no-ping")
        let json = parser.hasFlag("--json")
        let map = parser.hasFlag("--map")

        let configuration = ScanConfiguration(
            segment: segment,
            ports: ports,
            timeout: timeout,
            concurrency: concurrency,
            includePing: includePing
        )

        let scanner = NetworkScanner()
        let hosts = try await scanner.scan(configuration: configuration)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(hosts)
            print(String(decoding: data, as: UTF8.self))
        } else if map {
            print(NetworkMapRenderer.mermaid(segment: segment, hosts: hosts))
        } else {
            printTable(hosts)
        }
    }

    private static func printTable(_ hosts: [HostDiscovery]) {
        if hosts.isEmpty {
            print("No se encontraron equipos.")
            return
        }

        print(row(["IP", "MAC", "DNS", "Tipo", "Ping", "Puertos"], widths: [16, 18, 28, 30, 6, 42]))
        print(String(repeating: "-", count: 146))

        for host in hosts {
            let ports = host.openPorts
                .map { "\($0.port)/\($0.name)" }
                .joined(separator: ", ")
            print(row(
                [
                    host.ipAddress,
                    host.macAddress ?? "-",
                    host.hostname ?? "-",
                    host.systemType,
                    host.pingResponded ? "sí" : "no",
                    ports.isEmpty ? "-" : ports
                ],
                widths: [16, 18, 28, 30, 6, 42]
            ))
        }
    }

    private static func row(_ columns: [String], widths: [Int]) -> String {
        zip(columns, widths)
            .map { value, width in value.truncated(to: width).padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined(separator: "  ")
    }

    private static func printHelp() {
        print(
            """
            Uso:
              swift run netdiscover scan 192.168.1.0/24
              swift run netdiscover scan 192.168.1.1-40 --ports 22,80,443,502 --json
              swift run netdiscover scan 192.168.1.* --map

            Opciones:
              --ports, -p       Puertos TCP separados por coma o rangos. Por defecto: \(PortCatalog.defaultPorts.map { String($0.port) }.joined(separator: ","))
              --timeout         Timeout por prueba entre 1 y 30 segundos. Por defecto: 5
              --concurrency     Hosts en paralelo. Por defecto: 64
              --no-ping         No ejecutar ping ICMP.
              --json            Devuelve los resultados como JSON.
              --map             Devuelve un mapa Mermaid.
            """
        )
    }
}

private struct ArgumentParser {
    var arguments: [String]

    mutating func takePositional() -> String? {
        guard let index = arguments.firstIndex(where: { !$0.hasPrefix("-") }) else {
            return nil
        }
        return arguments.remove(at: index)
    }

    mutating func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        arguments.remove(at: index)
        guard index < arguments.count else {
            return nil
        }
        return arguments.remove(at: index)
    }

    mutating func hasFlag(_ flag: String) -> Bool {
        guard let index = arguments.firstIndex(of: flag) else {
            return false
        }
        arguments.remove(at: index)
        return true
    }
}

private enum CLIError: LocalizedError {
    case missingSegment
    case invalidTimeout(String)

    var errorDescription: String? {
        switch self {
        case .missingSegment:
            return "Falta el segmento de red. Ejemplo: 192.168.1.0/24"
        case .invalidTimeout(let value):
            return "Timeout no válido: \(value). Usa un valor entre 1 y 30 segundos."
        }
    }
}

private extension String {
    func truncated(to width: Int) -> String {
        count <= width ? self : String(prefix(max(0, width - 1))) + "…"
    }
}
