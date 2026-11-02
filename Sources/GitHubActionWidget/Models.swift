import Foundation

struct RepoInfo: Decodable, Identifiable, Hashable, Sendable {
    let fullName: String
    let name: String
    let archived: Bool
    let pushedAt: Date?
    var id: String { fullName }
    var owner: String { String(fullName.split(separator: "/").first ?? "") }
}

struct GitHubUser: Decodable, Sendable { let login: String }

struct RunsResponse: Decodable, Sendable { let workflowRuns: [WorkflowRun] }

struct WorkflowRun: Decodable, Identifiable, Hashable, Sendable {
    struct Actor: Decodable, Hashable, Sendable { let login: String }

    let id: Int
    let name: String?
    let displayTitle: String
    let status: String?
    let conclusion: String?
    let headBranch: String?
    let event: String
    let runNumber: Int
    let runStartedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let htmlUrl: URL
    let actor: Actor?

    static let activeStatuses: Set<String> = ["queued", "in_progress", "waiting", "requested", "pending"]

    var isActive: Bool { status.map(Self.activeStatuses.contains) ?? false }
    var isCompleted: Bool { status == "completed" }
    var startDate: Date { runStartedAt ?? createdAt }
    var workflowName: String { name ?? "workflow" }

    var visual: RunVisual {
        switch status {
        case "in_progress": return .running
        case "queued", "waiting", "requested", "pending": return .queued
        default: break
        }
        switch conclusion {
        case "success": return .success
        case "failure", "timed_out", "startup_failure": return .failure
        case "cancelled", "skipped", "stale": return .cancelled
        case "action_required": return .queued
        default: return .neutral
        }
    }
}

enum RunVisual: Sendable {
    case running, queued, success, failure, cancelled, neutral

    var label: String {
        switch self {
        case .running: return L.t("실행 중", "Running")
        case .queued: return L.t("대기 중", "Queued")
        case .success: return L.t("성공", "Succeeded")
        case .failure: return L.t("실패", "Failed")
        case .cancelled: return L.t("취소됨", "Cancelled")
        case .neutral: return L.t("완료", "Completed")
        }
    }
}

struct JobsResponse: Decodable, Sendable { let jobs: [Job] }

struct Job: Decodable, Identifiable, Hashable, Sendable {
    struct Step: Decodable, Hashable, Sendable {
        let name: String
        let status: String
        let conclusion: String?
        let number: Int
    }

    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [Step]?
}

/// 실행 중인 run 의 job/step 진행 요약.
struct RunProgress: Sendable {
    let jobName: String?
    let stepName: String?
    let doneSteps: Int
    let totalSteps: Int
    let doneJobs: Int
    let totalJobs: Int
    /// run 상태가 아직 queued 여도 job 하나라도 돌고 있으면 true
    let anyJobRunning: Bool

    var fraction: Double? { totalSteps > 0 ? Double(doneSteps) / Double(totalSteps) : nil }

    init?(jobs: [Job]?) {
        guard let jobs, !jobs.isEmpty else { return nil }
        let steps = jobs.flatMap { $0.steps ?? [] }
        totalSteps = steps.count
        doneSteps = steps.filter { $0.status == "completed" }.count
        totalJobs = jobs.count
        doneJobs = jobs.filter { $0.status == "completed" }.count
        anyJobRunning = jobs.contains { $0.status == "in_progress" }
        let current = jobs.first { $0.status == "in_progress" } ?? jobs.first { $0.status != "completed" }
        jobName = current?.name
        stepName = current?.steps?.first { $0.status == "in_progress" }?.name
    }

    var caption: String {
        var parts: [String] = []
        if let jobName { parts.append(jobName) }
        if let stepName { parts.append(stepName) }
        let head = parts.isEmpty ? L.t("준비 중", "Starting") : parts.joined(separator: " › ")
        return totalJobs > 1 ? "\(head)  (job \(doneJobs)/\(totalJobs))" : head
    }
}

struct RepoState: Sendable {
    var runs: [WorkflowRun] = []
    var jobs: [Int: [Job]] = [:]
    var error: String?
    var fetchedAt: Date?

    var activeRuns: [WorkflowRun] { runs.filter(\.isActive) }

    /// 워크플로별 최신 완료 run (취소된 건 건너뜀).
    var latestPerWorkflow: [WorkflowRun] {
        var seen = Set<String>()
        var out: [WorkflowRun] = []
        for r in runs where r.isCompleted && r.visual != .cancelled {
            if seen.insert(r.workflowName).inserted { out.append(r) }
        }
        return out
    }

    var isFailing: Bool { latestPerWorkflow.contains { $0.visual == .failure } }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return L.t("\(h)시간 \(m)분", "\(h)h \(m)m") }
        if m > 0 { return L.t("\(m)분 \(s)초", "\(m)m \(s)s") }
        return L.t("\(s)초", "\(s)s")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = L.locale
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 30 { return L.t("방금", "just now") }
        return relative.localizedString(for: date, relativeTo: now)
    }

    static func shortName(_ fullName: String) -> String {
        String(fullName.split(separator: "/").last ?? Substring(fullName))
    }
}
