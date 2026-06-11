import Foundation

struct HTTPFingerprint: Hashable, Sendable {
    let server: String?
    let title: String?
}

enum HTTPFingerprintProbe {
    static func fingerprint(ipAddress: String, port: Int, timeout: TimeInterval) async -> HTTPFingerprint? {
        let scheme = PortCatalog.isHTTPS(port) ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(ipAddress):\(port)/") else {
            return nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = max(0.3, timeout)
        configuration.timeoutIntervalForResource = max(0.3, timeout)
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let delegate = PermissiveHTTPSDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("VaDaNetworkDiscover/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            let server = httpResponse.value(forHTTPHeaderField: "Server")
            let html = String(decoding: data.prefix(64_000), as: UTF8.self)
            return HTTPFingerprint(
                server: server?.nilIfBlank,
                title: extractTitle(from: html)
            )
        } catch {
            return nil
        }
    }

    private static func extractTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let titleRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return html[titleRange]
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}

private final class PermissiveHTTPSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
