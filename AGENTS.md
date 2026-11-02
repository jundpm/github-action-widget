# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, …) working in this repository —
either **installing the app for a user** or **changing the code**.

## Installing for a user

Goal: the user ends up with "GitHub Action Widget" running in their menu bar, showing their repos.

1. Check prerequisites; stop and tell the user if one fails:
   - `sw_vers -productVersion` → must be 14 or later.
   - `gh auth status --hostname github.com` → must be logged in. The app has **no login screen**;
     it reads its token from `gh auth token`. If missing: `brew install gh`, then ask the user to run
     `gh auth login` themselves (interactive — do not try to automate it).
2. Install (pick one):
   - Prebuilt release (default): `curl -fsSL https://raw.githubusercontent.com/jundpm/github-action-widget/main/install.sh | bash`
   - From source (if the user prefers, or no release exists yet): `./scripts/build-and-install.sh --native`
     (needs Xcode or Command Line Tools; `--native` skips the slower universal build).
3. Verify: `pgrep -x GitHubActionWidget` prints a PID. Tell the user to look for the icon in the menu bar
   and that Settings opens automatically on first launch to pick repositories.
4. Optional, only if the user asks — preselect repos without the UI:
   `defaults write io.github.jundpm.github-action-widget watchedRepos -array owner/repo1 owner/repo2`
   then restart the app (`pkill -x GitHubActionWidget; open ~/Applications/"GitHub Action Widget.app"`).

Troubleshooting:
- Panel shows "No GitHub token" → `gh auth login`, then click refresh in the panel.
- "App can't be opened / unidentified developer" → `xattr -dr com.apple.quarantine ~/Applications/"GitHub Action Widget.app"`
  (install.sh already does this; the app is ad-hoc signed, not notarized).
- No notifications → System Settings › Notifications › GitHub Action Widget → allow.
- Uninstall: `pkill -x GitHubActionWidget; rm -rf ~/Applications/"GitHub Action Widget.app"; defaults delete io.github.jundpm.github-action-widget`

## Working on the code

- Build: `swift build` · run the app bundle: `./scripts/build-and-install.sh --native`
- Diagnose API parsing without UI: `.build/debug/GitHubActionWidget --check owner/repo`
- Release: push a `vX.Y.Z` tag → `.github/workflows/release.yml` builds the universal zip and publishes a Release.
  Keep the asset name `GitHubActionWidget.zip` — install.sh downloads `releases/latest/download/GitHubActionWidget.zip`.

Layout (`Sources/GitHubActionWidget/`):

| File | Role |
|---|---|
| `App.swift` | entry point, AppDelegate, CLI flags (`--check`, `--export-preview`) |
| `Store.swift` | watched repos, settings (UserDefaults), polling loop, run state transitions → notifications |
| `GitHubClient.swift` | REST client; token from `gh auth token`; ETag / `If-None-Match` caching |
| `Models.swift` | API models, `RunVisual`, `RunProgress`, formatting |
| `PanelController.swift` / `PanelView.swift` | floating non-activating panel + its SwiftUI content |
| `StatusItemController.swift` | menu bar icon (badge/pulse) and menu |
| `SettingsView.swift` | repo picker and preferences |
| `GitHubMark.swift` | vector mark + tiny SVG path parser used for the menu bar icon |
| `L10n.swift` | Korean/English strings |

Rules:
- **No third-party dependencies.** AppKit + SwiftUI + Foundation only.
- **Every user-visible string goes through `L.t("한국어", "English")`** — both languages, same meaning.
- **Keep polling cheap.** Every GitHub request must go through `GitHubClient.get` so ETag caching applies
  (304 responses don't count against the 5,000 req/h limit). Don't add per-poll requests for idle repos.
- The token must only ever be sent to `api.github.com`. Never log or persist it.
- Minimum macOS is 14; don't use newer-only APIs without an availability check.
- App icon source is `Resources/AppIcon.svg`; after editing it run `./scripts/make-icon.sh` and commit the regenerated
  `Resources/AppIcon.icns` and `docs/icon.png`.
