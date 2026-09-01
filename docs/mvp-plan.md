# Scanner — MVP plan (reconciled to the 199 MXN paid-upfront model)

_Drafted 2026-08-31 from `docs/first-principles-review.md` and `docs/prd-scanflow-v0.1.md`, plus the business decision stated by the owner: **the app costs 199 MXN to download and is then usable forever** (no subscription, no account)._

## 1. What the docs settle

| Question | Answer | Source |
|---|---|---|
| Scope | Documents first. Modes: Document, Receipt/Invoice, ID, Book/Notes, Whiteboard, Photo archive. QR/barcodes are out. | PRD §7 |
| MVP (P0) | Auto-capture, multi-page, crop/perspective, filters, on-device OCR, per-page quality checks, duplicate/sequence warnings, page management, searchable PDF/JPEG/text export, Files + share sheet, compression presets, local naming + classification, privacy controls. | PRD §6, §8 |
| Deferred (P1) | Receipt/ID field extraction, signatures, folders/tags/full-text search, cloud destinations, photo archive mode. | PRD §6, §8 |
| iCloud sync | Not MVP ("encrypted sync" is a later feature). | PRD §13 |
| Deployment target | iOS 18+. | PRD §9 |
| Analytics | Yes, content-free events only (schema in PRD §12). | PRD §12 |
| Privacy | On-device by default; every feature labeled on-device vs cloud; Face ID lock; data protection. | PRD §9–10 |
| Entry points | App, Lock Screen control, widget, share extension, Shortcuts. | PRD §7 |

## 2. Where the docs conflict with the business model (and how this plan resolves it)

**PRD §13 describes a freemium ladder (Free / Pro / Project pass / Business). The owner's decision is paid-upfront at 199 MXN.** This plan follows the owner's decision. Consequences:

1. **No StoreKit, no paywall, no tiers.** The PRD's "Free" tier list *is* the product baseline; "Pro" items become roadmap that ships inside the same price. "Project pass" and "Business" are dropped. Open question §18-7 (project pricing) is moot.
2. **No free trial is possible for a paid-upfront app.** PRD risk "native iOS scanner is sufficient" (§15, High) gets sharper: the App Store page must sell verification, OCR/search and privacy in the first three screenshots, because nobody can try it first. Listing copy: "Compra una vez. Sin suscripción. Sin cuenta. Todo en tu iPhone."
3. **Zero running cost matters.** Everything in MVP stays on-device (no backend, no cloud OCR). This is both the privacy story and what makes pay-once sustainable.
4. **Metrics:** §11 guardrail "support contacts involving subscriptions" becomes "refund requests per 100 sales" and review sentiment about value vs Notes.
5. **Family Sharing:** recommend ON (household-organizer persona; standard for paid-upfront utilities).
6. **Storefront:** base price 199 MXN in Mexico; sell worldwide with Apple's automatic equalization (≈ US$10–12) — costs nothing extra and the app is offline anyway. Confirm the exact 199 MXN price point exists in App Store Connect's pricing tab (Apple's MXN ladder is dense; 199 is expected to be present).

Rough net per Mexican sale: 199 MXN − 16% IVA ≈ 171 MXN gross to Apple → **≈146 MXN to us at 15% (Small Business Program)**, ≈120 MXN at 30%. Enroll in the Small Business Program before launch if not already enrolled.

## 3. Verified against the installed SDK (Xcode 26.6, iOS SDK 26.5)

| API | Min iOS | Use |
|---|---|---|
| `Vision.RecognizeTextRequest` | 18.0 | OCR with word boxes + confidence (OCR-01) |
| `Vision.DetectDocumentSegmentationRequest` | 18.0 | Live page quad for custom capture (CAP-01) |
| `Vision.GenerateImageFeaturePrintRequest` | 18.0 | Duplicate-page detection (QLT-02) |
| `Vision.DetectRectanglesRequest` | 18.0 | Fallback quad / ID cards |
| `VisionKit.VNDocumentCameraViewController` | 13.0 | Stock Apple scanner — **scaffold only** (see §5, M0) |
| `Vision.RecognizeDocumentsRequest` | **26.0** | Document structure (paragraphs, tables, lists) → better classification and extraction; gate behind `#available(iOS 26)` |
| `Vision.DetectLensSmudgeRequest` | **26.0** | Extra quality signal ("clean your lens") behind `#available(iOS 26)` |

Device floor: every iPhone that runs iOS 18 has an A12 or newer, so Vision's neural OCR and document segmentation are available on the entire supported matrix — no capability matrix or cloud fallback needed at MVP (resolves PRD §18-2).

## 4. Architecture

Mirrors the owner's existing projects (`event-pics-v11/app`): xcodegen `project.yml`, SwiftUI, iPhone-only, Swift 6 strict concurrency, local SPM packages, team ID in gitignored `Config/Signing.xcconfig`.

```
Scanner/
  project.yml                 # xcodegen; iOS 18.0; TARGETED_DEVICE_FAMILY 1
  Config/Signing.xcconfig     # gitignored (DEVELOPMENT_TEAM)
  App/                        # app target: navigation, screens, App Intents, Control widget
  Packages/
    ScannerCore/              # SwiftData models, session store (write-ahead), file store, data protection
    CaptureKit/               # AVFoundation camera, live quad + stability, auto-capture, guidance signals
    ImagePipeline/            # perspective correction, filters (CoreImage); originals vs derivatives
    Recognition/              # OCR, quality scoring, duplicate detection, classification, (later) field extraction
    Export/                   # PDF (image + invisible text layer), JPEG, TXT, compression estimator
    Telemetry/                # PRD §12 event schema behind a protocol; sinks: no-op / local log / vendor (later)
    DesignSystem/
  Tests/                      # unit tests over a fixture corpus (no real user documents)
  docs/
```

Key design rules carried from the docs: originals are immutable (store capture + quad + filter params; render derivatives), every automatic decision is reversible before export, nothing leaves the device without an explicit labeled action.

## 5. P0 requirements → implementation

| Req | Approach |
|---|---|
| CAP-01 auto-capture | Custom AVFoundation session; `DetectDocumentSegmentationRequest` per frame → quad; stability = quad-corner velocity below threshold for N frames; framing = quad inside safe area, min area; lighting = mean luma band; capture full-res still when all hold. Live guidance chips: "acércate", "más luz", "quieto", "falta una esquina". |
| CAP-02 manual controls | Shutter, torch, filter picker, crop with draggable corners (CoreImage `perspectiveCorrection`), rotate. |
| CAP-03 sessions | Session = ordered pages; reorder/delete/insert/recapture; 25+ pages without restart; thumbnails rendered off-main. |
| CAP-04 originals | Persist original still immediately (write-ahead, `NSFileProtectionComplete`), quad and filter as data; derivative cached, regenerable. |
| QLT-01 scores | Per page: blur (Laplacian variance inside quad), glare (% clipped highlights), shadow (luma gradient across page), crop completeness (quad confidence + edge contact), perspective (quad skew), readability (share of OCR words under confidence threshold). iOS 26: lens-smudge signal. Thresholds set on the benchmark corpus, per document class. |
| QLT-02 duplicates/sequence | Feature-print distance between pages → "possible duplicate"; page-number patterns in OCR ("3 de 7", "Page 3 of 7") → "page 4 may be missing / out of order". Warn only, never auto-fix. |
| OCR-01 | `RecognizeTextRequest` (accurate, `es`, `en`, auto language detection) run off-main per page while capture continues; text copyable from the page view. |
| CLS-01 | Rule-based classifier on OCR text + layout at MVP (Mexico-first vocabulary: RFC, CURP, INE, CFDI/factura, recibo, comprobante de domicilio, acta de nacimiento, contrato, nómina; English: invoice, receipt, agreement…). `NSDataDetector` for dates/amounts. Output: suggested type, filename `{type}-{party}-{yyyy-MM-dd}.pdf`, destination. Replace with a Create ML text classifier once the corpus exists. |
| EXP-01 | PDF and searchable PDF via CoreGraphics (draw page image, then recognized words in invisible text mode at their boxes), JPEG, TXT; `UIActivityViewController` + Files exporter; no watermark. |
| EXP-02 | Presets Email / Standard / Archive (long-side px + JPEG quality) with size estimate computed before export. |
| Privacy controls | "Procesado en tu iPhone" label on every screen that processes; Face ID lock (LocalAuthentication); data protection; delete-all; no third-party SDKs in MVP. |
| Library (answers PRD §18-4) | Local library **on** by default (paid app needs a home; household-records persona; enables "find the warranty" later). Verification screen always offers export/route first, so transient use stays one tap. |
| Entry points | App + Control Center/Lock Screen control (`ControlWidget`) + App Intent "Escanear documento" at MVP; share extension (import image/PDF) in P1. |
| Recovery | Session state and each page written to disk at capture time; on launch, an in-progress session is restored (PRD §9 reliability). |

## 6. Milestones (sequenced by risk; sizes are estimates for one developer working with Claude)

- **M0 — Walking skeleton (≈1 week).** Scaffold repo; capture with Apple's `VNDocumentCameraViewController` *as a temporary stand-in*; OCR → searchable PDF → share sheet works end to end on device. Proves spikes 1–2 below.
- **M1 — Records & trust (≈2 weeks).** SwiftData library, write-ahead session store + recovery, originals/derivatives, export presets, Face ID lock, privacy labels, delete-all.
- **M2 — Verification & understanding (≈2 weeks).** Quality scores + verification summary UI, duplicate/sequence warnings, rule-based classification + filename suggestion. Build the fixture corpus (own/consented documents; ~50 pages across lighting/paper types) and set thresholds per class.
- **M3 — Real capture (≈2 weeks).** Replace the VisionKit stand-in with CaptureKit: live quad, guidance, auto-capture, manual override, corner editor. This is what satisfies CAP-01/CAP-04 properly — VisionKit's scanner returns already-cropped, already-filtered pages and gives no per-frame signals, so it cannot meet those requirements.
- **M4 — Ship readiness (≈1 week).** es-MX + en localization, accessibility audit (VoiceOver, Dynamic Type, non-color warnings, volume-button capture), Control widget + App Intent, App Store listing (screenshots lead with verification/OCR/privacy), price 199 MXN base MX, Family Sharing on, launch gates from PRD §17.
- **Beta.** TestFlight with 100–300 users (PRD §16-6); baseline the §11 metrics before launch.
- **Post-launch P1 order (proposal for PRD §18-5):** sign-and-return forms first (fully on-device, no integration needed, hits the everyday-professional persona) → receipts extraction → ID front/back pairing → folders/tags/full-text search → photo archive mode.

## 7. Technical spikes to run first (inside M0/M1)

1. **Searchable PDF text layer:** invisible Core Text at OCR word boxes; verify Files/Preview search and text selection align on a 3-page test document.
2. **Live document segmentation at capture frame rate** on an A12-class phone (iPhone XR/XS) — latency and battery.
3. **Quality thresholds:** blur/glare/shadow scores vs human judgment on the fixture corpus; target the PRD's "flag low-confidence pages" without a high false-warning rate.
4. **Session recovery:** force-quit mid-capture, relaunch, session intact.
5. **iOS 26 `RecognizeDocumentsRequest`:** how much classification/extraction improves when available; keep as progressive enhancement.

## 8. Proposed answers to the PRD's open questions (§18)

1. **Launch segment:** Mexico-first "trámites" and household records (INE, CURP, comprobante de domicilio, actas, facturas) plus everyday professionals' sign-and-return forms. High frequency, sensitive (privacy story lands), no integration required.
2. **Floor:** iOS 18 — see §3; whole matrix has on-device OCR.
3. **Languages:** UI es-MX + en; OCR es + en at launch (Vision's accurate recognizer covers both; more Latin-script languages are essentially free to enable after benchmarking).
4. **Library vs transient:** local library on by default, export-first UX — see §5.
5. **First structured mode:** sign-and-return forms (see §6).
6. **Glare removal on-device:** spike in P1 (photo/ID modes); not needed for P0.
7. **Project pricing:** n/a under paid-upfront.
8. **Integrations:** none at MVP beyond Files/share sheet; add only when a beta metric (action_completed) shows demand.

## 9. Decisions still owned by you (none block M0)

| Item | Default this plan uses until you say otherwise |
|---|---|
| **App name** | "ScanFlow" is already taken on the App Store by at least four apps (QR scanner, Scanflow Pte Ltd, "ScanFlow: PDF Scanner App", "Document Scanner – Scanflow"). App Store names must be unique, so a new name is needed. Scaffold uses the working name `Scanner`; renaming is a one-line change in `project.yml`. |
| Bundle ID / developer account | Placeholder `mx.scanner.app` under the same Apple developer account as Konfetti; change with the name. |
| Territories | Worldwide, base 199 MXN (Mexico). |
| Family Sharing | On. |
| Languages | es-MX + en UI; es + en OCR. |
| Analytics vendor | None in MVP (no third-party SDK). §12 event schema is implemented behind a protocol with a local sink so a vendor can be added at beta without touching call sites. |
| Monetization | Paid-upfront 199 MXN (overrides PRD §13). |
