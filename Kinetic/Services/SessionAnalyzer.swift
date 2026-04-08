import Foundation
import Combine

/// Analyzes performance session CSV files to produce actionable diagnostics.
/// Parses the CSV format from PerformanceLogger and computes trigger stats,
/// false-positive indicators, latency distribution, and layer activity.
@MainActor
final class SessionAnalyzer: ObservableObject {
    @Published var report: SessionReport?
    @Published var isAnalyzing = false

    func analyze(csvString: String) {
        isAnalyzing = true

        let lines = csvString.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }

        guard lines.count > 1 else {
            report = nil
            isAnalyzing = false
            return
        }

        // Skip header
        let dataLines = Array(lines.dropFirst())

        var totalFrames = 0
        var triggers: [String: [TriggerEvent]] = [:]
        var gestureProbPeaks: [String: Float] = [:]
        var continuousActiveDurations: [String: TimeInterval] = [:]
        var continuousActiveStart: [String: TimeInterval] = [:]
        var postureActiveDurations: [String: TimeInterval] = [:]
        var postureActiveStart: [String: TimeInterval] = [:]
        var latencies: [Double] = []
        var firstTimestamp: TimeInterval?
        var lastTimestamp: TimeInterval?

        for line in dataLines {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 11 else { continue }
            totalFrames += 1

            let timestamp = TimeInterval(cols[0]) ?? 0
            if firstTimestamp == nil { firstTimestamp = timestamp }
            lastTimestamp = timestamp

            // Trigger
            let triggerName = cols[7]
            if !triggerName.isEmpty {
                var events = triggers[triggerName] ?? []
                events.append(TriggerEvent(timestamp: timestamp, gestureName: triggerName))
                triggers[triggerName] = events
            }

            // Probabilities — track peaks per gesture
            let probStr = cols[8]
            if !probStr.isEmpty {
                let entries = probStr.components(separatedBy: "|")
                for entry in entries {
                    let parts = entry.components(separatedBy: ":")
                    if parts.count == 2, let prob = Float(parts[1]) {
                        let name = parts[0]
                        gestureProbPeaks[name] = max(gestureProbPeaks[name] ?? 0, prob)
                    }
                }
            }

            // Continuous states
            let continuousStr = cols[9]
            if !continuousStr.isEmpty {
                let entries = continuousStr.components(separatedBy: "|")
                for entry in entries {
                    let parts = entry.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let name = parts[0]
                        let isOn = parts[1] == "on"
                        if isOn && continuousActiveStart[name] == nil {
                            continuousActiveStart[name] = timestamp
                        } else if !isOn, let start = continuousActiveStart[name] {
                            continuousActiveDurations[name, default: 0] += timestamp - start
                            continuousActiveStart[name] = nil
                        }
                    }
                }
            }

            // Posture states
            let postureStr = cols[10]
            if !postureStr.isEmpty {
                let entries = postureStr.components(separatedBy: "|")
                for entry in entries {
                    let parts = entry.components(separatedBy: ":")
                    if parts.count == 2 {
                        let name = parts[0]
                        let isOn = parts[1] == "on"
                        if isOn && postureActiveStart[name] == nil {
                            postureActiveStart[name] = timestamp
                        } else if !isOn, let start = postureActiveStart[name] {
                            postureActiveDurations[name, default: 0] += timestamp - start
                            postureActiveStart[name] = nil
                        }
                    }
                }
            }

            // Latency
            if cols.count >= 12, let lat = Double(cols[11]), lat > 0 {
                latencies.append(lat)
            }
        }

        // Close any still-active durations
        if let last = lastTimestamp {
            for (name, start) in continuousActiveStart {
                continuousActiveDurations[name, default: 0] += last - start
            }
            for (name, start) in postureActiveStart {
                postureActiveDurations[name, default: 0] += last - start
            }
        }

        // Build trigger summaries with rapid-fire detection
        var triggerSummaries: [TriggerSummary] = []
        for (name, events) in triggers.sorted(by: { $0.key < $1.key }) {
            var rapidFireCount = 0
            for i in 1..<events.count {
                if events[i].timestamp - events[i-1].timestamp < 0.3 {
                    rapidFireCount += 1
                }
            }
            let intervals = (1..<events.count).map { events[$0].timestamp - events[$0-1].timestamp }
            let avgInterval = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)

            triggerSummaries.append(TriggerSummary(
                gestureName: name,
                triggerCount: events.count,
                rapidFireCount: rapidFireCount,
                averageInterval: avgInterval,
                peakProbability: gestureProbPeaks[name] ?? 0
            ))
        }

        // Latency stats
        let sortedLatencies = latencies.sorted()
        let latencyStats: LatencyStats?
        if !sortedLatencies.isEmpty {
            let p50 = sortedLatencies[sortedLatencies.count / 2]
            let p95 = sortedLatencies[Int(Double(sortedLatencies.count) * 0.95)]
            let p99 = sortedLatencies[min(Int(Double(sortedLatencies.count) * 0.99), sortedLatencies.count - 1)]
            latencyStats = LatencyStats(
                mean: sortedLatencies.reduce(0, +) / Double(sortedLatencies.count),
                p50: p50,
                p95: p95,
                p99: p99,
                max: sortedLatencies.last ?? 0,
                sampleCount: sortedLatencies.count
            )
        } else {
            latencyStats = nil
        }

        let sessionDuration = (lastTimestamp ?? 0) - (firstTimestamp ?? 0)

        // Build probability peak summaries for gestures that were detected but never triggered
        let triggeredNames = Set(triggers.keys)
        let untriggeredPeaks = gestureProbPeaks
            .filter { !triggeredNames.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { ProbabilityPeak(gestureName: $0.key, peakProbability: $0.value) }

        report = SessionReport(
            totalFrames: totalFrames,
            sessionDuration: sessionDuration,
            triggerSummaries: triggerSummaries,
            untriggeredPeaks: untriggeredPeaks,
            continuousActiveDurations: continuousActiveDurations.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
            postureActiveDurations: postureActiveDurations.sorted { $0.key < $1.key }.map { ($0.key, $0.value) },
            latencyStats: latencyStats
        )

        isAnalyzing = false
    }

    func analyzeFile(at url: URL) {
        guard let csvString = try? String(contentsOf: url, encoding: .utf8) else {
            report = nil
            return
        }
        analyze(csvString: csvString)
    }
}

// MARK: - Report Models

struct TriggerEvent {
    let timestamp: TimeInterval
    let gestureName: String
}

struct TriggerSummary: Identifiable {
    var id: String { gestureName }
    let gestureName: String
    let triggerCount: Int
    let rapidFireCount: Int
    let averageInterval: TimeInterval
    let peakProbability: Float
}

struct ProbabilityPeak: Identifiable {
    var id: String { gestureName }
    let gestureName: String
    let peakProbability: Float
}

struct LatencyStats {
    let mean: Double
    let p50: Double
    let p95: Double
    let p99: Double
    let max: Double
    let sampleCount: Int
}

struct SessionReport {
    let totalFrames: Int
    let sessionDuration: TimeInterval
    let triggerSummaries: [TriggerSummary]
    let untriggeredPeaks: [ProbabilityPeak]
    let continuousActiveDurations: [(String, TimeInterval)]
    let postureActiveDurations: [(String, TimeInterval)]
    let latencyStats: LatencyStats?

    var hasIssues: Bool {
        triggerSummaries.contains { $0.rapidFireCount > 2 } ||
        (latencyStats?.p95 ?? 0) > 15 ||
        untriggeredPeaks.contains { $0.peakProbability > 0.1 }
    }
}
