import Foundation

public enum PortCatalog {
    public static let defaultPorts: [PortDefinition] = [
        PortDefinition(port: 22, name: "SSH", category: .remoteAccess),
        PortDefinition(port: 80, name: "HTTP", category: .web),
        PortDefinition(port: 443, name: "HTTPS", category: .web),
        PortDefinition(port: 502, name: "Modbus TCP", category: .industrial),
        PortDefinition(port: 8080, name: "HTTP alt", category: .web),
        PortDefinition(port: 8090, name: "VaDa Solar", category: .industrial),
        PortDefinition(port: 8443, name: "HTTPS alt", category: .web),
        PortDefinition(port: 21, name: "FTP", category: .remoteAccess),
        PortDefinition(port: 23, name: "Telnet", category: .remoteAccess),
        PortDefinition(port: 53, name: "DNS TCP", category: .network),
        PortDefinition(port: 139, name: "NetBIOS", category: .fileSharing),
        PortDefinition(port: 445, name: "SMB", category: .fileSharing),
        PortDefinition(port: 554, name: "RTSP", category: .media),
        PortDefinition(port: 1883, name: "MQTT", category: .messaging),
        PortDefinition(port: 3000, name: "Airzone HTTP", category: .web),
        PortDefinition(port: 3306, name: "MySQL", category: .database),
        PortDefinition(port: 5432, name: "PostgreSQL", category: .database),
        PortDefinition(port: 5900, name: "VNC", category: .remoteAccess),
        PortDefinition(port: 3389, name: "RDP", category: .remoteAccess),
        PortDefinition(port: 9100, name: "Impresora", category: .printing)
    ]

    public static func definition(for port: Int) -> PortDefinition {
        defaultPorts.first(where: { $0.port == port }) ??
            PortDefinition(port: port, name: "TCP \(port)", category: .unknown)
    }

    public static func isHTTP(_ port: Int) -> Bool {
        [80, 3000, 8080, 8090, 8000, 8888].contains(port)
    }

    public static func isHTTPS(_ port: Int) -> Bool {
        [443, 8443, 9443].contains(port)
    }

    public static func parsePorts(_ text: String) throws -> [Int] {
        let normalized = text
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: " ", with: ",")
            .replacingOccurrences(of: "\n", with: ",")

        var ports: [Int] = []
        for rawToken in normalized.split(separator: ",") {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            if token.contains("-") {
                let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
                guard bounds.count == 2,
                      let lower = Int(bounds[0]),
                      let upper = Int(bounds[1]),
                      lower <= upper
                else {
                    throw PortParseError.invalidRange(token)
                }

                for port in lower...upper {
                    try validate(port)
                    ports.append(port)
                }
            } else if let port = Int(token) {
                try validate(port)
                ports.append(port)
            } else {
                throw PortParseError.invalidToken(token)
            }
        }

        var seen = Set<Int>()
        let unique = ports.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { throw PortParseError.empty }
        return unique
    }

    private static func validate(_ port: Int) throws {
        guard (1...65_535).contains(port) else {
            throw PortParseError.outOfRange(port)
        }
    }
}

public enum PortParseError: LocalizedError, Equatable {
    case empty
    case invalidToken(String)
    case invalidRange(String)
    case outOfRange(Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Introduce al menos un puerto TCP."
        case .invalidToken(let token):
            return "Puerto no válido: \(token)."
        case .invalidRange(let range):
            return "Rango de puertos no válido: \(range)."
        case .outOfRange(let port):
            return "El puerto \(port) está fuera del rango 1...65535."
        }
    }
}
