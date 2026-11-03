# Contributing

Thanks for helping! Bug reports, ideas and pull requests are all welcome.
(한국어로 이슈·PR 을 남겨도 괜찮아요.)

## Before you start

- **Bugs / ideas** → open an issue using the templates.
- **Bigger changes** (new features, UI changes) → open an issue first so we can agree on the approach
  before you spend time on code.
- Small fixes (typos, obvious bugs) can go straight to a PR.

## Local development

Requirements: macOS 14+, Xcode or Command Line Tools (Swift 5.10+), [GitHub CLI](https://cli.github.com) logged in.

```bash
git clone https://github.com/<you>/github-action-widget.git
cd github-action-widget
swift build                                   # compile
./scripts/build-and-install.sh --native       # build the .app, install to ~/Applications and launch
.build/debug/GitHubActionWidget --check cli/cli   # print parsed runs/jobs for a repo, no UI
```

To see the "running" state without waiting for your own CI, watch a busy public repo such as
`vercel/next.js` or `microsoft/vscode`.

UI language follows macOS; to force one while testing:
`defaults write io.github.jundpm.github-action-widget language en` (or `ko`; `defaults delete … language` to reset).

## Rules

The full list (with the code map) is in [`AGENTS.md`](AGENTS.md) — it applies to humans and AI agents alike.
The important ones:

- **No third-party dependencies.** AppKit, SwiftUI and Foundation only.
- **Every user-visible string uses `L.t("한국어", "English")`** — add both languages.
- **Every GitHub request goes through `GitHubClient.get`** so ETag caching keeps API usage near zero.
- **Minimum macOS 14 and Swift 5.10.** CI builds with an older Xcode than you might have locally —
  avoid newest-only syntax (e.g. `weak let`). The CI check must pass before merge.
- Keep PRs focused: one change per PR, with a short description of *why*. Add a screenshot for UI changes.

## Using an AI agent

Claude Code, Codex and similar tools read `AGENTS.md` (Claude Code via `CLAUDE.md`).
Please review what the agent wrote before opening the PR — you're the author.

## Releases (maintainer)

Push a `vX.Y.Z` tag on `main`; the workflow builds the universal app and publishes the GitHub Release.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
