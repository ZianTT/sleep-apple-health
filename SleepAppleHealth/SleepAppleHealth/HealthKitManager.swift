import Foundation
import HealthKit
import Combine

/// Manages HealthKit authorization, sleep data queries, and background observer setup.
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var currentSleepState: Bool = false   // true = sleeping
    @Published var lastUpdated: Date?

    // Callback invoked whenever the detected sleep state changes.
    var onSleepStateChanged: ((Bool) -> Void)?

    private var observerQuery: HKObserverQuery?

    private init() {}

    // MARK: - Authorization

    /// Requests HealthKit read authorization for sleep data.
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, nil)
            return
        }
        healthStore.requestAuthorization(toShare: [], read: [sleepType]) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = self.healthStore.authorizationStatus(for: self.sleepType)
            }
            completion(success, error)
        }
    }

    // MARK: - Observer Query

    /// Starts an HKObserverQuery so the app receives callbacks whenever Apple Health
    /// receives new sleep data. Also enables background delivery so the system can
    /// wake the app even when it is not in the foreground.
    func startObservingSleepData() {
        guard observerQuery == nil else { return }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self = self else {
                completionHandler()
                return
            }
            if let error = error {
                print("[HealthKit] Observer error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            self.fetchCurrentSleepState { isSleeping in
                DispatchQueue.main.async {
                    let previousState = self.currentSleepState
                    self.currentSleepState = isSleeping
                    self.lastUpdated = Date()
                    if isSleeping != previousState {
                        self.onSleepStateChanged?(isSleeping)
                    }
                }
                completionHandler()
            }
        }

        observerQuery = query
        healthStore.execute(query)

        // Enable background delivery so iOS wakes the app in the background when
        // new sleep data is written to HealthKit (e.g. by Apple Watch).
        healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { success, error in
            if let error = error {
                print("[HealthKit] Background delivery setup error: \(error.localizedDescription)")
            } else {
                print("[HealthKit] Background delivery enabled: \(success)")
            }
        }
    }

    /// Stops the currently active observer query.
    func stopObservingSleepData() {
        if let query = observerQuery {
            healthStore.stop(query)
            observerQuery = nil
        }
    }

    // MARK: - Sleep State Detection

    /// Queries the last 24 hours of sleep samples and determines whether the user
    /// is currently sleeping.
    ///
    /// Logic:
    /// 1. If any "asleep" sample's time window contains the current time → sleeping.
    /// 2. If the most recent "asleep" sample ended within the last 15 minutes →
    ///    assume still sleeping (Watch may have just written a segment).
    /// 3. Otherwise → awake.
    func fetchCurrentSleepState(completion: @escaping (Bool) -> Void) {
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .hour, value: -24, to: now)!

        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: now,
            options: .strictStartDate
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            guard let samples = results as? [HKCategorySample], error == nil else {
                print("[HealthKit] Query error: \(String(describing: error?.localizedDescription))")
                completion(false)
                return
            }

            let isSleeping = HealthKitManager.determineSleepState(from: samples, at: now)
            completion(isSleeping)
        }

        healthStore.execute(query)
    }

    /// Returns sleep samples from the past `days` days, newest first.
    func fetchRecentSleepSamples(days: Int = 7, completion: @escaping ([HKCategorySample]) -> Void) {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: 50,
            sortDescriptors: [sortDescriptor]
        ) { _, results, error in
            let samples = (results as? [HKCategorySample]) ?? []
            completion(samples)
        }
        healthStore.execute(query)
    }

    // MARK: - Helpers

    /// Returns `true` when the samples indicate the user is currently asleep.
    static func determineSleepState(from samples: [HKCategorySample], at date: Date) -> Bool {
        let asleepValues = asleepCategoryValues()

        // 1. Is the user currently inside a sleep window?
        for sample in samples where asleepValues.contains(sample.value) {
            if sample.startDate <= date && date <= sample.endDate {
                return true
            }
        }

        // 2. Did the most recent asleep sample end very recently (≤ 15 min ago)?
        let recentThreshold: TimeInterval = 15 * 60
        if let latest = samples.first(where: { asleepValues.contains($0.value) }) {
            if date.timeIntervalSince(latest.endDate) <= recentThreshold {
                return true
            }
        }

        return false
    }

    /// Returns the set of HKCategoryValueSleepAnalysis raw values that represent
    /// being asleep (covers both pre-iOS 16 and iOS 16+ staging values).
    static func asleepCategoryValues() -> Set<Int> {
        var values: Set<Int> = []

        // Pre-iOS 16 unified "asleep" value
        values.insert(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)

        // iOS 16+ staged sleep values
        if #available(iOS 16.0, *) {
            values.insert(HKCategoryValueSleepAnalysis.asleepCore.rawValue)
            values.insert(HKCategoryValueSleepAnalysis.asleepDeep.rawValue)
            values.insert(HKCategoryValueSleepAnalysis.asleepREM.rawValue)
        }

        return values
    }

    /// Human-readable label for an HKCategoryValueSleepAnalysis raw value.
    static func sleepStageLabel(for value: Int) -> String {
        switch value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "In Bed"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "Awake"
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return "Asleep"
        default:
            if #available(iOS 16.0, *) {
                switch value {
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return "Light Sleep"
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return "Deep Sleep"
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  return "REM Sleep"
                default: break
                }
            }
            return "Unknown"
        }
    }
}
