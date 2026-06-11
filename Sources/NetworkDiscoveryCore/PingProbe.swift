import Foundation

enum PingProbe {
    static func ping(ipAddress: String, timeout: TimeInterval) async -> Bool {
#if os(macOS)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = [
                    "-c", "1",
                    "-W", "\(max(200, Int(timeout * 1000)))",
                    ipAddress
                ]
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }

                let deadline = Date().addingTimeInterval(timeout + 0.4)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }

                if process.isRunning {
                    process.terminate()
                }
                process.waitUntilExit()

                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
#else
        false
#endif
    }
}
