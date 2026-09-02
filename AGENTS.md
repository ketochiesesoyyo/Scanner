# Scanner — guide for people and their coding agents

Read this first. It tells you what this project is, what is non-negotiable, where the plan lives,
and how to work in the repo without breaking what others rely on. Keep it current: when a fact
here changes, change it in the same PR.

## What we are building

An iPhone document scanner that competes **above** Apple's free camera-and-crop layer:
verification before export, on-device OCR and classification, open export (PDF/JPEG/text, no
watermark). **Sold once for 199 MXN. No subscription, no account, no server.**

Positioning: *Scan it. Verify it. Send it where it belongs.* Documents first; photo archival is a
later, differentiated mode.

- Working name: `Scanner` (bundle ID `mx.scanner.app`). "ScanFlow" in the PRD is taken on the App
  Store; the real name is an owner decision (see `docs/mvp-plan.md` §9).
- Owner: ketochi (GitHub `ketochiesesoyyo`). Decisions listed in `docs/mvp-plan.md` §9 are theirs;
  don't change name, bundle ID, pricing, territories, languages or analytics vendor without them.

## Where the truth lives (in precedence order)

1. `docs/mvp-plan.md` — the reconciled plan: scope, architecture, milestones, decisions and their
   rationale. If it conflicts with the PRD, the plan wins (the PRD's freemium tiers are overridden
   by paid-upfront; see plan §2).
2. `docs/roadmap.md` — **what's done, what's in progress, what's next**, as pickable tasks. Update it
   when you start or finish something.
3. `docs/prd-scanflow-v0.1.md` — requirements (IDs like CAP-01, QLT-01, OCR-01, EXP-02). Reference
   these IDs in PRs and commit messages.
4. `docs/first-principles-review.md` — why the product exists; read once.

## Non-negotiables (from the PRD; enforce them in review)

- **On-device only.** No network calls, no cloud OCR, no third-party SDKs. If a feature truly needs
  the cloud, it is not MVP and needs an explicit, labeled disclosure designed first.
- **Originals are immutable** (CAP-04). Store the capture as delivered plus parameters (quad, filter);
  render derivatives. Never overwrite the source.
- **Never fabricate document content.** OCR/classification are suggestions with visible confidence.
  No generative reconstruction of text, signatures, stamps, totals or identity fields.
- **Warn, don't auto-fix** (QLT-02). Quality/duplicate/sequence checks flag; the user decides.
- **Open export** (EXP-01). Standard PDF/JPEG/TXT, no watermark, works offline, via share sheet/Files.
- **Telemetry carries no content.** `TelemetryEvent` payloads are enums and numbers only, by design.
  Never add a `String` payload. Ship with `NoOpSink`; `LogSink` is DEBUG-only.
- **Every processing screen shows the processing label** (`ProcessingBadge`, PRD §10).
- **No StoreKit / paywall / tiers.** Paid-upfront means the whole app is the product.

## Repo layout and package boundaries

```
project.yml          xcodegen source of truth. Scanner.xcodeproj is GENERATED and gitignored.
App/                 SwiftUI app target: navigation, screens, App Intents/Control widget (later).
Packages/
  ScannerCore        Domain model only (ScanDocument, ScanPage, recognition types, ExportPreset).
                     M1 adds persistence here (SwiftData models, session store, file store).
                     No UI, no Vision, no UIKit.
  CaptureKit         Capture sources. Today: VisionKit stand-in + UIImage upright helper.
                     M3: AVFoundation + Vision live capture (quad, guidance, auto-capture).
  ImagePipeline      Derivative rendering: downscale/encode today; perspective correction + filters in M3.
  Recognition        On-device intelligence: OCR today; quality scoring, duplicates, classification in M2.
  Export             PDF with invisible text layer; JPEG/TXT bundles and size estimates in M1.
  Telemetry          PRD §12 events + sinks. Enum-only payloads.
  DesignSystem       Tokens (DS.Spacing) and shared components (ProcessingBadge).
Tests/ScannerTests   Unit tests. Fixture pages are RENDERED (Fixtures.swift); never commit real documents.
docs/                Product docs, plan, roadmap.
Config/              Signing.xcconfig (committed) includes Local.xcconfig (gitignored, your team ID).
```

Dependency direction: `App → everything`; `Export → ImagePipeline → ScannerCore`;
`Recognition → ScannerCore`; `CaptureKit → ScannerCore`; `Telemetry` and `DesignSystem` depend on
nothing. Don't add upward or sideways dependencies without a note in the PR.

## Build, run, test

First time on a fresh Mac? `SETUP.md` at the repo root walks through everything from zero.

```sh
brew install xcodegen                                  # once
cp Config/Local.xcconfig.example Config/Local.xcconfig # once, for device builds; fill in your team
xcodegen generate                                      # after pulling or adding files; regenerates Scanner.xcodeproj
xcodebuild -scheme Scanner -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Scanner -destination 'platform=iOS Simulator,name=iPhone 17' test
```

- Toolchain: Xcode 26.x, Swift 6 language mode (strict concurrency), deployment target iOS 18.0.
  iOS 26-only APIs (`RecognizeDocumentsRequest`, `DetectLensSmudgeRequest`) go behind `#available`.
- New source files under `App/` or a package's `Sources/` are picked up automatically after
  `xcodegen generate`. New packages must be added to `project.yml` (`packages:` and the target's
  `dependencies:`).
- The simulator has no document camera; use **Import from Photos** to exercise the pipeline.
  The unit tests cover OCR → PDF end to end and run in the simulator.
- Bump `CURRENT_PROJECT_VERSION` in `project.yml` on every App Store Connect upload.

## How we work

- Branch per task: `m1/session-store`, `m2/quality-scorer`. Small PRs against `main`.
- Commit/PR titles start with the milestone and name the PRD IDs: `M1: write-ahead session store (CAP-03, §9 Reliability)`.
- Before opening a PR: builds with **zero warnings in our code**, `xcodebuild test` green, new behavior
  has a test where it can be tested without a device, `docs/roadmap.md` updated (tick the task,
  note anything you learned).
- Definition of done for a task: acceptance criterion in the roadmap/PRD met, processing label present
  on any new processing screen, no content in telemetry, originals untouched.
- Swift style: no force unwraps outside tests; `Sendable` value types across package boundaries;
  `@MainActor` on UI-facing models; heavy work off the main actor (`Task.detached` or nonisolated
  async functions). Prefer Apple frameworks over dependencies — the MVP has none.
- UI strings are English source keys for now; es-MX localization lands in M4 via a String Catalog.
  Write user-facing copy in plain language; say what happens ("Export searchable PDF"), not how.
- Keep `docs/mvp-plan.md` for *why*; keep `docs/roadmap.md` for *status*. Don't fork the plan into
  new documents — extend these.

## If you are an AI agent

- Start by reading `docs/roadmap.md` → "Now". Pick an unassigned task or continue the one your human
  named. Write your name/handle next to it when you start; tick it when done.
- Don't change scope: no cloud features, no StoreKit, no new third-party dependencies, no renames.
  If a task seems to need one of those, stop and leave a note in the roadmap's "Open questions".
- Don't regenerate or commit `Scanner.xcodeproj`, `App/Info.plist`, `Config/Local.xcconfig`, or `build/`.
- Verify with the commands above before claiming something works. The simulator can't scan; say so.
