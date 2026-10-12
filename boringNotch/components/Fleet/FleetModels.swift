import Foundation

// MARK: - Reading

struct Reading: Codable, Equatable {
    var value: Double?
    var state: String
    var note: String?

    var isAvailable: Bool {
        return state == "ok" && value != nil
    }

    private enum CodingKeys: String, CodingKey {
        case value, state, note
    }

    init() {
        self.value = nil
        self.state = "unavailable"
        self.note = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decodeIfPresent(Double.self, forKey: .value)
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? "unavailable"
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    init(value: Double?, state: String, note: String?) {
        self.value = value
        self.state = state
        self.note = note
    }
}

// MARK: - ModelServer

struct ModelServer: Codable, Equatable {
    var id: String
    var label: String
    var endpoint: String
    var state: String
    var models: [String]

    private enum CodingKeys: String, CodingKey {
        case id, label, endpoint, state, models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        self.models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
    }
}

// MARK: - FleetMachine

struct FleetMachine: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var state: String
    var ramUsedPct: Reading
    var cpuLoadPct: Reading
    var cpuTempC: Reading
    var gpuName: String?
    var gpuUtilPct: Reading
    var gpuTempC: Reading
    var models: [ModelServer]

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, state
        case ramUsedPct
        case cpuLoadPct, cpuTempC
        case gpuName, gpuUtilPct, gpuTempC
        case models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        self.state = try container.decode(String.self, forKey: .state)
        self.ramUsedPct = try container.decodeIfPresent(Reading.self, forKey: .ramUsedPct) ?? Reading(value: nil, state: "unavailable", note: nil)
        self.cpuLoadPct = try container.decodeIfPresent(Reading.self, forKey: .cpuLoadPct) ?? Reading(value: nil, state: "unavailable", note: nil)
        self.cpuTempC = try container.decodeIfPresent(Reading.self, forKey: .cpuTempC) ?? Reading(value: nil, state: "unavailable", note: nil)
        self.gpuName = try container.decodeIfPresent(String.self, forKey: .gpuName)
        self.gpuUtilPct = try container.decodeIfPresent(Reading.self, forKey: .gpuUtilPct) ?? Reading(value: nil, state: "unavailable", note: nil)
        self.gpuTempC = try container.decodeIfPresent(Reading.self, forKey: .gpuTempC) ?? Reading(value: nil, state: "unavailable", note: nil)
        self.models = try container.decodeIfPresent([ModelServer].self, forKey: .models) ?? []
    }
}

/// How fast one answer is being written, as the fleet API reports it: the current decode speed, when
/// it was last non-null, and the last ten minutes of readings (null = nobody writing).
struct FleetSpeed: Codable, Equatable {
    var current: Double?
    var lastAt: String?
    var trend: [Double?]
    var stepSec: Int?

    private enum CodingKeys: String, CodingKey { case current, lastAt, trend, stepSec }

    init(current: Double?, lastAt: String?, trend: [Double?] = [], stepSec: Int? = nil) {
        self.current = current
        self.lastAt = lastAt
        self.trend = trend
        self.stepSec = stepSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.current = try container.decodeIfPresent(Double.self, forKey: .current)
        self.lastAt = try container.decodeIfPresent(String.self, forKey: .lastAt)
        self.trend = try container.decodeIfPresent([Double?].self, forKey: .trend) ?? []
        self.stepSec = try container.decodeIfPresent(Int.self, forKey: .stepSec)
    }
}

// MARK: - FleetSnapshot

struct FleetSnapshot: Codable, Equatable {
    var generatedAt: String
    var machines: [FleetMachine]
    /// The fleet-wide decode speed; nil while the feed reports none.
    var speed: FleetSpeed?

    private enum CodingKeys: String, CodingKey {
        case generatedAt, machines, speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        self.machines = try container.decodeIfPresent([FleetMachine].self, forKey: .machines) ?? []
        self.speed = try container.decodeIfPresent(FleetSpeed.self, forKey: .speed)
    }

    static func decode(_ data: Data) throws -> FleetSnapshot {
        return try JSONDecoder().decode(FleetSnapshot.self, from: data)
    }
}

// MARK: - ActivityItem

struct ActivityItem: Codable, Equatable, Identifiable {
    var label: String
    var device: String
    var agent: String?
    var model: String?
    var since: String?
    var lastStep: String?
    var cwd: String?
    var file: String?
    var elapsedSec: Int?

    var id: String {
        if let file = file {
            return file
        }
        return label + "-" + (since ?? "")
    }

    private enum CodingKeys: String, CodingKey {
        case label, device, agent, model, since, lastStep, cwd, file, elapsedSec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decode(String.self, forKey: .label)
        self.device = try container.decode(String.self, forKey: .device)
        self.agent = try container.decodeIfPresent(String.self, forKey: .agent)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.since = try container.decodeIfPresent(String.self, forKey: .since)
        self.lastStep = try container.decodeIfPresent(String.self, forKey: .lastStep)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.file = try container.decodeIfPresent(String.self, forKey: .file)
        self.elapsedSec = try container.decodeIfPresent(Int.self, forKey: .elapsedSec)
    }
}

// MARK: - SlotState

struct SlotState: Codable, Equatable {
    var used: Int
    var total: Int
    var busy: [Bool]

    private enum CodingKeys: String, CodingKey {
        case used, total, busy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.used = try container.decodeIfPresent(Int.self, forKey: .used) ?? 0
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.busy = try container.decodeIfPresent([Bool].self, forKey: .busy) ?? []
    }
}

// MARK: - OdinStatus

/// One choice the owner can answer an Odin decision with (the shared contract's `options[]`).
struct OdinOption: Codable, Equatable {
    var id: String
    var label: String
    var pick: Bool

    /// The contract's default list, for entries that carry no `options` at all.
    static let defaults: [OdinOption] = [
        OdinOption(id: "fix", label: "One more fix round", pick: false),
        OdinOption(id: "accept", label: "Accept, add to backlog", pick: false),
        OdinOption(id: "stop", label: "Stop, close the PR", pick: false),
    ]

    private enum CodingKeys: String, CodingKey {
        case id, label, pick
    }

    init(id: String, label: String, pick: Bool) {
        self.id = id
        self.label = label
        self.pick = pick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        self.pick = try container.decodeIfPresent(Bool.self, forKey: .pick) ?? false
    }
}

/// Odin's QA status: the fleet API copies the writer's `~/.case/odin.json` under
/// the activity device's `odin.status`, so a missing block is an Odin that does
/// not need a decision, never an error.
struct OdinStatus: Codable, Equatable {
    var state: String
    var job: String?
    var repo: String?
    var pr: Int?
    var sha: String?
    var round: Int?
    var reason: String?
    var findings: Int?
    var verdict: String?
    var updated: String?

    /// Job titles the reviewer found this decision's findings in.
    var found: [String]
    /// The question the owner answers, when the decision carries one.
    var question: String?
    /// The owner's answer choices; a missing key decodes to `OdinOption.defaults`.
    var options: [OdinOption]

    var needsDecision: Bool {
        return state == "needs_decision"
    }

    private enum CodingKeys: String, CodingKey {
        case state, job, repo, pr, sha, round, reason, findings, verdict, updated, found, question, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        self.job = try container.decodeIfPresent(String.self, forKey: .job)
        self.repo = try container.decodeIfPresent(String.self, forKey: .repo)
        self.pr = try container.decodeIfPresent(Int.self, forKey: .pr)
        self.sha = try container.decodeIfPresent(String.self, forKey: .sha)
        self.round = try container.decodeIfPresent(Int.self, forKey: .round)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.findings = try container.decodeIfPresent(Int.self, forKey: .findings)
        self.verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        self.updated = try container.decodeIfPresent(String.self, forKey: .updated)
        self.found = try container.decodeIfPresent([String].self, forKey: .found) ?? []
        self.question = try container.decodeIfPresent(String.self, forKey: .question)
        self.options = try container.decodeIfPresent([OdinOption].self, forKey: .options) ?? OdinOption.defaults
    }
}

/// The activity feed's `odin` block: `{ "status": …, "counts": … }`. Only the
/// status matters to the notch, so the counts are dropped at decode.
struct OdinReport: Codable, Equatable {
    var status: OdinStatus?

    /// Every entry of the writer's open-decisions file; nil when the feed omits the field
    /// (a dashboard older than the list), `[]` when it is present and nothing is open.
    var open: [OdinStatus]?

    private enum CodingKeys: String, CodingKey {
        case status, open
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(OdinStatus.self, forKey: .status)
        self.open = try container.decodeIfPresent([OdinStatus].self, forKey: .open)
    }
}

// MARK: - DeviceActivity

struct DeviceActivity: Codable, Equatable, Identifiable {
    var device: String
    var busy: Bool?
    var items: [ActivityItem]
    var slots: SlotState?
    var tokPerSec: Double?
    var kvCachePct: Double?
    var running: Int?
    var waiting: Int?
    var state: String
    var odin: OdinReport?
    /// The device's own decode speed in tokens/s; nil when the device reports none.
    var speed: Double?

    var id: String {
        return device
    }

    private enum CodingKeys: String, CodingKey {
        case device, busy, items, slots, tokPerSec, kvCachePct, running, waiting, state, odin, speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.device = try container.decode(String.self, forKey: .device)
        self.busy = try container.decodeIfPresent(Bool.self, forKey: .busy)
        self.items = try container.decodeIfPresent([ActivityItem].self, forKey: .items) ?? []
        self.slots = try container.decodeIfPresent(SlotState.self, forKey: .slots)
        self.tokPerSec = try container.decodeIfPresent(Double.self, forKey: .tokPerSec)
        self.kvCachePct = try container.decodeIfPresent(Double.self, forKey: .kvCachePct)
        self.running = try container.decodeIfPresent(Int.self, forKey: .running)
        self.waiting = try container.decodeIfPresent(Int.self, forKey: .waiting)
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        self.odin = try container.decodeIfPresent(OdinReport.self, forKey: .odin)
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed)
    }
}

// MARK: - ActivitySnapshot

struct ActivitySnapshot: Codable, Equatable {
    var generatedAt: String
    var devices: [DeviceActivity]
    /// Fleet-wide decode speed; nil while the feed reports no speed block.
    var speed: FleetSpeed?

    private enum CodingKeys: String, CodingKey {
        case generatedAt, devices, speed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        self.devices = try container.decodeIfPresent([DeviceActivity].self, forKey: .devices) ?? []
        self.speed = try container.decodeIfPresent(FleetSpeed.self, forKey: .speed)
    }

    static func decode(_ data: Data) throws -> ActivitySnapshot {
        return try JSONDecoder().decode(ActivitySnapshot.self, from: data)
    }
}

// MARK: - Case jobs (`/api/jobs`)

private extension KeyedDecodingContainer {
    /// A string, or nil when the key is missing or holds anything else.
    func looseString(_ key: Key) -> String? {
        (try? decodeIfPresent(String.self, forKey: key)) ?? nil
    }

    /// A whole number the dashboard may send as 3 or 3.0; anything else reads as missing.
    func looseInt(_ key: Key) -> Int? {
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
        if let value = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil, value.isFinite {
            return Int(value.rounded())
        }
        return nil
    }
}

/// The watchdog's last word on a job: `ok`, `nudged`, `restarted`, `escalated` or `none`.
struct CaseJobWatchdog: Equatable {
    var state: String?
    var at: String?
    var detail: String?
}

/// How many of a job's spec items have proof (`blocking` ones stop the job from passing).
struct CaseJobProof: Equatable {
    var total: Int?
    var proven: Int?
    var missing: Int?
    var blocking: Int?
}

/// One Case job as the fleet dashboard's `GET /api/jobs` reports it. Every field but the name is
/// optional: an older or newer dashboard may leave any of them out.
struct CaseJob: Equatable, Identifiable {
    var job: String = ""
    var running: Bool = false
    var startedAt: String?
    var itemsPassed: Int?
    var itemsTotal: Int?
    var currentItemText: String?
    var lastCommitAt: String?
    var lastActivityAt: String?
    var minutesSinceCommit: Int?
    var watchdog: CaseJobWatchdog?
    var proof: CaseJobProof?

    var id: String { job }
}

extension CaseJobWatchdog: Decodable {
    private enum CodingKeys: String, CodingKey { case state, at, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(state: c.looseString(.state), at: c.looseString(.at), detail: c.looseString(.detail))
    }
}

extension CaseJobProof: Decodable {
    private enum CodingKeys: String, CodingKey { case total, proven, missing, blocking }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(total: c.looseInt(.total), proven: c.looseInt(.proven),
                  missing: c.looseInt(.missing), blocking: c.looseInt(.blocking))
    }
}

extension CaseJob: Decodable {
    private enum CodingKeys: String, CodingKey {
        case job, running, startedAt, itemsPassed, itemsTotal, currentItem, lastCommitAt,
             lastActivityAt, minutesSinceCommit, watchdog, proof
    }

    private struct CurrentItem: Decodable { var text: String? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let item = (try? c.decodeIfPresent(CurrentItem.self, forKey: .currentItem)) ?? nil
        self.init(job: c.looseString(.job) ?? "",
                  running: ((try? c.decodeIfPresent(Bool.self, forKey: .running)) ?? nil) ?? false,
                  startedAt: c.looseString(.startedAt),
                  itemsPassed: c.looseInt(.itemsPassed),
                  itemsTotal: c.looseInt(.itemsTotal),
                  currentItemText: item?.text,
                  lastCommitAt: c.looseString(.lastCommitAt),
                  lastActivityAt: c.looseString(.lastActivityAt),
                  minutesSinceCommit: c.looseInt(.minutesSinceCommit),
                  watchdog: (try? c.decodeIfPresent(CaseJobWatchdog.self, forKey: .watchdog)) ?? nil,
                  proof: (try? c.decodeIfPresent(CaseJobProof.self, forKey: .proof)) ?? nil)
    }
}

/// The `/api/jobs` payload: running jobs first. Jobs without a name are dropped.
struct CaseJobsSnapshot: Equatable, Decodable {
    var generatedAt: String = ""
    var jobs: [CaseJob] = []

    private enum CodingKeys: String, CodingKey { case generatedAt, jobs }

    init(generatedAt: String = "", jobs: [CaseJob] = []) {
        self.generatedAt = generatedAt
        self.jobs = jobs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = c.looseString(.generatedAt) ?? ""
        let all = ((try? c.decodeIfPresent([CaseJob].self, forKey: .jobs)) ?? nil) ?? []
        self.jobs = all.filter { !$0.job.isEmpty }
    }

    static func decode(_ data: Data) throws -> CaseJobsSnapshot {
        return try JSONDecoder().decode(CaseJobsSnapshot.self, from: data)
    }
}
