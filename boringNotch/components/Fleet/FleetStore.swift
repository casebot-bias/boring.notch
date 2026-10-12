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
    /// The Case jobs' heartbeat (`/api/jobs`); nil while the dashboard has none (or is too old to know it).
    @Published private(set) var caseJobs: CaseJobsSnapshot?
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var lastUpdated: Date?

    /// The decision being sent, the last one answered (until the next fetch) and the last short
    /// error, so the ODIN tab can show its button's three states.
    @Published private(set) var sendingDecisionJob: String?
    @Published private(set) var sentDecisionJob: String?
    @Published private(set) var decisionError: String?

    var panelModel: FleetPanelModel {
        // The rings read the fleet payload's own freshness, never the shared reachability, which an
        // activity answer can set back to true while the fleet poll keeps failing.
        let model = FleetPanelModelBuilder.build(fleet: fleet, activity: activity, fleetLive: freshness.fleetIsLive,
                                                 caseJobs: caseJobs)
        return model.droppingDecisions(jobs: answeredJobs)
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
    /// Each poll's freshness, tracked apart: the rings must not go live again just because an activity
    /// poll answered while the fleet poll keeps failing.
    private var freshness = FleetFeedFreshness()
    /// Jobs answered from this notch: dropped from the panel until a fetch stops reporting them.
    private var answeredJobs: Set<String> = []

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

    /// Answers one open decision and, on success, drops it from the panel (and says so) until a
    /// later fetch agrees it is gone. A failure keeps the owner's choice and shows a short message.
    func sendDecision(_ decision: FleetDecision, option: OdinOption) async {
        guard let job = decision.job, !job.isEmpty, let baseURL = baseURL() else {
            decisionError = "This decision cannot be sent."
            return
        }
        guard sendingDecisionJob == nil else { return }
        sendingDecisionJob = job
        decisionError = nil
        defer { sendingDecisionJob = nil }
        do {
            _ = try await FleetClient(baseURL: baseURL, session: session)
                .sendDecision(job: job, option: option.id)
            answeredJobs.insert(job)
            sentDecisionJob = job
        } catch let error as FleetClientError {
            decisionError = Self.shortDecisionError(error)
        } catch {
            decisionError = Self.decisionFallbackError
        }
    }

    private static let decisionFallbackError = "Case did not answer. Try again."

    /// The short line the ODIN tab shows under the button: the server's own words when it sent
    /// one, otherwise one line per status. Never the raw body.
    private static func shortDecisionError(_ error: FleetClientError) -> String {
        switch error {
        case let .decisionRejected(status, message):
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            switch status {
            case 400: return "Case did not accept that choice."
            case 403: return "The notch is not allowed to answer."
            case 404: return "That job is no longer open."
            case 409: return "That job is still running."
            default: return "Case could not take the decision."
            }
        case .badStatus, .transport, .decoding:
            return decisionFallbackError
        }
    }

    /// Keeps only the jobs the latest feed still reports: an answered job leaves the set once the
    /// feed agrees it is gone, so a job that opens again shows up again. The open set comes from the
    /// raw model, not from `panelModel` (which already hides the answered jobs).
    private func pruneAnsweredDecisions() {
        guard !answeredJobs.isEmpty else { return }
        let open = Set(FleetPanelModelBuilder.build(fleet: fleet, activity: activity, fleetLive: freshness.fleetIsLive)
                        .decisions.compactMap(\.job))
        answeredJobs.formIntersection(open)
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
            await fetchJobs()
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
            markFailure(.fleet)
            return
        }
        do {
            let snapshot = try await FleetClient(baseURL: baseURL, session: session).fetchFleet()
            fleet = snapshot
            markSuccess(.fleet)
        } catch {
            if !Task.isCancelled {
                markFailure(.fleet)
            }
        }
    }

    /// The jobs heartbeat rides the fleet cadence. A 404 (old dashboard) clears it; any other failure
    /// keeps the last good value. It never touches reachability: the panel's health reads the other feeds.
    private func fetchJobs() async {
        guard let baseURL = baseURL() else { return }
        do {
            caseJobs = try await FleetClient(baseURL: baseURL, session: session).fetchJobs()
        } catch {
            // Keep the last good value.
        }
    }

    private func fetchActivity() async {
        guard let baseURL = baseURL() else {
            markFailure(.activity)
            return
        }
        do {
            let snapshot = try await FleetClient(baseURL: baseURL, session: session).fetchActivity()
            activity = snapshot
            pruneAnsweredDecisions()
            sentDecisionJob = nil
            markSuccess(.activity)
        } catch {
            if !Task.isCancelled {
                markFailure(.activity)
            }
        }
    }

    /// Reads the base URL fresh on every fetch; an invalid/empty URL is a failure.
    private func baseURL() -> URL? {
        FleetFormat.fleetBaseURL(Defaults[.fleetBaseURL])
    }

    // MARK: - Reachability bookkeeping

    /// Records the outcome of one poll and republishes the store's reachability, which both feeds share.
    private func markSuccess(_ source: FleetFeedFreshness.Source) {
        let now = Date()
        freshness.markSuccess(source, at: now)
        lastUpdated = now
        isReachable = freshness.isReachable
    }

    private func markFailure(_ source: FleetFeedFreshness.Source) {
        freshness.markFailure(source, at: Date())
        isReachable = freshness.isReachable
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        return UInt64(interval * 1_000_000_000)
    }
}
