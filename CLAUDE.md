# CLAUDE.md

See **[`AGENTS.md`](AGENTS.md)** — the canonical instructions for any AI
agent (Claude Code included) editing this repository.

For host-app integration help, read **[`docs/AI_USAGE.md`](docs/AI_USAGE.md)**.

## Quick reminders (also in AGENTS.md)

- Public API is **stable at v1.0.0** — no renames or signature changes.
- Tests use `FakeMobileAdsBridge` / `FakeConsentBridge` — never hit live
  Google ad servers.
- iOS 26 / Swift 6 strict concurrency are fixed; do not lower.
- Do not absorb host responsibilities (`Info.plist`, ATT, placement
  policy). They live in `docs/HOST_APP_SETUP.md`.
- If you change public usage, update `docs/AI_USAGE.md` and
  `docs/LLM_CONTEXT.md` in the same change.
- Run `swift build && swift test` before declaring work done.
