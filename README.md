# Scanner

iPhone document scanner that competes above Apple's free camera-and-crop layer: verification before
export, on-device OCR and classification, open export. Sold once (199 MXN), no subscription, no account,
no server. Working name — see `docs/mvp-plan.md` §9.

**Start here:** [AGENTS.md](AGENTS.md) (rules, layout, how we work) → [docs/roadmap.md](docs/roadmap.md) (status, what's next).

- Plan and decisions: `docs/mvp-plan.md`
- Product docs: `docs/first-principles-review.md`, `docs/prd-scanflow-v0.1.md`

## Build

```sh
brew install xcodegen          # once
xcodegen generate              # project.yml is the source of truth; Scanner.xcodeproj is gitignored
open Scanner.xcodeproj
```

Device builds need your team: `cp Config/Local.xcconfig.example Config/Local.xcconfig` and fill it in.

```sh
xcodebuild -scheme Scanner -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Scanner -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Layout

```
App/            app target (SwiftUI): Home → Review → export
Packages/
  ScannerCore     domain model: ScanDocument, ScanPage, recognition types, ExportPreset
  CaptureKit      capture sources (M0: VisionKit stand-in; M3: custom AVFoundation + Vision camera)
  ImagePipeline   downscale + JPEG encode for export presets
  Recognition     on-device OCR (Vision RecognizeTextRequest)
  Export          searchable PDF (image + invisible text layer)
  Telemetry       PRD §12 events — enum payloads only, so document content cannot leak
  DesignSystem    tokens + the "processed on your iPhone" badge
Tests/          unit tests over rendered fixture pages (never real documents)
```
