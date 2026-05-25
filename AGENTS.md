# Agent Instructions — SwiftUIAdmob

For any AI coding agent (Claude Code, Cursor, Copilot, Codex, OpenCode,
Aider, …) editing this repository.

If you are integrating this package into a host app, read
**`docs/AI_USAGE.md`** instead — this file is for repo maintainers.

## Repository Status

- **Version**: 1.0.1, released. Public API is **stable** — do not rename,
  remove, or change signatures without an explicit user request to bump the
  major version.
- **Platform**: iOS 26 minimum, Swift 6 with strict concurrency. Do not
  lower either bound.
- **Dependency**: Google Mobile Ads SDK 13.3.0 (pinned via SPM). Do not
  upgrade without an explicit request — Google releases can introduce
  policy or behavioural changes that the package must absorb.

## Hard Rules

1. **Do not break public API**. Source-compatible additions are fine.
   Renames, removed cases, changed argument labels are not.
2. **Tests use fakes only**. Never write a test that actually contacts
   Google's ad servers. `FakeMobileAdsBridge` / `FakeConsentBridge` cover
   the testable surface — extend them rather than calling into
   `GoogleMobileAds` from tests.
3. **Do not absorb host responsibilities**. `Info.plist`,
   `ATTrackingManager` prompts, ad placement policy, App Store Connect
   privacy disclosures all belong to the host app. The package documents
   them in `docs/HOST_APP_SETUP.md`; it does not own them.
4. **Do not hard-code adaptive banner heights**. `AdmobBanner` is fixed
   320x50 and `AdmobVerticalBanner` is fixed 120x600 — those constants are
   fine. `AdmobAdaptiveBanner` has a dynamic 50–150pt height; use
   `AdmobAdaptiveBanner.height(forWidth:)` or rely on
   `.adAdaptiveBanner(_:)` so `safeAreaInset` handles layout.
5. **`@MainActor` everywhere user-facing**. Bootstrapper, coordinators,
   controllers, banner — all `@MainActor`. SDK delegate callbacks come in
   off the main actor; hop via `Task { @MainActor in ... }` before touching
   isolated state (see `FullScreenDelegateBridge`).
6. **Reward delivery comes from the SDK callback only**. The package
   returns `AdmobReward?` from `present()` precisely to enforce this —
   don't add convenience helpers that grant rewards elsewhere.
7. **No raw ad unit IDs in production logs**. `AdmobLogger` already
   complies; preserve that property in any new logging.

## When Editing

- Read `docs/ARCHITECTURE.md` for design rationale before structural changes.
- If you change public API behaviour, **update `docs/AI_USAGE.md` and
  `docs/LLM_CONTEXT.md` in the same change**. Stale docs are worse than
  no docs — AI agents will follow them.
- Add a `CHANGELOG.md` entry under an `## [Unreleased]` heading if one
  doesn't exist.
- Snippet examples in `docs/AI_USAGE.md` are compile-checked in
  `Tests/SwiftUIAdmobTests/UsageExamplesTests.swift`. If you change a public
  signature, that file will fail to build — fix the example, not the test.

## Verification Before "Done"

Run from the repo root:

```bash
swift build
swift test
```

Both must pass. If you cannot run them locally, say so explicitly — do not
claim verification you didn't perform.

## Out of Scope for v1.0.x

- Native ads (deferred to a later milestone).
- A sample/example app target (see `docs/AI_USAGE.md` snippets instead).
- Type-state APIs (`Loaded` / `Unloaded` phantom types) — under
  consideration for a v2 advanced API surface.

## Cross-Agent Convention

Claude Code reads `CLAUDE.md`; many other agents (Cursor, Copilot, Codex,
OpenCode, Aider) read `AGENTS.md`. This repository keeps the canonical
content here and has `CLAUDE.md` redirect to it.
