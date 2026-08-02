#if os(macOS)
import Foundation
import NetworkDiscoveryCore

struct AppRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let pageURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case pageURL = "html_url"
    }
}

enum UpdateNotice: Identifiable {
    case available(release: AppRelease, currentVersion: String)
    case upToDate(currentVersion: String)
    case failed(message: String)

    var id: String {
        switch self {
        case .available(let release, _): return "available-\(release.tagName)"
        case .upToDate(let currentVersion): return "current-\(currentVersion)"
        case .failed: return "failed"
        }
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var isChecking = false
    @Published var notice: UpdateNotice?

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/itilys/vada-smart-house-network-discover-tool/releases/latest"
    )!
    private static let lastCheckKey = "updateChecker.lastAttemptDate"
    private static let automaticCheckInterval: TimeInterval = 7 * 24 * 60 * 60

    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersionText: String?
    private let now: () -> Date

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        currentVersionText: String? = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.defaults = defaults
        self.currentVersionText = currentVersionText
        self.now = now
    }

    func checkIfNeeded() async {
        guard shouldRunAutomaticCheck else { return }
        await check(userInitiated: false)
    }

    func checkNow() async {
        await check(userInitiated: true)
    }

    private var shouldRunAutomaticCheck: Bool {
        guard currentVersionText != nil else { return false }
        guard let lastAttempt = defaults.object(forKey: Self.lastCheckKey) as? Date else {
            return true
        }
        return now().timeIntervalSince(lastAttempt) >= Self.automaticCheckInterval
    }

    private func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        guard let currentVersionText,
              let currentVersion = SemanticVersion(currentVersionText)
        else {
            if userInitiated {
                notice = .failed(message: "No se pudo determinar la versión instalada.")
            }
            return
        }

        isChecking = true
        defaults.set(now(), forKey: Self.lastCheckKey)
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease(currentVersion: currentVersionText)
            guard let latestVersion = SemanticVersion(release.tagName) else {
                throw UpdateCheckError.invalidReleaseVersion
            }

            if latestVersion > currentVersion {
                notice = .available(release: release, currentVersion: currentVersionText)
            } else if userInitiated {
                notice = .upToDate(currentVersion: currentVersionText)
            }
        } catch is CancellationError {
            return
        } catch {
            if userInitiated {
                notice = .failed(message: "No se pudo consultar GitHub. Comprueba tu conexión e inténtalo de nuevo.")
            }
        }
    }

    private func fetchLatestRelease(currentVersion: String) async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("VaDaNetworkDiscover/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw UpdateCheckError.invalidResponse
        }

        return try JSONDecoder().decode(AppRelease.self, from: data)
    }
}

private enum UpdateCheckError: Error {
    case invalidResponse
    case invalidReleaseVersion
}
#endif
