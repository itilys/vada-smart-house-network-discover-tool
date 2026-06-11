import Foundation
import Network

enum TCPProbe {
    static func isOpen(ipAddress: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(ipAddress),
                port: nwPort,
                using: .tcp
            )
            let queue = DispatchQueue(label: "network-discovery.tcp.\(ipAddress).\(port)")
            let completion = TCPProbeCompletion(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion.finish(true)
                case .failed, .cancelled:
                    completion.finish(false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(max(100, Int(timeout * 1000)))) {
                completion.finish(false)
            }
        }
    }
}

private final class TCPProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Bool, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()

        connection.cancel()
        continuation.resume(returning: result)
    }
}
