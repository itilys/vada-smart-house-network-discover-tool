import Foundation

enum SystemClassifier {
    static func classify(hostname: String?, openPorts: [OpenPort], pingResponded: Bool) -> String {
        let ports = Set(openPorts.map(\.port))
        let evidence = ([hostname] + openPorts.flatMap { [$0.server, $0.title] })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if ports.contains(8090) || evidence.contains("solarbrain") || evidence.contains("solargenius") || evidence.contains("vada") {
            return "VaDa SolarBrain / SolarGenius"
        }
        if ports.contains(502) {
            return "PLC / equipo industrial"
        }
        if ports.contains(9100) {
            return "Impresora / equipo de oficina"
        }
        if ports.contains(554) || evidence.contains("rtsp") || evidence.contains("camera") || evidence.contains("camara") {
            return "Cámara IP / vídeo"
        }
        if ports.contains(1883) {
            return "IoT / broker MQTT"
        }
        if ports.contains(3389) {
            return "Windows / RDP"
        }
        if ports.contains(445) || ports.contains(139) {
            return evidence.contains("nas") ? "NAS / almacenamiento" : "Windows/Samba"
        }
        if evidence.contains("router") || evidence.contains("openwrt") || evidence.contains("mikrotik") {
            return "Router / gateway"
        }
        if evidence.contains("synology") || evidence.contains("qnap") {
            return "NAS / almacenamiento"
        }
        if hasAny(ports, [3306, 5432]) {
            return "Servidor de base de datos"
        }
        if ports.contains(22), hasAny(ports, [80, 443, 8080, 8443]) {
            return "Appliance Linux / red"
        }
        if ports.contains(22) {
            return "Linux/Unix o equipo administrable"
        }
        if hasAny(ports, [80, 443, 8080, 8443]) {
            return "Servicio web / dispositivo"
        }
        if pingResponded {
            return "Equipo con ping"
        }
        return "Equipo de red"
    }

    private static func hasAny(_ ports: Set<Int>, _ candidates: [Int]) -> Bool {
        candidates.contains { ports.contains($0) }
    }
}
