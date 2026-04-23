import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var urlDraft: String = ""
    @State private var keyDraft: String = ""
    @State private var isTestingConnection = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(Bool)  // Bool = current backend sleep state
        case failure(String)
    }

    var body: some View {
        NavigationView {
            Form {
                // --- Backend configuration ---
                Section {
                    TextField("https://your-server:8000", text: $urlDraft)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                } header: {
                    Text("Backend URL")
                } footer: {
                    Text("The base URL of your sleep-status server (no trailing slash).")
                }

                Section {
                    SecureField("API Key", text: $keyDraft)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("The key from your server's config.json.")
                }

                // --- Test connection ---
                Section {
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingConnection ? "Testing…" : "Test Connection")
                        }
                    }
                    .disabled(isTestingConnection || urlDraft.isEmpty || keyDraft.isEmpty)

                    if let result = testResult {
                        testResultView(result)
                    }
                }

                // --- About ---
                Section("About") {
                    LabeledContent("Backend project") {
                        Link("shenghuo2/sleep-status",
                             destination: URL(string: "https://github.com/shenghuo2/sleep-status")!)
                    }
                    LabeledContent("Sleep sync interval", value: "On HealthKit change + every ~15 min")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(urlDraft.isEmpty || keyDraft.isEmpty)
                }
            }
            .onAppear {
                urlDraft = settings.backendURL
                keyDraft = settings.apiKey
            }
        }
    }

    // MARK: - Test result view

    @ViewBuilder
    private func testResultView(_ result: TestResult) -> some View {
        switch result {
        case .success(let sleeping):
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Connected! Backend status: \(sleeping ? "sleeping 🌙" : "awake ☀️")")
                    .font(.subheadline)
            }
        case .failure(let msg):
            HStack(alignment: .top) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                Text(msg).font(.subheadline)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        settings.backendURL = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reset last synced state so the next sync will always send a fresh request.
        settings.lastSyncedState = nil
        dismiss()
    }

    private func testConnection() {
        // Temporarily apply the draft values for the test.
        let originalURL = settings.backendURL
        let originalKey = settings.apiKey
        settings.backendURL = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        settings.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        isTestingConnection = true
        testResult = nil

        BackendSyncManager.shared.fetchStatus { result in
            // Restore original values (unless the user saves).
            settings.backendURL = originalURL
            settings.apiKey = originalKey

            isTestingConnection = false
            switch result {
            case .success(let sleeping):
                testResult = .success(sleeping)
            case .failure(let error):
                testResult = .failure(error.localizedDescription)
            }
        }
    }
}
