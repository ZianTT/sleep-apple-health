import UIKit
import HealthKit
import BackgroundTasks

class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - App launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        setupHealthKit()
        registerBackgroundTask()
        scheduleBackgroundSleepCheck()
        return true
    }

    // MARK: - HealthKit setup

    private func setupHealthKit() {
        let hk = HealthKitManager.shared

        hk.requestAuthorization { success, error in
            if success {
                hk.startObservingSleepData()
            } else if let error = error {
                print("[AppDelegate] HealthKit authorization failed: \(error.localizedDescription)")
            }
        }

        // Wire up the state-change callback so new HealthKit data triggers a sync.
        hk.onSleepStateChanged = { isSleeping in
            BackendSyncManager.shared.syncSleepState(isSleeping: isSleeping) { result in
                switch result {
                case .success:
                    print("[AppDelegate] Synced sleep state → \(isSleeping ? "sleeping" : "awake")")
                case .failure(let error):
                    print("[AppDelegate] Sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Background task registration (BGTaskScheduler, iOS 13+)

    private let backgroundTaskIdentifier = "com.sleepapplehealth.sleepcheck"

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let bgTask = task as? BGAppRefreshTask else { return }
            self.handleBackgroundSleepCheck(task: bgTask)
        }
    }

    private func scheduleBackgroundSleepCheck() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Ask the system to run again in at most 15 minutes.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[AppDelegate] BGTaskScheduler submit error: \(error.localizedDescription)")
        }
    }

    private func handleBackgroundSleepCheck(task: BGAppRefreshTask) {
        // Reschedule the next check before doing work.
        scheduleBackgroundSleepCheck()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        HealthKitManager.shared.fetchCurrentSleepState { isSleeping in
            BackendSyncManager.shared.syncSleepState(isSleeping: isSleeping) { _ in
                task.setTaskCompleted(success: true)
            }
        }
    }

    // MARK: - UIWindowScene support

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
