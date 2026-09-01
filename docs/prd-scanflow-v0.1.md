# ScanFlow — PRD v0.1

**An intelligent iPhone scanner for documents first, photographs second**

> Source: shared by the product owner on 2026-08-31. Preserved verbatim (tables reconstructed as Markdown). Note: "ScanFlow" is a working title — the name is already used by several App Store apps (see `docs/mvp-plan.md`).

- **Status:** Draft for product and engineering review
- **Owner:** Product
- **Platform:** iPhone / iOS
- **Version:** v0.1 | September 1, 2026
- **Target:** MVP definition; launch timing to be confirmed

**PRODUCT THESIS** — Scanning is not the product. The product converts physical information into an accurate, searchable, secure digital record and helps the user complete the next action.

## 1. Executive summary

ScanFlow is an iPhone application that captures documents, receipts, IDs, notes, books, whiteboards, and photographs; selects the appropriate processing method; verifies completeness and readability; extracts useful information; and routes the output to the user's chosen destination.

The product competes above the commoditized camera-and-crop layer. Apple's built-in scanner already provides automatic capture, corner adjustment, multi-page scanning, saving, and signatures. ScanFlow wins by adding document understanding, quality assurance, task completion, privacy by default, and an archival-quality photo mode.

## 2. Problem statement

People do not scan paper because they want a scan. They need to submit an expense, sign and return a form, preserve an ID, search old records, digitize notes, or rescue family photographs. Existing tools frequently stop at PDF creation, require manual naming and organization, hide useful functions behind subscriptions, or upload sensitive content without sufficiently clear control.

### User problems

- **Capture friction:** users manually align pages, correct corners, reshoot blur, reorder pages, and remove duplicates.
- **Quality uncertainty:** users cannot easily determine whether small text, signatures, edges, or page sequence are complete.
- **Information friction:** PDFs are created, but key fields and text remain difficult to reuse.
- **Workflow fragmentation:** signing, compressing, renaming, emailing, filing, or expensing requires multiple apps.
- **Trust friction:** IDs, tax records, contracts, and medical documents may be sent to a cloud service without an obvious need.
- **Archival friction:** photo tools may enhance images but lose original fidelity, back-of-photo context, or portable metadata.

## 3. Goals and non-goals

### Goals

- Produce a complete, readable scan with minimal manual intervention.
- Make the result searchable and portable in standard formats.
- Detect common scan failures before the user exports or submits the file.
- Recognize document type and recommend the most likely next action.
- Process sensitive content on-device wherever technically feasible.
- Provide a specialized archival mode that preserves both original and enhanced photo versions.

### Non-goals for MVP

- A general-purpose cloud document management system.
- A full PDF editor comparable to Acrobat.
- Legally binding identity verification or remote notarization.
- Automated tax, legal, medical, or financial advice.
- Generative restoration that changes documentary evidence or silently overwrites original photographs.
- Native integrations with every expense, CRM, storage, and collaboration platform at launch.

## 4. Product principles

| Principle | Implication |
|---|---|
| Outcome over capture | Optimize for the user's completed task, not the number of scans created. |
| Verify before export | A readable-looking preview is insufficient; check blur, crop, glare, sequence, and completeness. |
| Originals are immutable | Preserve the raw or minimally corrected source separately from enhanced derivatives. |
| Local by default | Use on-device processing for OCR, classification, and quality checks when feasible. |
| Open by design | Allow standard PDF/JPEG export and user-selected destinations without lock-in. |
| Modes follow physics | Receipts, books, IDs, whiteboards, and glossy photos need different capture models. |
| Explain automation | Show what was detected, changed, extracted, or uploaded, and allow correction. |

## 5. Target users and jobs to be done

| Persona | Context | Primary job |
|---|---|---|
| Everyday professional | Occasional urgent paperwork | Scan, sign, compress, and return a form without a computer. |
| Small business owner | Receipts, invoices, records | Extract fields, organize records, and route them to finance workflows. |
| Student or researcher | Notes, handouts, books | Create clean, searchable study material from multiple pages. |
| Household organizer | IDs, warranties, medical and tax files | Build a private, searchable record without vendor lock-in. |
| Family archivist | Boxes and albums of photographs | Digitize quickly while preserving original quality and family context. |

### Primary jobs to be done

1. When I receive a physical document that must be sent somewhere, help me create a correct file and deliver it quickly.
2. When I scan sensitive records, help me understand where the information is processed and stored.
3. When I have many pages or items, help me capture them rapidly without losing order or completeness.
4. When the content matters after scanning, extract and organize the information so I can find and reuse it.
5. When I digitize an irreplaceable photo, preserve a faithful source and its historical context before improving it.

## 6. Scope and release strategy

**MVP WEDGE** — Win the high-frequency document workflow: scan, verify, OCR, create a searchable PDF, and export. Add receipt/ID/form intelligence and photo archival as differentiated modes after the core capture pipeline is reliable.

| Release | Included capabilities |
|---|---|
| MVP / P0 | Document auto-capture; multi-page scanning; crop/perspective correction; filters; on-device OCR; quality checks; page management; searchable PDF/JPEG export; Files/share sheet; local naming and classification; explicit privacy controls. |
| V1 / P1 | Receipt field extraction; ID front/back pairing; signature workflow; smart folders; semantic search; cloud destinations; photo archival mode with original + enhanced copy and back scan. |
| V2 / P2 | Workflow integrations; collaborative family archive; form-field detection; document Q&A; duplicate detection; redaction; book mode; enterprise administration. |

## 7. Core experience

### Primary flow

1. Open ScanFlow from the app, Lock Screen control, widget, share extension, or Shortcuts action.
2. Point the camera at the object. The app proposes a mode and shows live guidance for distance, lighting, glare, stability, and missing edges.
3. Auto-capture when quality thresholds are met; allow immediate manual override.
4. Continue capturing pages or items. Detect likely duplicates and maintain page order.
5. Run mode-specific cleanup and OCR while preserving the original capture.
6. Display a verification summary: page count, low-confidence pages, missing edges, blur, glare, or incomplete fields.
7. Suggest filename, document type, folder, and next action. The user can correct all suggestions.
8. Export to PDF/JPEG/text or execute the selected action through Files, share sheet, or an enabled integration.

### Capture modes

| Mode | Best for | Specialized behavior |
|---|---|---|
| Document | Contracts, forms, letters | Straighten, clean background, preserve signatures, searchable PDF |
| Receipt / invoice | Expenses and purchases | Small-text fidelity, merchant/date/total/tax extraction |
| ID | Licenses, passports, cards | Front/back pairing, glare warning, secure handling, no beautification |
| Book / notes | Bound pages and handwriting | Curvature correction, two-page detection, handwriting OCR where supported |
| Whiteboard | Meetings and diagrams | Perspective correction, contrast isolation, color-preserving option |
| Photo archive | Prints, albums, photo backs | Glare reduction, faithful original, optional restoration, metadata pairing |

## 8. Functional requirements

| ID | Priority | Requirement | Acceptance criterion |
|---|---|---|---|
| CAP-01 | P0 | Detect page boundaries and auto-capture only when stability and framing thresholds are met. | A user can scan a standard letter page without manually pressing the shutter or adjusting corners in normal conditions. |
| CAP-02 | P0 | Support manual shutter, flash, filter, crop, rotation, and corner correction. | Every automatic decision is reversible before export. |
| CAP-03 | P0 | Support continuous multi-page sessions with reorder, delete, recapture, and insert. | A 25-page document can be corrected without restarting the session. |
| CAP-04 | P0 | Preserve an internal source image before destructive enhancement. | The original can be retrieved or regenerated during the active project. |
| QLT-01 | P0 | Score blur, glare, shadow, crop completeness, perspective, and text readability per page. | Low-confidence pages are visibly flagged before export. |
| QLT-02 | P0 | Detect likely duplicate pages and improbable sequence changes. | The app warns without deleting or reordering automatically. |
| OCR-01 | P0 | Perform on-device OCR for supported printed languages. | Exported PDFs are searchable and recognized text can be copied. |
| OCR-02 | P1 | Extract structured fields for receipts, invoices, and IDs. | Users can review confidence and correct each extracted value. |
| CLS-01 | P0 | Classify common document categories locally. | Classification produces a filename and destination suggestion, never a forced action. |
| EXP-01 | P0 | Export PDF, searchable PDF, JPEG, and extracted text through the iOS share sheet and Files. | Core exports contain no watermark and do not require cloud upload. |
| EXP-02 | P0 | Offer compression presets with an estimated output size. | The user can target email-friendly, standard, or archival quality. |
| ACT-01 | P1 | Support fill/sign/return for documents with signature fields. | The user can add a saved or new signature and export the signed copy. |
| ORG-01 | P1 | Provide local folders, tags, filenames, full-text search, and retention controls. | Users can find a scan by title, OCR text, date, or type. |
| PHT-01 | P1 | Provide photo-specific multi-capture glare reduction and batch separation. | Multiple prints can be detected while a selected print can use high-fidelity multi-frame capture. |
| PHT-02 | P1 | Pair front and back; attach names, date, location, and story metadata. | Metadata exports with the image or a standard sidecar format. |
| PHT-03 | P1 | Store original and enhanced photo versions separately. | Restoration never overwrites the archival source. |

## 9. Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | Camera opens in ≤1.0 second on supported devices; page processing does not block continued capture; median single-page export completes in ≤3 seconds after capture. |
| Reliability | No silent loss of captured pages. Interrupted sessions recover locally after app termination or device restart. |
| Privacy | Core capture, classification, OCR, and quality scoring operate on-device. Any cloud-dependent feature requires explicit, contextual disclosure. |
| Security | Files use iOS data protection; optional Face ID lock; temporary exports and cloud artifacts follow documented retention rules. |
| Accessibility | VoiceOver labels, Dynamic Type where compatible, sufficient contrast, non-color error indicators, and volume-button capture. |
| Compatibility | Initial support target: iOS 18+ on devices that meet camera and on-device model requirements; final matrix subject to technical discovery. |
| Localization | Architecture supports multi-language UI and OCR. MVP language set determined by OCR quality and launch market. |
| Portability | No watermark or proprietary viewer required for core export. Preserve standard metadata where formats allow. |

## 10. Privacy, safety, and trust

- **Processing label:** every feature indicates whether processing occurs on-device or in the cloud.
- **Minimum necessary data:** cloud features upload only the content required for the selected operation.
- **User confirmation:** classification and extracted fields are suggestions; users approve consequential actions.
- **Evidence integrity:** document mode must not generatively reconstruct text, signatures, stamps, totals, or identity fields.
- **Restoration separation:** generative photo improvements are visually labeled and stored as derivatives.
- **Deletion controls:** users can remove local files and request deletion of cloud-processed artifacts from within the app.
- **Sensitive-class safeguards:** IDs, medical records, financial documents, and minors' photos receive stricter defaults and clearer warnings.

## 11. Success metrics

| Level | Metric | Definition | MVP target |
|---|---|---|---|
| North-star | Verified task completion rate | % of scanning sessions exported or completed without a rescan within 10 minutes | Establish baseline in beta; target ≥85% for supported document types |
| Activation | First successful scan | % of new users who export a readable scan in first session | ≥70% |
| Efficiency | Median time to export | App open to exported 1-3 page document | ≤45 seconds |
| Quality | Post-export rescan rate | % of exported pages rescanned within 10 minutes | ≤5% |
| Automation | Auto-capture acceptance | % of captured pages accepted without corner correction | ≥85% in benchmark conditions |
| OCR | Character / field accuracy | Benchmark accuracy by language and document class | Threshold set per supported class before launch |
| Trust | Local-processing comprehension | % of tested users who correctly identify where processing occurs | ≥90% |
| Retention | Weekly returning scanners | Users with a second successful session within 28 days | Measure by segment; no single blended target at MVP |

### Guardrail metrics

- Crash-free sessions and capture-session recovery rate.
- False quality-warning rate and ignored-warning rate.
- Unexpected cloud-upload incidents: target zero.
- Export failure and file-corruption rates.
- Support contacts involving subscriptions, lost access, or unclear storage.
- Material document alteration incidents: target zero.

## 12. Analytics and experimentation

Analytics must measure product behavior without collecting document content. Event payloads should use categorical metadata, latency, confidence bands, error types, and user actions. Raw OCR text, images, filenames, extracted identity values, and document contents are excluded from general product analytics.

| Event | Permitted properties |
|---|---|
| scan_session_started | entry_point, proposed_mode, device_class |
| page_captured | capture_method, mode, quality_band, processing_latency |
| quality_warning_shown | warning_type, confidence_band, page_index |
| quality_warning_resolved | warning_type, action: recapture/edit/ignore |
| ocr_completed | language, document_class, confidence_band, latency |
| export_completed | format, page_count_band, size_band, destination_category |
| action_completed | action_type, integration_category, success/failure |

## 13. Monetization principles

Core scanning must remain useful without a subscription. Users should never lose access to exported files or be forced to upload sensitive documents to unlock basic capture.

| Tier | Value |
|---|---|
| Free | Unlimited basic document capture, multi-page scan, essential quality checks, on-device OCR within reasonable device limits, standard PDF/JPEG export, no watermark. |
| Pro | Advanced extraction, semantic search, premium compression/editing, automation, expanded archival tools, encrypted sync, and selected integrations. |
| Project pass | One-time access for high-intensity projects such as tax season or a family photo archive. |
| Business | Team destinations, policy controls, workflow integrations, centralized billing, support, and administrative features. |

## 14. Dependencies

- iOS camera, Vision/VisionKit, PDF generation, Files, share sheet, Shortcuts, and local data-protection capabilities.
- On-device OCR and classification model quality across supported languages and device classes.
- A benchmark corpus with consented documents covering lighting, perspective, paper types, handwriting, receipts, IDs, and photographs.
- Security and privacy review for any external OCR, restoration, sync, or integration service.
- Legal review for signatures, identity documents, retention, biometric access, and regional privacy requirements.
- Design research with users who have accessibility needs and low confidence with document technology.

## 15. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Native iOS scanner is sufficient | High | Differentiate on verification, structured understanding, workflows, privacy clarity, and specialized modes. |
| OCR errors create false confidence | High | Expose confidence, require review for consequential fields, and never fabricate unreadable text. |
| Scope becomes a full document suite | High | Hold MVP to capture, verify, OCR, and export; gate integrations and editing behind evidence. |
| On-device models exclude older phones | Medium | Define a capability matrix and graceful fallback; do not silently switch to cloud. |
| Subscription backlash | Medium | Keep core export free, offer project pricing, and communicate ownership clearly. |
| Photo enhancement damages history | High | Immutable original, derivative labeling, reversible edits, and exportable metadata. |
| Sensitive data leakage | High | Local defaults, data minimization, encryption, retention controls, and threat-model review. |

## 16. Validation plan

1. Interview 12-15 users across professionals, small businesses, students, household organizers, and family archivists; identify the last five real scanning tasks completed.
2. Benchmark Apple Notes, Adobe Scan, Google PhotoScan, Photomyne, and two privacy-first scanners on task completion time, corrections, export friction, and trust comprehension.
3. Prototype the document quality summary and test whether users understand and act on warnings without feeling blocked.
4. Run technical spikes for continuous capture, on-device OCR, glare detection, book flattening, and interrupted-session recovery.
5. Build a consented benchmark corpus and establish quality thresholds by document type rather than one blended score.
6. Pilot the P0 workflow with 100-300 external users before committing to advanced extraction or integrations.

## 17. Launch criteria

| Gate | Exit criterion |
|---|---|
| Capture | P0 requirements pass on the supported device matrix and benchmark conditions. |
| Quality | Low-quality pages are detected at the agreed precision/recall threshold; no known silent page-loss defect. |
| Export | Searchable PDF/JPEG export works offline and through Files/share sheet without watermark. |
| Privacy | Core workflow is verified on-device; data-flow documentation and in-product disclosure pass review. |
| Reliability | Crash-free session and recovery thresholds meet release standards; corrupted export rate is within tolerance. |
| Accessibility | VoiceOver, Dynamic Type, contrast, non-color warnings, and alternative capture controls pass audit. |
| Trust | No known material alteration of document content; original capture preservation validated. |

## 18. Open questions

1. Which launch segment provides the strongest repeat behavior: general productivity, small-business receipts, or private household records?
2. What device and iOS floor supports acceptable on-device OCR and classification without harming reach?
3. Which languages and document classes meet launch-quality OCR thresholds?
4. Should ScanFlow store a local library by default, or operate primarily as a transient capture-and-route utility?
5. Which workflow deserves the first structured mode: receipts, IDs, or sign-and-return forms?
6. Can high-quality glare removal run on-device at acceptable speed for photo and ID modes?
7. What one-time project pricing best addresses intermittent scanning behavior?
8. Which integrations create measurable task completion rather than product bloat?

## 19. Search and competitive evidence

Current search and marketplace evidence supports a documents-first strategy. Apple's built-in workflow establishes free automatic capture, multipage scanning, Files storage, and signatures as the baseline. Adobe Scan's scale and positioning validate demand for OCR, searchable PDFs, bulk scanning, field reuse, organization, and workflow completion. Photomyne and Google PhotoScan demonstrate the value of specialized batch capture, archival metadata, restoration, and computational glare removal for photographs.

| Source | Evidence used | URL |
|---|---|---|
| Apple Support | Native iPhone document scanning and signatures | https://support.apple.com/en-us/108963 |
| Adobe Scan / App Store | Document scanning, OCR, bulk capture, organization, export and adoption evidence | https://apps.apple.com/us/app/adobe-scan-pdf-ocr-scanner/id1199564834 |
| Photomyne / App Store | Batch photo scanning, restoration, metadata and family archive workflows | https://apps.apple.com/us/app/photo-scan-app-by-photomyne/id1037784828 |
| Google PhotoScan / App Store | Photo-specific computational capture and glare removal | https://apps.apple.com/us/app/photoscan-by-google-photos/id1165525994 |
