//
//  FleetFormat.swift
//  boringNotch
//
//  Pure formatting/normalising functions for fleet data.
//  Depends only on Foundation and the model types (Reading, FleetMachine, DeviceActivity)
//  declared in the same target.
//
import Foundation

enum FleetFormat {

    static let unknown = "—"

    // MARK: - degrees

    /// "38.37" -> "38°"; "40.8" -> "41°"; unavailable -> "—"
    static func degrees(_ r: Reading) -> String {
        guard r.isAvailable, let value = r.value else { return unknown }
        let rounded = Int(value.rounded())
        return "\(rounded)°"
    }

    // MARK: - tokensPerSecond

    /// nil -> "—"; 0 -> "0 t/s"; 12.34 -> "12 t/s"
    static func tokensPerSecond(_ v: Double?) -> String {
        guard let v = v else { return unknown }
        return "\(Int(v.rounded())) t/s"
    }

    // MARK: - jobs

    /// n <= 0 -> "idle"; 1 -> "1 job"; 2 -> "2 jobs"
    static func jobs(_ n: Int) -> String {
        guard n > 0 else { return "idle" }
        return n == 1 ? "1 job" : "\(n) jobs"
    }

    // MARK: - elapsed

    /// nil -> "—"; negatives -> "—"; 44 -> "44s"; 1444 -> "24m 04s"; 3730 -> "1h 02m"
    static func elapsed(_ seconds: Int?) -> String {
        guard let seconds = seconds, seconds >= 0 else { return unknown }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }

        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        }

        return "\(seconds)s"
    }

    // MARK: - barFraction

    /// Clamped 0...1 of value/100; 0 when unavailable.
    static func barFraction(_ r: Reading) -> Double {
        guard r.isAvailable, let value = r.value else { return 0.0 }
        let fraction = value / 100.0
        return max(0.0, min(1.0, fraction))
    }

    // MARK: - isRAMWarning

    /// isAvailable && value > 80
    static func isRAMWarning(_ r: Reading) -> Bool {
        r.isAvailable && (r.value ?? 0) > 80
    }

    // MARK: - fleetBaseURL

    /// Normalises `Defaults[.fleetBaseURL]` into the URL used to reach the fleet:
    /// surrounding whitespace trimmed, every trailing slash dropped, `nil` when
    /// nothing is left. Shared by FleetStore polling and the "Open Fleet" link.
    static func fleetBaseURL(_ raw: String) -> URL? {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        guard !base.isEmpty else { return nil }
        return URL(string: base)
    }
}
