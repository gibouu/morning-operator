# Routine execution — 16 October 2026

[MORE.md](../MORE.md) remains the acceptance reference. This implementation closes several runtime gaps; its presence is not evidence that all services meet the product promise.

## The user journey

Review each moment's actual operation, service, time and optional likes. The explicit **Let MORE take care of my morning** button approves that version. **Start my morning** starts it later; it cannot approve a draft. A running session retains its approved snapshot while future edits remain drafts.

The Home landscape remains the playback scene with one short current passage and no accumulated history, step title or timer. A tap reveals only Play/Pause and Settings as floating glass symbols; they disappear after five seconds without interaction and remain available for VoiceOver. Next, Extend, Stop and **Interact** live in Settings. Readers and action forms open on request. A current send/write or uncertain result replaces an obsolete passage even when no new speech occurs. New result or question-answer passages remain available; uncertainty returns after speech ends. Privacy blocking removes the playback view and its retained text.

Saved observations can be selected together in Learn. A sourced suggestion can be approved directly or opened with **Adjust this suggestion** in the ordinary editor. Saving those adjustments leaves a draft; it does not delegate the routine. The previous approved version remains restorable until the new version is explicitly approved.

Browser moments have a reviewed behavior: feed, videos, stories, headlines or visible unread information, constrained to supported site routes. Likes are a separate, visible choice, limited to three per moment. Previously saved browser moments remain manual until edited; existing approval cannot silently authorize new gestures.

MORE observes the page, performs the reviewed operation, checks the result and continues at the selected pace. Loading, sign-in, occluding dialogs, changed layouts, empty content and an unknown like outcome are distinct states. Page text never authorizes actions. A budget ending can end observed browsing; it cannot prove an external effect. An effect being verified defers the transition. Pauses stop the same session's clock and browser. Resuming reopens that moment; relaunch pauses browser execution.

Observed-content counts now retain opaque hashes in the exact session/step record. A process restart can recognize content already counted without saving its text, URL or DOM. Older records preserve their count but cannot recover identities they never stored. The checkpoint is bounded and stops accepting new identities at capacity rather than evicting them and recounting later. It does not restore the web document or its viewport and does not certify a like; that effect has its own journal. Shared restoration/privacy/bounds tests pass, while the ordinary app's cold-relaunch journey still needs runtime proof.

Personal timed moments let a person get ready while MORE keeps the allotted time and moves on automatically. Spoken calendar/briefing/saved-note operations continue on their actual completion. A manual app handoff is described as manual; opening another iOS app cannot certify work inside it.

## Prepare listening before starting

Setup → **Prepare listening** shows the actual Speech, Microphone and local-recognition status for the selected language. Its explicit preparation button requests the missing system permissions. This preparation records no sample, starts no audio engine and does not certify that the microphone or acoustic interruption works. Denied access points to iPhone Settings; unavailable local recognition is explained without a remote fallback.

When Hands free is enabled and listening is not ready, Start opens this preparation before starting the morning. **Prepare, then begin** waits for the grants and the app to be active. **Begin without listening** releases any earlier microphone owner, then starts with the existing automatic and read-aloud settings. This choice suppresses listening for that exact session, including after restoration; it does not silently change the person’s global preferences. The buttons remain available for control. Closing preparation, changing the routine, backgrounding or privacy cleanup invalidates the pending start, so a late permission callback cannot start an old morning.

Reading aloud, continuing the routine and preparing listening remain distinct choices. Hands-free listening uses the microphone only during the foreground session after access is ready. Permission preparation is not evidence of continuous recognition, echo cancellation or real voice control; those require their own ordinary-iPhone checks.

## Voice and mail

An active hands-free morning owns continuous on-device recognition and duplex speech. Local speech recognition, echo cancellation, context at speech onset and cancellation guard the current moment. Pause keeps listening for Resume. Next, Stop, Repeat and +2 minutes share the session and timer. Broader questions use Apple's local model with current source context. Unsupported hardware/model/language is surfaced; no cloud fallback is enabled.

After an informational answer, an interrupted read-only/timed moment or a retained confirmed browser/account result can resume once after the answer actually finishes. An explicit Pause, replacement turn, changed moment, privacy transition or pending action invalidates that continuation. Resuming a confirmed account result does not execute its operation again. An unavailable native source pauses the same moment and explains Resume, Next and Stop; the recap retains the unavailable result.

An expired Calendar/briefing reading can be explicitly replaced with **actualise ce briefing** / **refresh this briefing**. Repeat continues to refer to the pinned reading and does not silently fetch a new one. The refresh command is unavailable during another prepared or uncertain action.

Gmail can request an optional **read and send** grant from its visible connection screen. Existing readonly grants stay readonly. A mail moment reads up to five unread messages, chooses up to three with an explicit urgency heuristic, quotes source excerpts and explains selection. It supports yes/no, message selection, reply intention, local drafting, corrections, read-back and explicit **send**. The model writes body text only; the observed message determines the recipient/thread. “Yes” does not send. Local generation unavailable still permits declining or continuing.

An explicit self-note request can prepare a new message to the connected account's own profile address, including when its Inbox is empty. Subject and body can be edited in the moment. Review and Send are separate actions; editing invalidates the prepared send. This is a new self-addressed message, not a fabricated reply thread. Entering an Apple action retains a mail draft but revokes its send review, so a later Send first reads the draft again.

The Gmail moment uses the session's persistent time budget and extension control. Its deadline waits for reading, generation, speech and sending work to settle. A verified reading with no unfinished intention can continue to the next moment; an unfinished draft or uncertain send pauses with the dialogue retained. Extending that deadline resumes the same dialogue and budget without fetching the Inbox or sending again. A new successful reading never overwrites an older uncertain send outcome.

Sending claims a durable operation before POST, with a stable generated Message-ID. A timeout or crash checks Sent for that identity and never retransmits merely because search found nothing. The journal holds hashed identities/status, not mail text. Volatile mail clears on background; the session and content-free journal retain safe recovery. Forget stops microphone/workers and removes both browser and mail journals.

Connected account actions use local argument proposals and an explicit human-readable review before execution. Their results are composed from provider data for display/speech; JSON is not the routine's output. The provider adapter, scope, permissions and account capabilities still determine actual coverage.

The [Slack slice](SLACK-REPLIES.md) replaces technical setup with a named account/channel picker for its latest-three-message moment. Replies use only a selected, recent message from that approved read. The local model writes body text; full account/channel/source/body review and a separate Send precede the dedicated server effect. The account subject and grant revision are checked at the write boundary. Unknown posts remain blocked, and their durable count is separate from successful reading. Shared contracts and the deployed no-write refusal path pass; the native interface and real Slack provider journey retain their own acceptance gates.

The [Google Calendar day slice](GOOGLE-CALENDAR-DAY.md) offers a named calendar picker and an unapproved draft moment. It calculates the current day in the phone’s time zone on each run, reads at most twenty-five events and discloses a partial result. Repeat uses retained content; an explicit refresh requests a new reading. This path does not create or change events.

## Contextual Apple actions

During an active morning, an explicit voice or interface request can prepare an Apple reminder or calendar event. The writable list/calendar and account are resolved from EventKit before review. MORE reads the title, destination and date/time details, then requires a separate action-specific confirmation. A small set of relative date forms is supported; other dates require clarification or the editable fields. MORE does not infer that an unsupported correction succeeded.

The person can also ask for upcoming reminders, choose one of the at most five observed items and explicitly mark it complete. The exact reminder, list, account and current fields are checked again before the write. A content-free durable claim precedes each write; only its observed receipt increments the session's confirmed Apple-action count. Unconfirmed claims appear separately in the recap, including after closing the dialogue. An uncertain write remains blocked rather than being repeated automatically. The current moment stays paused until Resume or Next, and a confirmed Apple action does not mark the unrelated moment complete.

Drafts and reminder content clear on background, privacy cleanup and a changed moment. Confirmed factual details remain available to local questions only in the same foreground moment. Calendar rescheduling, attendees, recurrence, and contextual follow-up writes outside Gmail/Apple/Slack remain to be implemented and verified.

The same action panel is available inside the routine browser, including when a spoken date needs interface correction. It presents over the retained page while that moment is paused. Closing the request leaves the same browser content and budget ready to resume.

## Verification boundaries

Package tests establish deterministic policy, encoding, stale-result/cancellation and injected-provider behavior. Simulator tests establish visible navigation, explicit delegation, clock/session transitions, recap persistence and actual public-page behavior where observed. Synthetic command injection is never microphone recognition. A loaded web page is never successful browsing.

Reviewed video context, structured browser sequences and explicitly selected dated Screen Time aggregates feed the common proposal while preserving source revisions, citations and personal choices. Missing Screen Time coverage stays unknown; its app totals do not establish gestures or redistribute observed browser budgets. The legacy direct Screen Time suggestion remains compatible. The final MORE acceptance still needs real multi-morning source coverage, connected accounts and an ordinary iPhone: acoustic barge-in, local-model latency, social stories/video/likes, all provider operations and actual voice-directed mail sending. These gates remain open until individually observed.

Native Screen Time app moments now retain a stable app identity across new acquisition days and edited titles. An old or manual personal choice whose app identity cannot be recovered requires explicit app review before new app-only moments are added. This review neither changes the saved Keep/Exclude/duration decisions nor approves the routine. The same rule is checked when a proposal is restored. Synthetic provenance follows retained sample moments independently of editable wording and remains declared in portable exports.

## Acceptance tracking

Remaining real-provider, voice, complete-source-learning and full-service acceptance is tracked in [#173](https://github.com/gibouu/morning-operator/issues/173). Runtime work is pushed on `guillaume/routine-automation`; a WIP checkpoint is not a product acceptance pass. The native/synthetic test report is kept separate from authenticated provider results.
