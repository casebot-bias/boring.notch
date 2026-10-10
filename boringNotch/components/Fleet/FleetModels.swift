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

// MARK: - FleetSnapshot

struct FleetSnapshot: Codable, Equatable {
    var generatedAt: String
    var machines: [FleetMachine]

    private enum CodingKeys: String, CodingKey {
        case generatedAt, machines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        self.machines = try container.decodeIfPresent([FleetMachine].self, forKey: .machines) ?? []
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

    var needsDecision: Bool {
        return state == "needs_decision"
    }

    private enum CodingKeys: String, CodingKey {
        case state, job, repo, pr, sha, round, reason, findings, verdict, updated
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

    var id: String {
        return device
    }

    private enum CodingKeys: String, CodingKey {
        case device, busy, items, slots, tokPerSec, kvCachePct, running, waiting, state, odin
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
    }
}

// MARK: - ActivitySnapshot

struct ActivitySnapshot: Codable, Equatable {
    var generatedAt: String
    var devices: [DeviceActivity]

    private enum CodingKeys: String, CodingKey {
        case generatedAt, devices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        self.devices = try container.decodeIfPresent([DeviceActivity].self, forKey: .devices) ?? []
    }

    static func decode(_ data: Data) throws -> ActivitySnapshot {
        return try JSONDecoder().decode(ActivitySnapshot.self, from: data)
    }
}
