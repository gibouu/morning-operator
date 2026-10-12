# Portable routine files

MORE can prepare a portable JSON plan and review one before importing it. This is a routine transfer, not a workspace backup. The scoped validation below separates completed checks from outstanding provider and device verification; [PHASE-ONE](PHASE-ONE.md) maintains the wider record.

## Export a reviewed plan

1. Open **Review → Your routine → Export routine**.
2. Review the preview. **Include notes** starts off each time: the default file contains the plan's names, categories, order, planned minutes and keep flags, with its identifying/version metadata.
3. Turn on **Include notes** only if you want the exact saved step details and source label in the file. Details can include quotations from observations. The preview shows this text without shortening it.
4. Choose **Save file…** and a destination in the native file dialog. **Done** closes the preview. Canceling the dialog does not change the routine.

The preview holds the routine as it was when opened; the exporter writes that same snapshot and selected detail scope. It does not follow later workspace changes while the dialog is open.

Plan-only export omits every step's detail field and the source label, rather than trying to recognize and remove quotation lines. **Titles are still personal text. This is not anonymization.** Review the displayed names before sharing a file. Including notes may also include sensitive text someone wrote in those notes; the exporter does not inspect or redact it.

Neither mode adds executable app operations, account credentials, raw recordings, observation archives, run history, captures, saved-choice journals or approval receipts. The file is an ordinary JSON document, not an encrypted backup.

## Import without starting anything

1. Open **Review → Your routine → Import routine** and select a supported JSON file. Import is also available before a first routine exists.
2. Review the source version, exported approval, sample declaration, names, planned minutes and any included notes/source label. **Cancel** leaves the current routine unchanged.
3. Choose **Use as a draft** to save a new local routine. Every imported step is manual; no spoken-note, calendar or other app operation is enabled.
4. Review/edit the draft, then use the ordinary **Approve this routine** action when ready. The file's approval flag does not approve the imported draft or start a session.

The imported routine gets a fresh local ID. Its local version is the current version plus one, or one when there is no current routine. Step IDs and order are preserved. The document's original routine ID/version remain source metadata in the import preview; they do not select or overwrite a matching local object.

If an approved routine was current, **Restore previous routine** remains available while reviewing the imported draft. An existing unapproved draft is replaced; it does not get another restoration slot. Any already-retained approved routine stays restorable during this review, including after a repeated import. Ordinary approval follows the existing routine workflow and ends that draft's restoration opportunity. Existing saved choices stay separate: importing a keep flag does not add a standing preference to their journal.

Import is blocked while a morning is active. A changed current routine makes an already-open import preview stale, so it must be opened again. A failed save keeps the previous routine and the preview available. The selected original file is read, not changed or deleted; the app does not retain a separate raw copy of it.

## Format version 1

The authoritative implementation is [PortableRoutineDocument.swift](../Sources/MorningCore/PortableRoutineDocument.swift). This format is distinct from `workspace.json` and older raw `RoutineVersion` exports; those files are rejected here.

| Field | Meaning |
|---|---|
| `format` | Exactly `morning-operator.routine`. |
| `formatVersion` | Exactly `1`. |
| `detail` | `planOnly` or `includeDetails`. |
| `sourceRoutineID`, `sourceRoutineVersion` | Source UUID and positive version metadata. |
| `sourceCreatedAt` | Finite Unix seconds; the wire encoding is independent of a caller's date-encoding strategy. |
| `approvalAtExport` | Describes the exported source; confers no authority. |
| `sourceIsSynthetic` | Preserves the known sample/test declaration even when the source label is omitted. False does not prove human observation. |
| `sourceLabel` | Present only with included details. |
| `steps` | Ordered rows containing `id`, `title`, `kind`, `durationMinutes`, `isRequired`, and optional `detail`. |

Sample/test documents import with a sample marker so ordinary run-history filtering can continue to distinguish them. Source declarations are metadata, not verified claims about an external file's origin.

Validation requires:

- 1–10 steps, unique step UUIDs and 1–120 planned minutes per step.
- Nonblank titles of at most 2,000 characters; included details at most 32,000 characters per step; source labels at most 256 characters.
- At most **1,048,576 bytes (1 MiB)** for the selected file and encoded document.
- Finite dates, supported categories/detail modes and valid positive version metadata. Local version overflow is rejected.
- Known document and step keys only. An `automation` field is rejected, even when otherwise well-formed. Plan-only files cannot carry note/source text; detailed files must contain their declared text fields.

Invalid rows are not silently dropped and durations are not clamped. The bounded reader checks actual bytes as well as the reported file size, cooperates with file providers and releases scoped file access. Reading/decoding does not mutate the workspace; installation is a separate reviewed transaction.

## Validation snapshot

Recorded 10 October 2026. Transfer implementation: `943766e`; native round-trip check included with `aec8fc8`.

- **14 new shared checks passed:** 11 portable-format tests and three actual-file reader tests. They cover omitted/private fields, explicit details, version/identity semantics, manual unapproved imports, sample provenance, malformed input and bounds.
- **Simulator UI passed:** export preview with deliberate notes and the default reset on reopening; staged real-file import review/cancel, manual draft persistence, repeated import and restoration of the prior approved routine. The corrected malformed-file journey also passed, verifying a decoding error and the unchanged routine after relaunch. The fixtures contain synthetic content and invoke the production bounded reader.
- **Native file-sheet dismissal passed (78.153s)** in a corrected scoped run: the actual export and import panels dismiss, then the approved routine survives relaunch. Two earlier selector/hittability failures remain in the record. This earlier check only establishes dismissal. The later round trip below establishes local native save/selection separately.
- **Native local save/reopen passed (136.740s):** a uniquely named synthetic plan-only file was saved under **On My iPhone**, selected through the actual importer, reviewed without notes/source text and adopted as a manual unapproved draft that survived relaunch. The previous approved routine stayed restorable. No staged-file hook was used; provider bytes were not independently inspected. This is simulator local-provider evidence, not a cloud-provider or physical-device check.
- **Original transfer builds passed:** signed generic iOS and simulator targets. This transfer slice has not been installed on the physical iPhone.
- **The latest full shared run passed: 279 checks, six optional skips.** The earlier transfer run had 271 passes, six skips and two Vision failures; paired/isolated retries also failed. Scoped logs subsequently identified compiler storage exhaustion. Removing redundant project build caches restored both unchanged recognition checks; earlier failures remain in [the verification history](PHASE-ONE.md).

No transfer test invokes a model or proves recording, narration or cross-app behavior.

## Boundaries and implementation

This slice does not provide full forgetting, raw-media expiry, research-data export, an account transfer or backup/restore of the workspace. Exporting or deleting a portable file does not erase observations, quoted routine details or saved choices elsewhere in the app. Those controls remain separate work under [#8](https://github.com/gibouu/morning-operator/issues/8).

The UI and frozen export bytes live in [RoutineTransferViews.swift](../Sources/MorningOperator/RoutineTransferViews.swift); bounded selected-file access lives in [RoutineDocumentReader.swift](../Sources/MorningApple/RoutineDocumentReader.swift). Installation and rollback use [MorningStore.swift](../Sources/MorningOperator/MorningStore.swift). No model call is needed for transfer.

The native bridge uses Apple's [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument), [fileExporter](https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)) and [fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)); selected-file reads use [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator). Source-level tests and UI journeys are separate from a verified file-provider or device outcome.
