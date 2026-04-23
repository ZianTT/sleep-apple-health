import Foundation

/// Syncs the current sleep state to the shenghuo2/sleep-status backend.
///
/// Backend API reference: https://github.com/shenghuo2/sleep-status
/// Endpoint: GET /change?key=<key>&status=<1|0>
///   status=1 → sleeping, status=0 → awake
class BackendSyncManager {
    static let shared = BackendSyncManager()

    private let settings = SettingsManager.shared
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Syncs the given sleep state to the backend. Skips the request when the state
    /// is identical to the last successfully synced state (to avoid redundant calls).
    /// - Parameters:
    ///   - isSleeping: `true` when the user is sleeping.
    ///   - force: When `true`, sends the request regardless of cached state.
    ///   - completion: Called on the main queue with the result.
    func syncSleepState(
        isSleeping: Bool,
        force: Bool = false,
        completion: @escaping (Result<Void, SyncError>) -> Void
    ) {
        guard settings.isConfigured else {
            DispatchQueue.main.async { completion(.failure(.notConfigured)) }
            return
        }

        if !force, let lastState = settings.lastSyncedState, lastState == isSleeping {
            DispatchQueue.main.async { completion(.failure(.alreadyInState)) }
            return
        }

        guard let url = buildURL(isSleeping: isSleeping) else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error))) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }

            switch httpResponse.statusCode {
            case 200:
                self.settings.lastSyncedState = isSleeping
                self.settings.lastSyncDate = Date()
                DispatchQueue.main.async { completion(.success(())) }

            case 401:
                DispatchQueue.main.async { completion(.failure(.unauthorized)) }

            default:
                let body = data.flatMap { String(data: $0, encoding: .utf8) }
                DispatchQueue.main.async {
                    completion(.failure(.serverError(httpResponse.statusCode, body)))
                }
            }
        }
        task.resume()
    }

    /// Fetches the current sleep status from the backend.
    func fetchStatus(completion: @escaping (Result<Bool, SyncError>) -> Void) {
        guard settings.isConfigured else {
            DispatchQueue.main.async { completion(.failure(.notConfigured)) }
            return
        }

        var components = URLComponents(string: settings.backendURL)
        components?.path = "/status"

        guard let url = components?.url else {
            DispatchQueue.main.async { completion(.failure(.invalidURL)) }
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(.networkError(error))) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sleep = json["sleep"] as? Bool else {
                DispatchQueue.main.async { completion(.failure(.invalidResponse)) }
                return
            }
            DispatchQueue.main.async { completion(.success(sleep)) }
        }
        task.resume()
    }

    // MARK: - Private helpers

    private func buildURL(isSleeping: Bool) -> URL? {
        var components = URLComponents(string: settings.backendURL)
        components?.path = "/change"
        components?.queryItems = [
            URLQueryItem(name: "key", value: settings.apiKey),
            URLQueryItem(name: "status", value: isSleeping ? "1" : "0")
        ]
        return components?.url
    }

    // MARK: - Error types

    enum SyncError: LocalizedError {
        case notConfigured
        case alreadyInState
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case serverError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .notConfigured:      return "Backend URL and API key are not configured."
            case .alreadyInState:     return "Backend already reflects the current state."
            case .invalidURL:         return "The backend URL is invalid."
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .invalidResponse:    return "Received an unexpected response from the server."
            case .unauthorized:       return "Invalid API key (401 Unauthorized)."
            case .serverError(let code, let body):
                return "Server returned \(code): \(body ?? "no body")"
            }
        }
    }
}
