import Foundation
import ServiceManagement

/// 감시 레포 목록·설정·최신 상태를 들고 있고, 주기적으로 GitHub 을 확인한다.
@MainActor
final class Store: ObservableObject {
    enum Overall { case idle, ok, running(Int), failing(Int) }

    private enum Key {
        static let watched = "watchedRepos"
        static let interval = "pollInterval"
        static let notifyComplete = "notifyOnComplete"
        static let failuresOnly = "notifyFailuresOnly"
        static let notifyStart = "notifyOnStart"
        static let onTop = "alwaysOnTop"
        static let collapsed = "panelCollapsed"
        static let panelVisible = "panelVisible"
    }

    private let defaults = UserDefaults.standard
    let client = GitHubClient()

    @Published var watched: [String] { didSet { defaults.set(watched, forKey: Key.watched) } }
    @Published var pollInterval: Double { didSet { defaults.set(pollInterval, forKey: Key.interval) } }
    @Published var notifyOnComplete: Bool { didSet { defaults.set(notifyOnComplete, forKey: Key.notifyComplete) } }
    @Published var notifyFailuresOnly: Bool { didSet { defaults.set(notifyFailuresOnly, forKey: Key.failuresOnly) } }
    @Published var notifyOnStart: Bool { didSet { defaults.set(notifyOnStart, forKey: Key.notifyStart) } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: Key.onTop) } }
    @Published var collapsed: Bool { didSet { defaults.set(collapsed, forKey: Key.collapsed) } }
    @Published var panelVisible: Bool { didSet { defaults.set(panelVisible, forKey: Key.panelVisible) } }

    @Published private(set) var repoStates: [String: RepoState] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var rateRemaining: Int?
    @Published private(set) var account: String?
    @Published private(set) var authError: String?

    /// run id → 마지막으로 본 status. 상태 전이(실행 중 → 완료)를 잡아 알림을 띄운다.
    private var seenStatus: [Int: String] = [:]
    /// 첫 조회를 마친 레포. 첫 조회 때는 알림을 띄우지 않는다.
    private var seeded: Set<String> = []
    private var loop: Task<Void, Never>?

    init() {
        watched = defaults.stringArray(forKey: Key.watched) ?? []
        let saved = defaults.double(forKey: Key.interval)
        pollInterval = saved >= 10 ? saved : 15
        notifyOnComplete = defaults.object(forKey: Key.notifyComplete) as? Bool ?? true
        notifyFailuresOnly = defaults.object(forKey: Key.failuresOnly) as? Bool ?? false
        notifyOnStart = defaults.object(forKey: Key.notifyStart) as? Bool ?? false
        alwaysOnTop = defaults.object(forKey: Key.onTop) as? Bool ?? true
        collapsed = defaults.bool(forKey: Key.collapsed)
        panelVisible = defaults.object(forKey: Key.panelVisible) as? Bool ?? true
    }

    // MARK: - 집계

    var overall: Overall {
        let states = watched.compactMap { repoStates[$0] }
        let running = states.reduce(0) { $0 + $1.activeRuns.count }
        if running > 0 { return .running(running) }
        let failing = states.filter(\.isFailing).count
        if failing > 0 { return .failing(failing) }
        return states.isEmpty ? .idle : .ok
    }

    var activeRuns: [(repo: String, run: WorkflowRun)] {
        watched.flatMap { repo in (repoStates[repo]?.activeRuns ?? []).map { (repo, $0) } }
    }

    // MARK: - 감시 레포

    func isWatched(_ fullName: String) -> Bool { watched.contains(fullName) }

    func setWatched(_ fullName: String, _ on: Bool) {
        if on, !watched.contains(fullName) {
            watched.append(fullName)
            refreshNow()
        } else if !on {
            watched.removeAll { $0 == fullName }
            repoStates[fullName] = nil
            seeded.remove(fullName)
        }
    }

    func moveWatched(from: IndexSet, to: Int) { watched.move(fromOffsets: from, toOffset: to) }

    // MARK: - 조회 루프

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                let wait = self.pollInterval
                try? await Task.sleep(for: .seconds(wait))
            }
        }
        Task { await loadAccount() }
    }

    func refreshNow() { Task { await refreshAll() } }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let repos = watched
        let client = self.client
        await withTaskGroup(of: (String, Result<RepoState, Error>).self) { group in
            for repo in repos {
                group.addTask { (repo, await Self.fetch(repo, client: client)) }
            }
            for await (repo, result) in group where watched.contains(repo) {
                apply(repo: repo, result: result)
            }
        }
        lastRefresh = Date()
        rateRemaining = await client.rateRemaining
        pruneSeen()
    }

    nonisolated private static func fetch(_ repo: String, client: GitHubClient) async -> Result<RepoState, Error> {
        do {
            let runs = try await client.get("/repos/\(repo)/actions/runs?per_page=15", as: RunsResponse.self).workflowRuns
            var jobs: [Int: [Job]] = [:]
            for run in runs where run.isActive {
                jobs[run.id] = try? await client.get(
                    "/repos/\(repo)/actions/runs/\(run.id)/jobs?per_page=50", as: JobsResponse.self
                ).jobs
            }
            return .success(RepoState(runs: runs, jobs: jobs, error: nil, fetchedAt: Date()))
        } catch {
            return .failure(error)
        }
    }

    private func apply(repo: String, result: Result<RepoState, Error>) {
        switch result {
        case .success(let state):
            authError = nil
            if seeded.contains(repo) { detectTransitions(repo: repo, runs: state.runs) }
            for run in state.runs { seenStatus[run.id] = run.status ?? "" }
            seeded.insert(repo)
            repoStates[repo] = state
        case .failure(let error):
            if case GitHubClient.ClientError.noToken = error { authError = error.localizedDescription }
            var state = repoStates[repo] ?? RepoState()
            state.error = error.localizedDescription
            repoStates[repo] = state
        }
    }

    private func detectTransitions(repo: String, runs: [WorkflowRun]) {
        let name = Format.shortName(repo)
        for run in runs {
            let prev = seenStatus[run.id]
            let wasActive = prev.map(WorkflowRun.activeStatuses.contains) ?? false
            // 두 조회 사이에 시작~종료가 다 끝난 run 도 놓치지 않는다
            let finishedUnseen = prev == nil && Date().timeIntervalSince(run.updatedAt) < max(120, pollInterval * 3)
            if run.isCompleted && (wasActive || finishedUnseen) {
                notifyCompletion(repoName: name, run: run)
            } else if prev == nil && run.isActive && notifyOnStart {
                Notifier.shared.post(
                    title: "▶︎ \(name) · \(run.workflowName)",
                    body: "\(run.headBranch ?? "-") · \(L.t("시작됨", "Started"))\n\(run.displayTitle)",
                    url: run.htmlUrl, sound: false)
            }
        }
    }

    private func notifyCompletion(repoName: String, run: WorkflowRun) {
        guard notifyOnComplete else { return }
        let v = run.visual
        if notifyFailuresOnly && v != .failure { return }
        let mark: String
        switch v {
        case .success: mark = "✅"
        case .failure: mark = "❌"
        case .cancelled: mark = "⚪️"
        default: mark = "☑️"
        }
        let took = Format.duration(run.updatedAt.timeIntervalSince(run.startDate))
        Notifier.shared.post(
            title: "\(mark) \(repoName) · \(run.workflowName)",
            body: "\(run.headBranch ?? "-") · \(v.label) · \(took)\n\(run.displayTitle)",
            url: run.htmlUrl, sound: v == .failure)
    }

    private func pruneSeen() {
        guard seenStatus.count > 500 else { return }
        let live = Set(repoStates.values.flatMap { $0.runs.map(\.id) })
        seenStatus = seenStatus.filter { live.contains($0.key) }
    }

    // MARK: - 계정 / 레포 목록

    func loadAccount() async {
        do {
            account = try await client.get("/user", as: GitHubUser.self).login
            authError = nil
        } catch {
            authError = error.localizedDescription
        }
    }

    /// 내가 접근할 수 있는 레포(개인 + 조직), 최근 push 순.
    func fetchRepos() async throws -> [RepoInfo] {
        var all: [RepoInfo] = []
        for page in 1...5 {
            let batch = try await client.get(
                "/user/repos?per_page=100&sort=pushed&page=\(page)", as: [RepoInfo].self)
            all += batch
            if batch.count < 100 { break }
        }
        rateRemaining = await client.rateRemaining
        return all.filter { !$0.archived }
    }

    // MARK: - 로그인 시 자동 실행

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }
}
