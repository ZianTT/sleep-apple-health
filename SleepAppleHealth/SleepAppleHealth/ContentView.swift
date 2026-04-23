import SwiftUI
import HealthKit

struct ContentView: View {
    @StateObject private var hkManager = HealthKitManager.shared
    @StateObject private var settings = SettingsManager.shared

    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showSettings = false
    @State private var backendStatus: Bool?

    private let syncManager = BackendSyncManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    // --- Sleep state card ---
                    sleepStateCard

                    // --- Last sync info ---
                    if let date = settings.lastSyncDate {
                        lastSyncCard(date: date)
                    }

                    // --- Manual sync button ---
                    syncButton

                    // --- Recent sleep samples ---
                    recentSamplesSection
                }
                .padding()
            }
            .navigationTitle("Sleep Sync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: refreshAll) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isSyncing)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear(perform: onAppear)
        }
    }

    // MARK: - Sub-views

    private var sleepStateCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hkManager.currentSleepState ? Color.indigo.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 110, height: 110)
                Image(systemName: hkManager.currentSleepState ? "moon.zzz.fill" : "sun.max.fill")
                    .font(.system(size: 48))
                    .foregroundColor(hkManager.currentSleepState ? .indigo : .orange)
            }

            Text(hkManager.currentSleepState ? "Sleeping" : "Awake")
                .font(.title.bold())

            if let updated = hkManager.lastUpdated {
                Text("Updated \(updated, formatter: relativeDateFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            authorizationBanner
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private var authorizationBanner: some View {
        switch hkManager.authorizationStatus {
        case .notDetermined:
            Button("Authorize HealthKit") {
                authorizeHealthKit()
            }
            .buttonStyle(.borderedProminent)

        case .sharingDenied:
            Label("HealthKit access denied — open Settings to grant access.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)

        default:
            EmptyView()
        }
    }

    private func lastSyncCard(date: Date) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last synced to backend").font(.caption).foregroundColor(.secondary)
                Text(date, formatter: relativeDateFormatter).font(.subheadline)
                if let state = settings.lastSyncedState {
                    Text("Status: \(state ? "sleeping" : "awake")").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var syncButton: some View {
        VStack(spacing: 8) {
            Button(action: manualSync) {
                HStack {
                    if isSyncing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    Text(isSyncing ? "Syncing…" : "Sync Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(settings.isConfigured ? Color.accentColor : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isSyncing || !settings.isConfigured)

            if !settings.isConfigured {
                Text("Configure backend URL and API key in Settings first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let msg = syncMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @State private var recentSamples: [HKCategorySample] = []

    private var recentSamplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Sleep Records")
                .font(.headline)
                .padding(.horizontal, 4)

            if recentSamples.isEmpty {
                Text("No sleep data found in the past 7 days.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
            } else {
                ForEach(recentSamples.prefix(10), id: \.uuid) { sample in
                    SleepSampleRow(sample: sample)
                }
            }
        }
    }

    // MARK: - Actions

    private func onAppear() {
        if hkManager.authorizationStatus == .notDetermined {
            authorizeHealthKit()
        } else {
            refreshAll()
        }
    }

    private func authorizeHealthKit() {
        hkManager.requestAuthorization { success, _ in
            if success {
                hkManager.startObservingSleepData()
                refreshAll()
            }
        }
    }

    private func refreshAll() {
        hkManager.fetchCurrentSleepState { isSleeping in
            DispatchQueue.main.async {
                hkManager.currentSleepState = isSleeping
                hkManager.lastUpdated = Date()
            }
        }
        hkManager.fetchRecentSleepSamples { samples in
            DispatchQueue.main.async {
                recentSamples = samples
            }
        }
    }

    private func manualSync() {
        isSyncing = true
        syncMessage = nil

        hkManager.fetchCurrentSleepState { isSleeping in
            DispatchQueue.main.async {
                hkManager.currentSleepState = isSleeping
                hkManager.lastUpdated = Date()
            }

            syncManager.syncSleepState(isSleeping: isSleeping, force: true) { result in
                DispatchQueue.main.async {
                    isSyncing = false
                    switch result {
                    case .success:
                        syncMessage = "Successfully synced: \(isSleeping ? "sleeping" : "awake")"
                    case .failure(let error):
                        syncMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - Sleep sample row

struct SleepSampleRow: View {
    let sample: HKCategorySample

    var body: some View {
        HStack {
            Image(systemName: stageIcon)
                .foregroundColor(stageColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(HealthKitManager.sleepStageLabel(for: sample.value))
                    .font(.subheadline.weight(.medium))
                Text("\(sample.startDate, formatter: timeFormatter) – \(sample.endDate, formatter: timeFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(duration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var stageIcon: String {
        let asleep = HealthKitManager.asleepCategoryValues()
        if asleep.contains(sample.value) { return "moon.fill" }
        if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue { return "bed.double.fill" }
        return "sun.max.fill"
    }

    private var stageColor: Color {
        let asleep = HealthKitManager.asleepCategoryValues()
        if asleep.contains(sample.value) { return .indigo }
        if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue { return .teal }
        return .orange
    }

    private var duration: String {
        let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Formatters

private let relativeDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM/dd HH:mm"
    return f
}()
