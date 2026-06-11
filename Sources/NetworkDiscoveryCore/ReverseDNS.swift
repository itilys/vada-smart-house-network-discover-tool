import Darwin
import Foundation

enum ReverseDNS {
    static func hostname(for ipAddress: String) async -> String? {
        await Task.detached(priority: .utility) {
            lookup(ipAddress)
        }.value
    }

    private static func lookup(_ ipAddress: String) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)

        guard inet_pton(AF_INET, ipAddress, &address.sin_addr) == 1 else {
            return nil
        }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getnameinfo(
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NAMEREQD
                )
            }
        }

        guard result == 0 else { return nil }
        let name = String(cString: hostname)
        return name == ipAddress ? nil : name
    }
}
