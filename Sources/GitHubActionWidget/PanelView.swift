import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var store: Store
    let openSettings: () -> Void
    let hidePanel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.collapsed {
                Divider().opacity(0.5)
                content
            }
        }
        .frame(minWidth: 260, maxWidth: .infinity, minHeight: 40, maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground())
        .ignoresSafeArea()
    }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 8) {
            GitHubMarkShape()
                .fill(Color.primary)
                .frame(width: 15, height: 15)
            Text("Actions")
                .font(.system(size: 13, weight: .semibold))
            SummaryChip(overall: store.overall)
            Spacer(minLength: 4)
            HeaderButton(symbol: "arrow.clockwise", help: L.t("지금 새로고침", "Refresh now"), spinning: store.isRefreshing) {
                store.refreshNow()
            }
            HeaderButton(symbol: "gearshape", help: L.t("설정", "Settings"), action: openSettings)
            HeaderButton(symbol: store.collapsed ? "chevron.down" : "chevron.up",
                         help: store.collapsed ? L.t("펼치기", "Expand") : L.t("접기", "Collapse")) {
                store.collapsed.toggle()
            }
            HeaderButton(symbol: "xmark", help: L.t("패널 숨기기 (메뉴바에서 다시 열기)", "Hide panel (reopen from the menu bar)"), action: hidePanel)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    // MARK: 본문

    @ViewBuilder
    private var content: some View {
        if let err = store.authError {
            Notice(symbol: "key.slash", text: err)
        } else if store.watched.isEmpty {
            VStack(spacing: 8) {
                Text(L.t("볼 레포를 아직 고르지 않았어요", "No repositories selected yet"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(L.t("레포 선택…", "Choose repositories…"), action: openSettings)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.watched, id: \.self) { repo in
                        RepoSection(repo: repo, state: store.repoStates[repo])
                    }
                }
                .padding(.vertical, 6)
            }
            footer
        }
    }

    private var footer: some View {
        HStack {
            if let last = store.lastRefresh {
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    Text(L.t("확인 \(Format.ago(last, now: ctx.date)) · \(Int(store.pollInterval))초마다", "Checked \(Format.ago(last, now: ctx.date)) · every \(Int(store.pollInterval))s"))
                }
            }
            Spacer()
            if let rate = store.rateRemaining {
                Text(verbatim: "API \(rate)")
                    .help(L.t("남은 GitHub API 요청 한도 (시간당 5,000)", "Remaining GitHub API requests (5,000 per hour)"))
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - 레포 섹션

private struct RepoSection: View {
    let repo: String
    let state: RepoState?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(Format.shortName(repo))
                    .font(.system(size: 12, weight: .semibold))
                if let err = state?.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .help(err)
                }
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/\(repo)/actions") { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(L.t("GitHub Actions 열기", "Open GitHub Actions"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            if let state {
                let active = state.activeRuns
                if !active.isEmpty {
                    ForEach(active) { run in RunRow(run: run, progress: RunProgress(jobs: state.jobs[run.id])) }
                } else if !state.latestPerWorkflow.isEmpty {
                    ForEach(state.latestPerWorkflow.prefix(3)) { run in RunRow(run: run, progress: nil) }
                } else if state.error == nil {
                    Text(L.t("실행 기록 없음", "No runs yet"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            } else {
                ProgressView().controlSize(.small).padding(.horizontal, 12).padding(.vertical, 4)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - run 한 줄

private struct RunRow: View {
    let run: WorkflowRun
    let progress: RunProgress?
    @State private var hover = false

    var body: some View {
        Button { NSWorkspace.shared.open(run.htmlUrl) } label: {
            HStack(alignment: .top, spacing: 8) {
                StatusIcon(visual: progress?.anyJobRunning == true ? .running : run.visual)
                    .frame(width: 14, height: 14)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(run.workflowName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        timeText
                    }
                    Text(verbatim: "\(run.headBranch ?? "-") · #\(run.runNumber) · \(run.displayTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if run.isActive {
                        Text(progress?.caption ?? run.visual.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        if let f = progress?.fraction {
                            ProgressView(value: f)
                                .progressViewStyle(.linear)
                                .tint(.orange)
                                .controlSize(.mini)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(hover ? Color.primary.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L.t("GitHub 에서 이 실행 열기", "Open this run on GitHub"))
    }

    @ViewBuilder
    private var timeText: some View {
        Group {
            if run.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Format.duration(ctx.date.timeIntervalSince(run.startDate)))
                        .monospacedDigit()
                }
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("\(Format.duration(run.updatedAt.timeIntervalSince(run.startDate))) · \(Format.ago(run.updatedAt, now: ctx.date))")
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

// MARK: - 작은 부품들

struct StatusIcon: View {
    let visual: RunVisual

    var body: some View {
        switch visual {
        case .running: Spinner()
        case .queued: symbol("clock.fill", .orange)
        case .success: symbol("checkmark.circle.fill", .green)
        case .failure: symbol("xmark.circle.fill", .red)
        case .cancelled: symbol("slash.circle", .secondary)
        case .neutral: symbol("minus.circle", .secondary)
        }
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).resizable().scaledToFit().foregroundStyle(color)
    }
}

private struct Spinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let angle = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            Circle()
                .trim(from: 0.08, to: 0.82)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(angle))
                .padding(1)
        }
    }
}

private struct SummaryChip: View {
    let overall: Store.Overall

    var body: some View {
        let (text, color): (String, Color) = {
            switch overall {
            case .running(let n): return (L.t("실행 중 \(n)", "\(n) running"), .orange)
            case .failing(let n): return (L.t("실패 \(n)", "\(n) failing"), .red)
            case .ok: return (L.t("정상", "All good"), .green)
            case .idle: return ("", .clear)
            }
        }()
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

private struct Notice: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.yellow)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
