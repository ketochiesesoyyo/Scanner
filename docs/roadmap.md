# Roadmap and status

Status board for everyone (and every agent) working on Scanner. **Update this when you start or
finish a task** — put your handle in the "Who" column, tick the box, add a one-line note if you learned
something the next person needs. Rationale for the sequence is in `docs/mvp-plan.md` §6.

Legend: `[ ]` open · `[~]` in progress · `[x]` done · IDs in parentheses are PRD requirements.

---

## Now → M1 · Records & trust

Goal: a scan survives app termination, lives in a local library, and the user can see and control where
their data is. Nothing leaves the device.

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [ ] M1.1 | **Persistence models** in `ScannerCore`: SwiftData `ScanRecord` / `PageRecord` referencing files on disk; `FileStore` under Application Support with `.completeFileProtection` (CAP-04, §9 Security) | | Round-trip test: save a 3-page document, reload, originals byte-identical. Files carry complete protection attribute. |
| [ ] M1.2 | **Write-ahead capture session**: each page is written to disk the moment it arrives; an interrupted session is restored on next launch (§9 Reliability, spike 4) | | Test: kill the process mid-session (simulate by discarding the in-memory model), relaunch, session and page order intact. |
| [ ] M1.3 | **Library screen**: list of scans with thumbnail, title, date, page count; rename, delete; open into Review | | 100 scans scroll smoothly on the simulator; delete removes files, not just the record. |
| [ ] M1.4 | **Thumbnails** generated at capture (long side ≈ 400 px) and stored as derivatives; Review grid stops decoding full-res originals | | Review of a 25-page document stays under 150 MB resident on device. |
| [ ] M1.5 | **Export formats + size estimate**: JPEG (one file per page, zipped when >1) and TXT alongside PDF; estimated output size per preset shown before export (EXP-01, EXP-02) | | Estimate within ±15% of the actual file for the fixture pages. |
| [ ] M1.6 | **Save to Files** via `fileExporter` in addition to the share sheet (EXP-01) | | Exported PDF opens in Files and is searchable there. |
| [ ] M1.7 | **Face ID lock + Settings**: optional biometric lock (LocalAuthentication), "Delete everything", processing explanation screen (§9 Security, §10) | | Lock engages on background→foreground; delete leaves no files in Application Support or tmp. |
| [ ] M1.8 | **Copy and privacy pass**: every screen that processes shows `ProcessingBadge`; export button copy says what it does; no dead ends | | Walkthrough checklist in PR description. |

Definition of done for M1: all boxes ticked, tests green, `docs/mvp-plan.md` §5 rows for CAP-04, EXP-01, EXP-02, Privacy, Library, Recovery marked implemented.

## Next → M2 · Verification & understanding

Goal: the app tells you when a scan is not good enough or incomplete, and suggests what it is.

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [ ] M2.1 | `QualityScorer` in `Recognition`: blur (Laplacian variance), glare (% clipped highlights), shadow (luma gradient), readability (share of low-confidence OCR words) (QLT-01) | | Scores computed per page off-main; unit tests with synthetic blurred/glared fixtures. |
| [ ] M2.2 | Per-class thresholds + `QualityWarning` model; iOS 26 `DetectLensSmudgeRequest` behind `#available` | | Warnings fire on the bad fixtures, not on the clean ones. |
| [ ] M2.3 | Duplicate pages via `GenerateImageFeaturePrintRequest` distance; page-sequence check from OCR ("3 de 7", "Page 3 of 7") (QLT-02) | | Duplicate fixture flagged; reordered fixture flagged; never auto-deleted or reordered. |
| [ ] M2.4 | **Verification summary** on Review: page count, flagged pages with reason, one tap to the page; non-color indicators (§9 Accessibility) | | VoiceOver reads each warning; ignoring a warning is possible and logged as `quality_warning_resolved(ignore)`. |
| [ ] M2.5 | `DocumentClassifier` (rule-based): Mexico-first vocabulary (RFC, CURP, INE, CFDI/factura, recibo, comprobante de domicilio, acta, contrato, nómina) + English; `NSDataDetector` for dates/amounts (CLS-01) | | Fixture set of 20 rendered docs classified ≥ 80% correctly; output is a suggestion the user can change. |
| [ ] M2.6 | Filename + title suggestion `{type}-{party}-{yyyy-MM-dd}`; editable before export | | Suggested name appears on Review; export uses the edited name. |
| [ ] M2.7 | Fixture corpus: ~50 rendered pages across sizes/fonts/rotations with expected labels under `Tests/Fixtures/` (§14) | | Corpus documented in `Tests/README.md`; no real personal documents. |
| [ ] M2.8 | iOS 26 `RecognizeDocumentsRequest` spike: does document structure improve classification? (spike 5) | | Short write-up appended to this file under "Learnings". |

## Later → M3 · Real capture (replaces the VisionKit stand-in)

Goal: CAP-01 and CAP-04 for real — live guidance, auto-capture, untouched originals.

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [ ] M3.1 | `CaptureKit` AVFoundation session + SwiftUI preview; full-res still capture | | Camera opens ≤ 1.0 s on iPhone XR-class device (§9 Performance). |
| [ ] M3.2 | Live quad from `DetectDocumentSegmentationRequest` per frame; overlay; stability/framing/lighting gates; **auto-capture** with manual override (CAP-01, spike 2) | | Letter page scans hands-free in normal light without corner correction ≥ 85% of attempts (§11). |
| [ ] M3.3 | Guidance chips ("move closer", "more light", "hold still", "corner missing") + volume-button shutter (§9 Accessibility) | | Chips are announced by VoiceOver. |
| [ ] M3.4 | Corner editor + CoreImage perspective correction + filters (color / grayscale / B&W) in `ImagePipeline`; quad and filter stored as parameters, original untouched (CAP-02, CAP-04) | | Re-editing corners regenerates from the original with no generation loss. |
| [ ] M3.5 | Multi-page session UX: continuous capture, reorder, delete, insert, recapture (CAP-03) | | 25-page document corrected without restarting. |
| [ ] M3.6 | Remove `DocumentCameraView` stand-in; keep Photos import as an entry point | | No VisionKit camera left in the app target. |

## Later → M4 · Ship readiness

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [ ] M4.1 | Localization es-MX + en via String Catalog; OCR languages es + en confirmed on device | | All UI strings localized; screenshots in both. |
| [ ] M4.2 | Accessibility audit: VoiceOver, Dynamic Type, contrast, non-color warnings, volume-button capture (§17 Accessibility) | | Audit checklist committed with results. |
| [ ] M4.3 | Control Center / Lock Screen control (`ControlWidget`) + App Intent "Scan document" (§7 entry points) | | Control launches straight into capture. |
| [ ] M4.4 | App Store: name (owner decision), icon, screenshots that lead with verification/OCR/privacy, description in es-MX + en, privacy nutrition label "Data Not Collected", price 199 MXN base MX, Family Sharing on, Small Business Program | | Listing reviewed by owner. |
| [ ] M4.5 | Launch gates from PRD §17 walked and recorded here | | All seven gates have evidence links. |
| [ ] M4.6 | TestFlight beta 100–300 users; baseline the §11 metrics from `LogSink`-equivalent local counters (no vendor yet) | | Baseline table added under "Learnings". |

## After launch (P1, in this order — see plan §6)

1. Sign-and-return forms (ACT-01) — fully on-device, no integrations.
2. Receipt field extraction (OCR-02): merchant, date, total, tax.
3. ID front/back pairing with glare warning and stricter defaults.
4. Folders, tags, full-text search, retention controls (ORG-01).
5. Photo archive mode: multi-frame glare reduction, original + enhanced, back-of-photo pairing (PHT-01…03).
6. Share extension (import images/PDFs from other apps).

---

## Done

### M0 · Walking skeleton — 2026-08-31

- [x] xcodegen project, iOS 18, iPhone-only, Swift 6, local SPM packages, gitignored signing.
- [x] `Recognition.TextRecognizer`: Vision `RecognizeTextRequest`, es→en, per-word boxes and confidence.
- [x] `Export.SearchablePDFBuilder`: image + invisible text layer at OCR boxes; Email/Standard/Archive presets.
- [x] `CaptureKit.DocumentCameraView` (VisionKit stand-in) + Photos import.
- [x] `Telemetry`: PRD §12 events with enum-only payloads; `NoOpSink` default, `LogSink` in DEBUG.
- [x] App: Home → Review (per-page OCR status) → Page detail → export → share sheet.
- [x] Tests: 6 passing — searchable-PDF alignment within 3% (spike 1 ✅), OCR round trip, presets, page sizing.

## Learnings

- **Spike 1 (searchable PDF)**: CoreText `CTLineDraw` with `setTextDrawingMode(.invisible)` produces a text
  layer PDFKit can find and select; sizing the font so ascent+descent = box height and stretching the
  text matrix to the box width keeps selection aligned within 3%. No PDFKit or UIKit needed in `Export`.
- Vision only accepts its own language identifiers (`es-ES`, not `es-MX`); `TextRecognizer.resolve` maps
  by language code. On the iOS 26 simulator `VNDocumentCameraViewController.isSupported` returns `true`
  even though there is no camera.

## Open questions (for the owner)

See `docs/mvp-plan.md` §9: app name (ScanFlow is taken), bundle ID / developer account, territories,
Family Sharing, languages, analytics vendor, and confirmation that monetization is paid-upfront.
Add new questions here; don't block on them if a sensible default exists.
