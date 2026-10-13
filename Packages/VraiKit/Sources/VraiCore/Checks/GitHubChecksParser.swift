import Foundation

public enum GitHubChecksParser {
    struct CheckRunsPayload: Decodable {
        struct Suite: Decodable {
            var id: Int?
        }

        struct App: Decodable {
            var slug: String?
        }

        struct Output: Decodable {
            var title: String?
        }

        struct Run: Decodable {
            var id: Int
            var name: String
            var status: String?
            var conclusion: String?
            var started_at: String?
            var completed_at: String?
            var html_url: String?
            var details_url: String?
            var check_suite: Suite?
            var app: App?
            var output: Output?
        }

        var check_runs: [Run]
    }

    struct StatusPayload: Decodable {
        struct Status: Decodable {
            var context: String
            var state: String
            var target_url: String?
            var description: String?
            var created_at: String?
            var updated_at: String?
        }

        var statuses: [Status]
    }

    struct WorkflowRunsPayload: Decodable {
        struct Run: Decodable {
            var id: Int
            var name: String?
            var check_suite_id: Int?
            var html_url: String?
        }

        var workflow_runs: [Run]
    }

    public struct WorkflowRun: Sendable, Hashable {
        public var id: Int
        public var name: String?
        public var url: URL?
    }

    static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    public static func state(status: String?, conclusion: String?) -> CheckState {
        switch status {
        case "queued", "waiting", "requested", "pending": return .pending
        case "in_progress": return .running
        default: break
        }
        switch conclusion {
        case "success": return .passed
        case "failure", "timed_out", "action_required", "startup_failure", "stale": return .failed
        case "cancelled": return .cancelled
        case "skipped", "neutral": return .skipped
        case nil: return status == "completed" ? .passed : .pending
        default: return .failed
        }
    }

    public static func statusState(_ state: String) -> CheckState {
        switch state {
        case "success": .passed
        case "pending": .running
        case "failure", "error": .failed
        default: .pending
        }
    }

    public static func workflowRuns(_ data: Data) throws -> [Int: WorkflowRun] {
        let payload = try JSONDecoder().decode(WorkflowRunsPayload.self, from: data)
        var map: [Int: WorkflowRun] = [:]
        for run in payload.workflow_runs {
            guard let suite = run.check_suite_id else { continue }
            if let existing = map[suite], existing.id > run.id { continue }
            map[suite] = WorkflowRun(id: run.id, name: run.name, url: run.html_url.flatMap(URL.init(string:)))
        }
        return map
    }

    public static func checkRuns(_ data: Data, workflows: [Int: WorkflowRun] = [:]) throws -> [CheckRun] {
        let payload = try JSONDecoder().decode(CheckRunsPayload.self, from: data)
        var latest: [String: (id: Int, run: CheckRun)] = [:]
        for run in payload.check_runs {
            let workflow = run.check_suite?.id.flatMap { workflows[$0] }
            let key = (workflow?.name ?? "") + "\u{0}" + run.name
            if let existing = latest[key], existing.id > run.id { continue }
            let check = CheckRun(
                id: "check:" + String(run.id),
                name: run.name,
                workflow: workflow?.name,
                state: state(status: run.status, conclusion: run.conclusion),
                url: (run.html_url ?? run.details_url).flatMap(URL.init(string:)),
                startedAt: date(run.started_at),
                completedAt: date(run.completed_at),
                runID: workflow?.id,
                source: .check,
                summary: run.output?.title
            )
            latest[key] = (run.id, check)
        }
        return latest.values.map(\.run)
    }

    public static func statuses(_ data: Data) throws -> [CheckRun] {
        let payload = try JSONDecoder().decode(StatusPayload.self, from: data)
        var seen: Set<String> = []
        var out: [CheckRun] = []
        for status in payload.statuses where seen.insert(status.context).inserted {
            let state = statusState(status.state)
            out.append(CheckRun(
                id: "status:" + status.context,
                name: status.context,
                state: state,
                url: status.target_url.flatMap(URL.init(string:)),
                startedAt: date(status.created_at),
                completedAt: state.isFinished ? date(status.updated_at) : nil,
                source: .status,
                summary: status.description
            ))
        }
        return out
    }
}
