# MORE documentation

MORE is a native iPhone app. Build from `main`; the Mac is its development/test environment. Current runtime inspection is `8e25b20`, with demo planning merged at `b8a6c93`. Ordinary MORE build 1518 was installed; owner-confirmed Gmail reading and Screen Time proposal approval are partial proof, not a completed morning.

**Start here:** [Current onboarding](ONBOARDING.md) · [Demo requirements](DEMO-REQUIREMENTS.md) · [Normal iPhone acceptance](DEMO-TEST-PLAN.md) · [iOS stories, modules and ownership](IOS-TEAM-GUIDE.md).

**Architecture and gaps:** [Dated source audit](audit/2026-10-15-IOS-AUDIT.md) · [Local/PCC model and recording plan](APPLE-MODEL-PLAN.md) · [Gmail reading and saved connection](GMAIL-READING.md) · [Current visual/navigation direction](CURRENT-DIRECTION.md).

Current navigation has Home, Learn/Routine and Settings, with days inline on Home. Historical design/feature guides below retain implementation context and older evidence; their menu labels do not override current onboarding. Full normal-phone rehearsal remains open. No fixtures or test control substitute for that proof.

## Use the app

| Guide | What it answers |
|---|---|
| [Observed mornings](OBSERVED-MORNINGS.md) | Inspect sampled screens, exact source quotations and distinct-day labels without inventing usage totals |
| [Learn from saved mornings](ROUTINE-LEARNING.md) | Select comparable sources, inspect quotations, manage keep/exclude/timing choices, and approve or discard a pending update |
| [Privacy & local data](PRIVACY.md) | Review stored categories, disable activity logging and remove local data with recoverable cleanup |
| [Portable routine files](ROUTINE-FILES.md) | Preview a plan-only export, choose whether to include notes, and review an imported draft |
| [Morning entry](MORNING-ENTRY.md) | Schedule one invitation, enter through Start, and understand permissions, expiry and manual fallback |
| [Lock Screen progress](LIVE-ACTIVITY.md) | Opt into a generic Live Activity, understand its paused/stale state, and return to Morning without starting a run |
| [Your day](YOUR-DAY.md) | Select calendars and a city, preview a sourced recap, and add it to an approved morning |
| [Saved moments](SAVED-MOMENTS.md) | Select an exact historical excerpt, preview it and hear it in an approved routine |
| [Voice commands](VOICE.md) | Use an explicit listening turn; understand commands, audio handoff and outstanding device checks |
| [Voice audit](VOICE-AUDIT.md) | What Apple documents about Personal Voice and Siri voices, and what a custom voice would require; none is offered |
| [V2 design history](V2-DESIGN.md) | Earlier design contract; current navigation is in ONBOARDING and CURRENT-DIRECTION |
| [Short morning trial checklist](DEVICE-SETUP.md#tomorrow-morning-checklist) | The recording checks and recovery boundaries retained from the earlier physical trial |
| [Onboarding](ONBOARDING.md) | Current three-destination flow and local developer setup |
| [Device setup](DEVICE-SETUP.md) | Signing, paired-device tests, recording, Shortcuts and the separate HomePod experiment |

## Understand and build it

| Guide | What it contains |
|---|---|
| [Architecture](ARCHITECTURE.md) | System diagrams, runtime states, persistence, model inference and effect boundaries |
| [Business hypotheses](BUSINESS.md) | Customer jobs, proposed subscriptions, experiment measures and independent research feasibility |
| [Data retention today](ARCHITECTURE.md#data-retention-today) | What exists on disk, why it remains and what current controls remove |
| [Apple capabilities](CAPABILITIES.md) | Framework-specific behavior, permission requirements and official documentation |
| [Observation plan](OBSERVATION-PLAN.md) | Learning windows, evidence quality, app-return cycles, coverage and research hypotheses |
| [Observation metrics](OBSERVATION-METRICS.md) | Ordered samples and text positions, bounded model evidence, unknowns, trace mathematics and day denominators |
| [Roadmap](ROADMAP.md) | Priorities, dependencies and GitHub issues |
| [V2 issue #25](https://github.com/gibouu/morning-operator/issues/25) | Design acceptance criteria and the owner walkthrough still required |

## Assess the evidence

| Guide | How to use it |
|---|---|
| [Physical verification record](PHASE-ONE.md) | Read source, device, scope and outcome before carrying a phone result over to new code |
| [Digest test protocol](DIGEST-TEST-PROTOCOL.md) | Three fresh seeds, actual inference, exact source facts, speech and independent multi-day evidence |
| [Digest scorer contract](../Benchmarks/morning-digest-contract.md) | Versioned facts, withheld truth, runtime evidence and separate transcript checks; the digest model adapter remains unfinished |
| [Historical teammate handoff](HANDOFF.md) | Earlier tasks and failure history; current ownership is in IOS-TEAM-GUIDE |
| [Test report template](TEST-REPORT-TEMPLATE.md) | Record a pass, failure, skip or environment block without uploading personal artifacts |
| [Recording benchmark](OBSERVATION-BENCHMARK.md) | Reproduce real capture of two native fixture apps; distinguish extraction success, known actions and failed model inference |
| [Controlled benchmark #23](https://github.com/gibouu/morning-operator/issues/23) | Compare known phone actions and visible evidence against extraction and model claims |

**Implemented** means the source contains the behavior. **Verified** means a specified check actually passed. **Planned** means further design or implementation remains. A simulator navigation pass is not a physical recording test; a passing synthetic import is not native capture; successful capture is not proof that proposed habits are correct.

Observations, source corrections, routine versions, saved thoughts and run recaps have distinct lifecycles. Missing days and unresolved origins stay unknown. Sampled evidence cannot establish continuous phone usage, and recorded routine time is not measured external-app time. Follow current onboarding for access paths and the privacy guide for retained copies.

The private source PRD, personal recordings, OCR, workspace snapshots and device-test media stay outside these shared guides. [Research-data feasibility #24](https://github.com/gibouu/morning-operator/issues/24) does not authorize retention or upload of those artifacts.
