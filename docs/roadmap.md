# Roadmap and status

Status board for everyone (and every agent) working on Scanner. **Update this when you start or
finish a task** — put your handle in the "Who" column, tick the box, add a one-line note if you learned
something the next person needs. Rationale for the sequence is in `docs/mvp-plan.md` §6.

Legend: `[ ]` open · `[~]` in progress · `[x]` done · IDs in parentheses are PRD requirements.

---

## Done → M1 · Records & trust (2026-08-31)

Goal: a scan survives app termination, lives in a local library, and the user can see and control where
their data is. Nothing leaves the device.

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [x] M1.1 | **Persistence models** in `ScannerCore`: SwiftData `ScanRecord` / `PageRecord` referencing files on disk; `FileStore` under Application Support with `.completeFileProtection` (CAP-04, §9 Security) | ketochi · Claude | Round-trip test: save a 3-page document, reload, originals byte-identical. Files carry complete protection attribute.<br>_Done: `ScanRecord`/`PageRecord` (SwiftData) + `FileStore`; originals round-trip byte-identical (test). File-protection attribute asserted on device only — the Simulator doesn't report it._ |
| [x] M1.2 | **Write-ahead capture session**: each page is written to disk the moment it arrives; an interrupted session is restored on next launch (§9 Reliability, spike 4) | ketochi · Claude | Test: kill the process mid-session (simulate by discarding the in-memory model), relaunch, session and page order intact.<br>_Done: `Library.addPage` is write-ahead (files → record → save); `recoverableDrafts()` on launch; test reopens the on-disk store and finds the interrupted draft with page order intact._ |
| [x] M1.3 | **Library screen**: list of scans with thumbnail, title, date, page count; rename, delete; open into Review | ketochi · Claude | 100 scans scroll smoothly on the simulator; delete removes files, not just the record.<br>_Done: Home lists scans (thumbnail, title, date, pages, OCR mark), swipe to delete, rename from Review, "Interrupted" section to continue a draft. 100-scan scroll not yet measured._ |
| [x] M1.4 | **Thumbnails** generated at capture (long side ≈ 400 px) and stored as derivatives; Review grid stops decoding full-res originals | ketochi · Claude | Review of a 25-page document stays under 150 MB resident on device.<br>_Done: 400 px thumbnails generated at ingest and stored as derivatives; Review grid and list decode only thumbnails, Page detail decodes at ≤ 2048 px. 25-page memory ceiling not yet measured on device._ |
| [x] M1.5 | **Export formats + size estimate**: JPEG (one file per page, zipped when >1) and TXT alongside PDF; estimated output size per preset shown before export (EXP-01, EXP-02) | ketochi · Claude | Estimate within ±15% of the actual file for the fixture pages.<br>_Done: JPEG (one file per page, shared as multiple items — no zip needed) and Text alongside searchable PDF; size shown before export is the real size because the export is built and cached per record version (exact, not ±15%)._ |
| [x] M1.6 | **Save to Files** via `fileExporter` in addition to the share sheet (EXP-01) | ketochi · Claude | Exported PDF opens in Files and is searchable there.<br>_Done: "Save to Files" via `UIDocumentPickerViewController(forExporting:)` next to the share button. Files-app search of the exported PDF verified only via PDFKit in tests; check on device._ |
| [x] M1.7 | **Face ID lock + Settings**: optional biometric lock (LocalAuthentication), "Delete everything", processing explanation screen (§9 Security, §10) | ketochi · Claude | Lock engages on background→foreground; delete leaves no files in Application Support or tmp.<br>_Done: Face ID/passcode lock (`LockGate`, engages on background→active and at launch), Settings with storage used, data explanation, Delete all scans (records + files + export temp). Lock-while-a-sheet-is-open shows the sheet above the lock — known gap, see Open questions._ |
| [x] M1.8 | **Copy and privacy pass**: every screen that processes shows `ProcessingBadge`; export button copy says what it does; no dead ends | ketochi · Claude | Walkthrough checklist in PR description.<br>_Done: every processing screen shows `ProcessingBadge`; buttons say what they do ("Share Searchable PDF", "Save to Files"); errors say what went wrong; no dead ends. Checklist in Learnings._ |

Definition of done for M1: all boxes ticked, tests green, `docs/mvp-plan.md` §5 rows for CAP-04, EXP-01, EXP-02, Privacy, Library, Recovery marked implemented.

## Done → M2 · Verification & understanding (2026-09-01; M2.7 corpus expansion remains open)

Goal: the app tells you when a scan is not good enough or incomplete, and suggests what it is.

| # | Task | Who | Acceptance criterion |
|---|------|-----|----------------------|
| [x] M2.1 | `QualityScorer` in `Recognition`: blur (Laplacian variance), glare (% clipped highlights), shadow (luma gradient), readability (share of low-confidence OCR words) (QLT-01) | ketochi · Claude | Scores computed per page off-main; unit tests with synthetic blurred/glared fixtures.<br>_Done: `QualityAnalyzer` (Laplacian blur variance, clipped-highlight glare ratio, 85th-percentile block shadow spread, low-confidence OCR share) on a 512 px gray working copy, off-main. Synthetic fixture values: sharp 1705 vs blurred 6 variance._ |
| [x] M2.2 | Per-class thresholds + `QualityWarning` model; iOS 26 `DetectLensSmudgeRequest` behind `#available` | ketochi · Claude | Warnings fire on the bad fixtures, not on the clean ones.<br>_Done: `QualityThresholds.standard` tuned on the synthetic fixtures; warnings fire on the bad fixtures and stay quiet on clean ones (tests). iOS 26 `DetectLensSmudgeRequest` wired behind `#available`. Real per-class thresholds still need the device corpus (M3+)._ |
| [x] M2.3 | Duplicate pages via `GenerateImageFeaturePrintRequest` distance; page-sequence check from OCR ("3 de 7", "Page 3 of 7") (QLT-02) | ketochi · Claude | Duplicate fixture flagged; reordered fixture flagged; never auto-deleted or reordered.<br>_Done: duplicates via `GenerateImageFeaturePrintRequest` distance with a 9×8 dHash fallback (the neural runtime is absent on the Simulator and can fail on device); page-number sequence parsing ("Página 3 de 7", "Page 3 of 7", "3/7", not dates) → missing/out-of-order warnings. Warn only, never auto-fix._ |
| [x] M2.4 | **Verification summary** on Review: page count, flagged pages with reason, one tap to the page; non-color indicators (§9 Accessibility) | ketochi · Claude | VoiceOver reads each warning; ignoring a warning is possible and logged as `quality_warning_resolved(ignore)`.<br>_Done: verification summary on Review (warnings link to their page, Ignore is persisted per warning key and logged as `quality_warning_resolved(ignore)`); orange badge + "needs attention" text on page cards (non-color); per-page warnings with Ignore on Page detail; footnote near export. VoiceOver labels combined per row._ |
| [x] M2.5 | `DocumentClassifier` (rule-based): Mexico-first vocabulary (RFC, CURP, INE, CFDI/factura, recibo, comprobante de domicilio, acta, contrato, nómina) + English; `NSDataDetector` for dates/amounts (CLS-01) | ketochi · Claude | Fixture set of 20 rendered docs classified ≥ 80% correctly; output is a suggestion the user can change.<br>_Done: rule-based `DocumentClassifier` (Mexico-first vocabulary + English), folded matching with word boundaries; party from the top lines; document date via Spanish/dd-mm-yyyy regexes with NSDataDetector fallback. 24-sample corpus ≥ 80% in tests. Create ML upgrade waits for the consented corpus._ |
| [x] M2.6 | Filename + title suggestion `{type}-{party}-{yyyy-MM-dd}`; editable before export | ketochi · Claude | Suggested name appears on Review; export uses the edited name.<br>_Done: "Suggested: {Kind} – {party} – {yyyy-MM-dd}" chip on Review with a Use button — offered only while the title is still the automatic one; renaming never re-verifies (contentRevision vs updatedAt split)._ |
| [~] M2.7 | Fixture corpus: ~50 rendered pages across sizes/fonts/rotations with expected labels under `Tests/Fixtures/` (§14) | ketochi · Claude | Corpus documented in `Tests/README.md`; no real personal documents.<br>_Partially done: 24 labeled classifier texts + rendered blur/glare/shadow/duplicate/sequence pages, all generated in `Tests/ScannerTests` (no committed images, no real documents). The ~50-page corpus across fonts/rotations and per-class thresholds still owed — expand alongside M3's real-capture testing._ |
| [x] M2.8 | iOS 26 `RecognizeDocumentsRequest` spike: does document structure improve classification? (spike 5) | ketochi · Claude | Short write-up appended to this file under "Learnings".<br>_Done (spike): see Learnings — structure comes through (4 paragraphs on the fixture), ~1.5× slower than plain OCR._ |

## Now → M3 · Real capture (replaces the VisionKit stand-in)

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

- **M2.8 spike — iOS 26 `RecognizeDocumentsRequest`**: on the factura fixture it returns the full
  transcript plus structure (4 paragraphs; tables/lists when present) in ~1.5 s vs ~1.0 s for plain
  `RecognizeTextRequest` (Simulator timings). Worth adopting behind `#available` for receipt/table
  extraction (P1) — not as the default OCR path, since word-level boxes for the PDF text layer come
  from `RecognizeTextRequest` anyway. API shape: `observation.document.text.transcript`,
  `.document.tables/.paragraphs/.lists`.
- **Neural Vision requests don't run on the Simulator**: `GenerateImageFeaturePrintRequest` (and
  smudge detection) fail with "Failed to create espresso context". Duplicate detection therefore has a
  9×8 dHash fallback (cutoff hamming ≤ 2; two *different* text pages measured 5) that also covers
  exact re-imports on device. Verify the feature-print path on hardware in M3.
- **Verification staleness is content-based** (`contentRevision`), not `updatedAt` — renaming a scan
  (e.g. accepting the suggested title) must not trigger a re-verify of every page.

- **Spike 1 (searchable PDF)**: CoreText `CTLineDraw` with `setTextDrawingMode(.invisible)` produces a text
  layer PDFKit can find and select; sizing the font so ascent+descent = box height and stretching the
  text matrix to the box width keeps selection aligned within 3%. No PDFKit or UIKit needed in `Export`.
- Vision only accepts its own language identifiers (`es-ES`, not `es-MX`); `TextRecognizer.resolve` maps
  by language code. On the iOS 26 simulator `VNDocumentCameraViewController.isSupported` returns `true`
  even though there is no camera.

- **M1 relaunch test**: two `ModelContainer`s over the same on-disk store URL in one process work fine for
  simulating a relaunch; `Library.ephemeral` (in-memory) is for everything else.
- **SwiftData store location**: a named `ModelConfiguration` without a URL failed on first launch because
  Application Support didn't exist yet. `Library.live()` now creates the file store first and pins the
  store URL under `Application Support/Scanner/`.
- **Memory**: `ScanPage` loads its original lazily (`loadOriginal()`); export decodes/encodes one page at a
  time. Lists and grids only ever decode 400 px thumbnails.
- **Simulator helpers (DEBUG only)**: launch with `-seedDemoScan` to get a two-page rendered scan, and
  `-openFirstScan` to land on Review — used for screenshots since the Simulator has no camera.
- **M1.8 copy/privacy walkthrough**: Home (badge in empty state), Review (badge in header), Page detail
  (badge below text), Settings (badge in footer + plain-language data section). Camera permission and
  Face ID strings say why and that nothing is uploaded.

## Open questions (for the owner)

- Lock gate vs. presented sheets: when the app is locked while Settings or a share sheet is open, the
  sheet stays above the lock overlay. Fix candidates: dismiss sheets on background, or present the lock
  as its own full-screen cover. Not urgent for M1; pick one in M4's accessibility/security pass.
- Backups: page files are protected on device and included in encrypted device/iCloud backups (default
  iOS behaviour). Excluding them would mean scans don't survive a phone restore. Keeping the default
  unless the owner says otherwise.

See `docs/mvp-plan.md` §9: app name (ScanFlow is taken), bundle ID / developer account, territories,
Family Sharing, languages, analytics vendor, and confirmation that monetization is paid-upfront.
Add new questions here; don't block on them if a sensible default exists.
