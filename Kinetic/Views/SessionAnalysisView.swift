import SwiftUI
import UniformTypeIdentifiers

struct SessionAnalysisView: View {
    @StateObject private var analyzer = SessionAnalyzer()
    @State private var showingFilePicker = false
    @State private var savedSessions: [(name: String, url: URL, date: Date)] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // On-device sessions
                if !savedSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved Sessions")
                            .font(.headline)
                        ForEach(savedSessions, id: \.url) { session in
                            Button {
                                analyzer.analyzeFile(at: session.url)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.name)
                                            .font(.caption.monospaced())
                                        Text(session.date, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import External CSV", systemImage: "doc.badge.plus")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)

                if analyzer.isAnalyzing {
                    ProgressView("Analyzing...")
                }

                if let report = analyzer.report {
                    reportView(report)
                } else if savedSessions.isEmpty && !analyzer.isAnalyzing {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Record a performance session to see analysis here")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Session Analysis")
        .onAppear {
            savedSessions = PerformanceLogger.savedSessions()
            // Auto-analyze the most recent session
            if analyzer.report == nil, let latest = savedSessions.first {
                analyzer.analyzeFile(at: latest.url)
            }
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                analyzer.analyzeFile(at: url)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - Report Display

    @ViewBuilder
    private func reportView(_ report: SessionReport) -> some View {
        // Overview
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            HStack(spacing: 20) {
                statBox("Duration", value: formatDuration(report.sessionDuration))
                statBox("Frames", value: "\(report.totalFrames)")
                if report.sessionDuration > 0 {
                    statBox("FPS", value: String(format: "%.0f", Double(report.totalFrames) / report.sessionDuration))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Latency
        if let stats = report.latencyStats {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Latency")
                        .font(.headline)
                    if stats.p95 > 15 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                HStack(spacing: 16) {
                    statBox("p50", value: String(format: "%.1fms", stats.p50))
                    statBox("p95", value: String(format: "%.1fms", stats.p95), highlight: stats.p95 > 15)
                    statBox("p99", value: String(format: "%.1fms", stats.p99), highlight: stats.p99 > 20)
                    statBox("max", value: String(format: "%.1fms", stats.max), highlight: stats.max > 30)
                }
                Text("\(stats.sampleCount) measurements")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Triggers
        if !report.triggerSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discrete Triggers")
                    .font(.headline)
                ForEach(report.triggerSummaries) { summary in
                    HStack {
                        Text(summary.gestureName)
                            .font(.body.monospaced())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(summary.triggerCount) triggers")
                                .font(.caption)
                            if summary.rapidFireCount > 0 {
                                Text("\(summary.rapidFireCount) rapid-fire")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.red)
                            }
                            if summary.averageInterval > 0 {
                                Text(String(format: "avg %.1fs apart", summary.averageInterval))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "peak: %.0f%%", summary.peakProbability * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Untriggered gesture peaks — critical for diagnosing detection failures
        if !report.untriggeredPeaks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Detection (No Triggers)")
                        .font(.headline)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                Text("These gestures were detected but never reached the trigger threshold.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(report.untriggeredPeaks) { peak in
                    HStack {
                        Text(peak.gestureName)
                            .font(.body.monospaced())
                        Spacer()
                        Text(String(format: "peak: %.0f%%", peak.peakProbability * 100))
                            .font(.caption.monospaced())
                            .foregroundStyle(peak.peakProbability > 0.5 ? .yellow : .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Continuous activity
        if !report.continuousActiveDurations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Continuous Activity")
                    .font(.headline)
                ForEach(report.continuousActiveDurations, id: \.0) { name, duration in
                    HStack {
                        Text(name)
                            .font(.body.monospaced())
                        Spacer()
                        Text(formatDuration(duration))
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Posture activity
        if !report.postureActiveDurations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Posture Activity")
                    .font(.headline)
                ForEach(report.postureActiveDurations, id: \.0) { name, duration in
                    HStack {
                        Text(name)
                            .font(.body.monospaced())
                        Spacer()
                        Text(formatDuration(duration))
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // Recommendations
        if report.hasIssues {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommendations")
                    .font(.headline)
                ForEach(recommendations(for: report), id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(rec)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func statBox(_ label: String, value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.monospaced().bold())
                .foregroundStyle(highlight ? .red : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return "\(mins)m \(secs)s"
    }

    private func recommendations(for report: SessionReport) -> [String] {
        var recs: [String] = []
        for summary in report.triggerSummaries where summary.rapidFireCount > 2 {
            recs.append("\"\(summary.gestureName)\" had \(summary.rapidFireCount) rapid-fire triggers. Increase cooldown or lower sensitivity.")
        }
        for peak in report.untriggeredPeaks {
            if peak.peakProbability < 0.3 {
                recs.append("\"\(peak.gestureName)\" peak was only \(Int(peak.peakProbability * 100))%. Try re-training with more consistent recordings, or increase sensitivity.")
            } else {
                recs.append("\"\(peak.gestureName)\" peaked at \(Int(peak.peakProbability * 100))% but didn't trigger. Increase sensitivity in gesture settings.")
            }
        }
        if let stats = report.latencyStats, stats.p95 > 15 {
            recs.append("Classification latency p95 is \(String(format: "%.1fms", stats.p95)). Consider reducing gesture count.")
        }
        return recs
    }
}
