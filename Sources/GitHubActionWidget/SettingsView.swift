import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var repos: [RepoInfo] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var query = ""
    @State private var loginError: String?

    private var filtered: [RepoInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? repos : repos.filter { $0.fullName.lowercased().contains(q) }
        // 선택한 레포를 위로
        return base.sorted { store.isWatched($0.fullName) && !store.isWatched($1.fullName) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                GitHubMarkShape().fill(Color.primary).frame(width: 18, height: 18)
                Text("GitHub Action Widget").font(.headline)
                Spacer()
                if let account = store.account {
                    Text(verbatim: "@\(account)").font(.caption).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField(L.t("레포 검색", "Search repositories"), text: $query)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await load() }
                        } label: { Image(systemName: "arrow.clockwise") }
                            .help(L.t("레포 목록 다시 불러오기", "Reload repositories"))
                            .disabled(loading)
                    }
                    if loading && repos.isEmpty {
                        ProgressView(L.t("레포 목록 불러오는 중…", "Loading repositories…")).frame(maxWidth: .infinity, minHeight: 240)
                    } else if let loadError {
                        Text(loadError).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    } else {
                        List(filtered) { repo in
                            Toggle(isOn: Binding(
                                get: { store.isWatched(repo.fullName) },
                                set: { store.setWatched(repo.fullName, $0) }
                            )) {
                                HStack {
                                    Text(repo.name)
                                    Text(repo.owner).font(.caption).foregroundStyle(.tertiary)
                                    Spacer()
                                    if let pushed = repo.pushedAt {
                                        Text(Format.ago(pushed)).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                        .listStyle(.bordered(alternatesRowBackgrounds: true))
                        .frame(height: 260)
                    }
                    Text(L.t("선택 \(store.watched.count)개 · 패널에는 선택한 순서대로 보여요", "\(store.watched.count) selected · shown in the panel in the order you pick them"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            } label: {
                Text(L.t("볼 레포", "Repositories"))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $store.pollInterval, in: 10...120, step: 5) {
                        Text(L.t("확인 간격  \(Int(store.pollInterval))초", "Check every  \(Int(store.pollInterval))s"))
                    }
                    Toggle(L.t("실행이 끝나면 알림", "Notify when a run finishes"), isOn: $store.notifyOnComplete)
                    Toggle(L.t("실패했을 때만 알림", "Only for failures"), isOn: $store.notifyFailuresOnly)
                        .disabled(!store.notifyOnComplete)
                        .padding(.leading, 18)
                    Toggle(L.t("실행이 시작될 때도 알림", "Also notify when a run starts"), isOn: $store.notifyOnStart)
                    Toggle(L.t("패널을 항상 위에 띄우기", "Keep panel on top"), isOn: $store.alwaysOnTop)
                    Toggle(L.t("로그인할 때 자동 실행", "Launch at login"), isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { on in
                            do { try store.setLaunchAtLogin(on); loginError = nil }
                            catch { loginError = error.localizedDescription }
                        }
                    ))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(L.t("동작", "Behavior"))
            }

            HStack {
                Text(L.t("토큰: 이 맥의 gh 로그인을 사용", "Token: uses this Mac's gh login"))
                Spacer()
                if let rate = store.rateRemaining { Text(L.t("남은 API 한도 \(rate)/5000", "API quota left \(rate)/5000")) }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 460)
        .task { if repos.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            repos = try await store.fetchRepos()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
