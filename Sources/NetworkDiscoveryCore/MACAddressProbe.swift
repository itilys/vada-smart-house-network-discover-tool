import Foundation

enum MACAddressProbe {
    static func macAddress(for ipAddress: String, timeout: TimeInterval = 0.35) async -> String? {
#if os(macOS)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                process.arguments = ["-n", ipAddress]
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }

                if process.isRunning {
                    process.terminate()
                }
                process.waitUntilExit()

                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let text = [
                    String(data: output, encoding: .utf8),
                    String(data: errorOutput, encoding: .utf8)
                ]
                .compactMap { $0 }
                .joined(separator: "\n")

                continuation.resume(returning: parseMACAddress(from: text))
            }
        }
#else
        nil
#endif
    }

#if os(macOS)
    private static func parseMACAddress(from text: String) -> String? {
        let pattern = #"(?i)\bat\s+(([0-9a-f]{1,2}:){5}[0-9a-f]{1,2})\b"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let parts = text[range].split(separator: ":").compactMap { Int($0, radix: 16) }
        guard parts.count == 6 else { return nil }
        return parts
            .map { String(format: "%02x", $0) }
            .joined(separator: ":")
    }
#endif
}
