import Foundation

/// Manages user-configurable settings stored in UserDefaults.
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let backendURL = "backendURL"
        static let apiKey = "apiKey"
        static let lastSyncedState = "lastSyncedState"
        static let lastSyncDate = "lastSyncDate"
    }

    @Published var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: Keys.backendURL) }
    }

    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    /// The last sleep state successfully synced to the backend. nil means never synced.
    var lastSyncedState: Bool? {
        get {
            guard UserDefaults.standard.object(forKey: Keys.lastSyncedState) != nil else { return nil }
            return UserDefaults.standard.bool(forKey: Keys.lastSyncedState)
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: Keys.lastSyncedState)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastSyncedState)
            }
        }
    }

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastSyncDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastSyncDate) }
    }

    var isConfigured: Bool {
        !backendURL.isEmpty && !apiKey.isEmpty
    }

    private init() {
        backendURL = UserDefaults.standard.string(forKey: Keys.backendURL) ?? ""
        apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
    }
}
