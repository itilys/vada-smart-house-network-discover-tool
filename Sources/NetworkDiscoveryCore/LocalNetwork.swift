import Darwin
import Foundation

public enum LocalNetwork {
    public static func suggestedCIDR() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = interface.ifa_netmask
            else {
                continue
            }

            let ip = sockaddrToIPv4(address)
            let mask = sockaddrToIPv4(netmask)
            guard mask != 0 else { continue }

            let network = ip & mask
            let prefix = mask.nonzeroBitCount
            return "\(IPv4Address.string(from: network))/\(prefix)"
        }

        return nil
    }

    private static func sockaddrToIPv4(_ sockaddrPointer: UnsafePointer<sockaddr>) -> UInt32 {
        let address = sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr.s_addr
        }
        return UInt32(bigEndian: address)
    }
}
