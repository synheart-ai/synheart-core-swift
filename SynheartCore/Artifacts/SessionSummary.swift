import Foundation

public struct SessionInfo: Codable {
    public let sessionId: String
    public let startMs: Int64
    public let endMs: Int64
    public let mode: String

    public init(sessionId: String, startMs: Int64, endMs: Int64, mode: String) {
        self.sessionId = sessionId
        self.startMs = startMs
        self.endMs = endMs
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case startMs = "start_ms"
        case endMs = "end_ms"
        case mode
    }
}

public struct CoverageInfo: Codable {
    public let totalWindows: Int
    public let windowSizeMs: Int

    public init(totalWindows: Int, windowSizeMs: Int = 30000) {
        self.totalWindows = totalWindows
        self.windowSizeMs = windowSizeMs
    }

    enum CodingKeys: String, CodingKey {
        case totalWindows = "total_windows"
        case windowSizeMs = "window_size_ms"
    }
}

public struct AggregateAxis: Codable {
    public let mean: Double
    public let min: Double
    public let max: Double

    public init(mean: Double, min: Double, max: Double) {
        self.mean = mean
        self.min = min
        self.max = max
    }
}

public struct SessionAggregates: Codable {
    public let focus: AggregateAxis
    public let arousal: AggregateAxis
    public let capacity: AggregateAxis
    public let sleep: AggregateAxis

    public init(focus: AggregateAxis, arousal: AggregateAxis, capacity: AggregateAxis, sleep: AggregateAxis) {
        self.focus = focus
        self.arousal = arousal
        self.capacity = capacity
        self.sleep = sleep
    }
}

public struct AppMetric: Codable {
    public let name: String
    public let mean: Double
    public let count: Int

    public init(name: String, mean: Double, count: Int) {
        self.name = name
        self.mean = mean
        self.count = count
    }
}

public struct InsightMetrics: Codable {
    public let appMetrics: [AppMetric]

    public init(appMetrics: [AppMetric] = []) {
        self.appMetrics = appMetrics
    }

    enum CodingKeys: String, CodingKey {
        case appMetrics = "app_metrics"
    }
}

/// A compact session summary for UI display and fast queries.
///
/// See RFC-CORE-0006 Section 6.3.
public struct SessionSummaryArtifact: Codable {
    public let header: ArtifactHeader
    public let session: SessionInfo
    public let coverage: CoverageInfo
    public let aggregates: SessionAggregates
    public let insightMetrics: InsightMetrics

    public init(
        header: ArtifactHeader,
        session: SessionInfo,
        coverage: CoverageInfo,
        aggregates: SessionAggregates,
        insightMetrics: InsightMetrics = InsightMetrics()
    ) {
        self.header = header
        self.session = session
        self.coverage = coverage
        self.aggregates = aggregates
        self.insightMetrics = insightMetrics
    }

    public static func create(
        subjectId: String,
        sessionId: String,
        startMs: Int64,
        endMs: Int64,
        mode: String,
        totalWindows: Int,
        aggregates: SessionAggregates,
        insightMetrics: InsightMetrics = InsightMetrics()
    ) -> SessionSummaryArtifact {
        let header = ArtifactHeader(
            type: "session_summary",
            subjectId: subjectId,
            sessionId: sessionId,
            timeRange: TimeRange(startMs: startMs, endMs: endMs),
            schema: SchemaRef(name: "session_summary", version: "1")
        )
        return SessionSummaryArtifact(
            header: header,
            session: SessionInfo(sessionId: sessionId, startMs: startMs, endMs: endMs, mode: mode),
            coverage: CoverageInfo(totalWindows: totalWindows),
            aggregates: aggregates,
            insightMetrics: insightMetrics
        )
    }

    enum CodingKeys: String, CodingKey {
        case header, session, coverage, aggregates
        case insightMetrics = "insight_metrics"
    }
}
