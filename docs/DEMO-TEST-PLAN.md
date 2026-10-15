# MORE demo acceptance plan

Use the [demo requirements](DEMO-REQUIREMENTS.md) as the scope. Run acceptance in the ordinary iPhone app with the owner's approved routine and real permitted accounts. Unit fixtures remain useful for regression checks; they are not evidence that a provider, model, alarm or handoff worked on the phone.

## Test record

For each check record: date/timezone, source commit, build number and distribution type, device/iOS, requirement ID, starting state, steps, observed outcome, pass/fail/blocked and the next issue. Save redacted errors and event IDs when needed. Keep mailbox text, contacts, recordings, health facts, tokens and passwords out of shared reports.

Start from main, preserving the owner's saved routine. Record whether the run is idle, paused, running or completed, which day is selected, and which connections are Ready. Another team's branch or a fresh install is a different test baseline.

Run the Forget/reset case only with disposable data on a separate test device or installation. It must not erase the owner's active routine to satisfy this checklist.

## Setup and learning

| Test | Action | Pass condition |
|---|---|---|
| T01 Guided setup | Choose the demo destinations; finish each requested authorization on the phone; stop and resume midway | Completed sources remain connected. Skipped sources are identified. No Mac console is required for an ordinary user's sign-in. |
| T02 Learning and approval | Obtain real Screen Time evidence; inspect the proposal, change one duration/order and approve | Evidence and estimates are clear. One daily routine is saved; no sample is substituted. New Gmail suggestions open the supported reader. |
| T03 Missing destination | Exclude an app, revoke one permission and test an unknown/unlaunchable target | Missing, denied and unknown stay distinct. The morning offers a clear skip/fallback; it does not claim zero activity. |
| T04 Start late | Open Today later in the day with an approved idle routine; repeat with a paused prior run | Start or Resume is understandable. Ending/restarting is explicit. No duplicate run is created. UX discovery remains #154. |

## Native opening and communication

| Test | Action | Pass condition |
|---|---|---|
| T05 Real alarm | Schedule a near-future MORE alarm normally; lock the device; let it ring; use its action | Actual audible ring and ordinary MORE entry are observed. Unlock/start boundaries are accurate. Repeat cancellation and denied-alarm permission. |
| T06 Weather | Read the selected city's current conditions, then test missing city/network failure/stale response. Test a day outlook only after an hourly/daily forecast reader exists | Spoken and visible values share the same fresh source. Errors are bounded; unsupported facts are omitted. |
| T07 Calendar | Select a known calendar and verify one appointment; repeat with permission denied, empty day and a different timezone | Correct day, time and source using one authoritative route per calendar/account. Direct Google API checks wait for that connector; dual-route dedup requires implemented identity rules. No unintended calendar write. |
| T08 Health | After native integration, authorize only needed Health types; test known data, empty data and denied reads | Actual authorized data is sourced correctly. An empty result is not presented as a measured zero or proof of permission. No medical conclusion is generated. |
| T09 Gmail persistence | Connect once; open a real message; leave/reopen; background; relaunch | Authorization restores without another browser login unless Google revoked/expired the grant. Message contents clear while away. |
| T10 Actual reply | Prepare a reply to one short supported message; edit it and copy it; repeat with local model unavailable and oversized/partial body | A real on-device draft is editable; manual fallback is usable. Nothing is sent or written to Gmail. Report the outcome only. |
| T11 Communication types | On the current phone route, open supported email/message data and an inaccessible call source; include a “call me” message. Test real missed-call records only after a specific provider adapter is implemented | Correct source-backed type. “Call me” stays a message. Current unsupported call history says unavailable. Synthetic missed-call classification is a separate source-level check, never live-provider proof. |
| T12 Provider failures | Go offline, revoke a test grant, interrupt refresh and return after a transient error | Retry preserves a still-valid saved connection. Revocation needs sign-in. Other moments continue; stale facts are not spoken as current. |

## Browser and external app

| Test | Action | Pass condition |
|---|---|---|
| T13 Visible browsing | Sign in directly on the chosen website; request one scroll/advance; navigate and return | Correct visible page changes once. The login works in this browser. Unsupported DOM behavior gives an honest result. |
| T14 Pace learning | Explicitly learn on a permitted page at two scroll speeds; stop; review; replay only after approval | Recorded distance/time supports the speed. Manual stop and page/site changes halt replay. Existing sparse screenshots cannot stand in for this measurement. |
| T15 News | Open the approved article; test a paywall, changed layout and denied extraction | Readable website remains available; summary only uses accessible supported source text. |
| T16 External handoff | Launch the chosen Duolingo/Chess target from a running moment | Correct app opens; no scripted taps occur inside it. Timer refers to the same run and moment. Failed launch is recoverable. |
| T17 Island and Lock Screen | While outside MORE, expand the island; press +2 once, rapidly repeat Next, then test while locked | +2 adds exactly 120 seconds per accepted action. Next advances once. Any unlock/foreground handoff is clear. No unrelated moment or stale action is applied. |
| T18 Timer lifecycle | Test an external-target moment and ordinary narration separately: background, pause/resume, interrupt, relaunch and let time expire | The external target retains its saved deadline; ordinary narration pauses and browser actions stop. Relaunch reconciles state. OS-controlled activity refresh is not continuous background app execution. Expiry cannot prove lesson completion or force another app open. |
| T19 Completion | Finish normally, then relaunch; separately stop a run and skip a moment | Exactly one completion is saved. Stopped/skipped remain accurate. No repeat greeting or duplicate history entry. |
| T20 Privacy | Disconnect Gmail, stop learning, revoke site permission and perform an explicit test-data Forget | Saved authorization and in-flight work obey removal. No later callback restores deleted content. Original provider data remains under that provider's control. |

## Source level classification checks

After a communication schema exists, synthetic records must cover email/message/explicit missed call/voicemail/unknown, conflicting labels, duplicate IDs and a “call me” message. An unsupported source cannot create a zero count or a known type. These tests validate policy only. A provider gets a real phone check after its adapter and authorization are available.

## Live rehearsal script

1. Before presenting, connect the chosen accounts and approve the actual six-moment route. Select short real budgets. Confirm local model readiness, network, charged phone, sound route, selected calendar and one installed external target.
2. Show one real Screen Time finding and the reviewed routine order. Do not claim that one day's evidence establishes a stable personal habit.
3. Lock the phone and let the scheduled alarm actually ring. Follow the ordinary alarm/start path.
4. Hear the short weather/calendar opening. Include Health only if T08 passed; otherwise name it as an unavailable optional source.
5. Read Gmail and prepare/edit a draft. Leave it unsent. Use Next normally.
6. Show one visible Instagram advance, one news article and the actual external-app handoff.
7. Expand the island, add two minutes, choose Next, then finish in MORE and verify today's saved completion.
8. Repeat the whole route three times without a Mac tapping the phone. Include a cold launch and one denied/offline-source recovery across those runs. Record all failures; a partial run is not a full pass.

## Release decision

The demo is ready when the selected route passes T01–T20 where applicable, three complete normal runs pass, and every omitted optional integration is named. Simulations and source-level tests remain separate evidence.

Before claiming App Store readiness, repeat the chosen route with a distribution/TestFlight build, normal device settings and no tethered controller. Complete the release gate in the requirements, verify current entitlements/provider permissions and prepare reviewer instructions. A developer-signed installation is not a distribution rehearsal or an App Store approval.
