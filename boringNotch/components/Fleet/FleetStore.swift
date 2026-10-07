//
//  FleetStore.swift
//  boringNotch
//
//  Polls the fleet endpoints (`/api/fleet`, `/api/activity`) and publishes the
//  latest snapshots. Polling runs only while Defaults[.showFleet] is true; the
//  interval tightens while the notch is open. Failures are silent — only the
//  reachability/lastUpdated state changes.
//

import Combine
import Defaults
import Foundation

@MainActor
final class FleetStore: ObservableObject {
    static let shared = FleetStore()

    @Published private(set) var fleet: FleetSnapshot?
    @Published private(set) var activity: ActivitySnapshot?
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastUpdated: Date?

    var orbitModel: FleetOrbitModel {
        return FleetOrbitBuilder.build(fleet: fleet, activity: activity)
    }

    var activeCount: Int {
        return orbitModel.activeCount
    }

    var isBusy: Bool {
        return orbitModel.isBusy
    }

    // MARK: - Tunables

    private static let activityIntervalOpen: TimeInterval = 2
    private static let activityIntervalClosed: TimeInterval = 15
    private static let fleetIntervalOpen: TimeInterval = 5
    private static let fleetIntervalClosed: TimeInterval = 15
    private static let requestTimeout: TimeInterval = 3

    // MARK: - State

    private let session: URLSession
    private var fleetTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var showFleetCancellable: AnyCancellable?
    private var notchOpen = false
    private var lastSuccessAt: Date?
    private var lastErrorAt: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = Self.requestTimeout
        self.session = URLSession(configuration: config)
    }

    // MARK: - Lifecycle

    /// Starts polling. Idempotent and safe to call from several screens; only
    /// one set of loops ever runs. Polling begins only when `showFleet` is on
    /// and follows the setting while the store lives.
    func start() {
        if showFleetCancellable == nil {
            showFleetCancellable = Defaults.publisher(.showFleet)
                .sink { [weak self] change in
                    let enabled = change.newValue
                    Task { @MainActor [weak self] in
                        self?.applyShowFleet(enabled)
                    }
                }
        }
        applyShowFleet(Defaults[.showFleet])
    }

    /// Cancels both polling loops; the last published snapshots are kept.
    func stop() {
        stopPolling()
    }

    func setNotchOpen(_ open: Bool) {
        let wasOpen = notchOpen
        notchOpen = open
        // Flipping to open should feel instant instead of waiting out the
        // closed-interval sleep; restarting also adopts the open cadence.
        guard open, !wasOpen, isPolling else { return }
        stopPolling()
        startPolling()
    }

    func settingsDidChange() {
        // Restart so a changed base URL or enable flag takes effect immediately.
        stopPolling()
        if Defaults[.showFleet] {
            startPolling()
        }
    }

    // MARK: - Polling

    private var isPolling: Bool {
        return fleetTask != nil || activityTask != nil
    }

    private func applyShowFleet(_ enabled: Bool) {
        if enabled {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        guard !isPolling else { return }
        fleetTask = Task { [weak self] in
            await self?.fleetLoop()
        }
        activityTask = Task { [weak self] in
            await self?.activityLoop()
        }
    }

    private func stopPolling() {
        fleetTask?.cancel()
        fleetTask = nil
        activityTask?.cancel()
        activityTask = nil
    }

    private func fleetLoop() async {
        while !Task.isCancelled {
            await fetchFleet()
            let interval = notchOpen ? Self.fleetIntervalOpen : Self.fleetIntervalClosed
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
            } catch {
                return
            }
        }
    }

    private func activityLoop() async {
        while !Task.isCancelled {
            await fetchActivity()
            let interval = notchOpen ? Self.activityIntervalOpen : Self.activityIntervalClosed
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
            } catch {
                return
            }
        }
    }

    // MARK: - Fetch

    private func fetchFleet() async {
        guard let baseURL = baseURL() else {
            markFailure()
            return
        }
        do {
            let snapshot = try await FleetClient(baseURL: baseURL, session: session).fetchFleet()
            fleet = snapshot
            markSuccess()
        } catch {
            if !Task.isCancelled {
                markFailure()
            }
        }
    }

    private func fetchActivity() async {
        guard let baseURL = baseURL() else {
            markFailure()
            return
        }
        do {
            let snapshot = try await FleetClient(baseURL: baseURL, session: session).fetchActivity()
            activity = snapshot
            markSuccess()
        } catch {
            if !Task.isCancelled {
                markFailure()
            }
        }
    }

    /// Reads the base URL fresh on every fetch; an invalid/empty URL is a failure.
    private func baseURL() -> URL? {
        var base = Defaults[.fleetBaseURL].trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        guard !base.isEmpty else {
            return nil
        }
        return URL(string: base)
    }

    // MARK: - Reachability bookkeeping

    private func markSuccess() {
        let now = Date()
        lastSuccessAt = now
        lastUpdated = now
        isReachable = computeIsReachable()
    }

    private func markFailure() {
        lastErrorAt = Date()
        isReachable = computeIsReachable()
    }

    /// Reachable once something has succeeded and no failure is newer than the last success.
    private func computeIsReachable() -> Bool {
        guard let lastSuccessAt else {
            return false
        }
        guard let lastErrorAt else {
            return true
        }
        return lastSuccessAt >= lastErrorAt
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        return UInt64(interval * 1_000_000_000)
    }
}
