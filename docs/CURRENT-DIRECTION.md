# One MORE direction

15 October 2026. Build from `main`. The current direction combines the visual foundation in PR #146 with the three-destination shell, direct routine page, inline day browser and connection tracks (#135, #136, #138 and #139). Use [MORE feedback](https://github.com/gibouu/morning-operator/issues/new/choose) for problems and design notes; include the commit, iPhone/iOS and what actually happened.

## The first story

1. Open MORE normally. In Learn, start with **See your rhythm → Connect Screen Time**. Review actual dates and app minutes, then the proposed morning. Unknown coverage and estimated order stay explicit.
2. Record or import a short real morning if you want to add visible evidence. Review its text and uncertain screens. Screen Time and recording proposals remain separate suggestions; neither silently replaces an approved routine.
3. Review/edit the moments, their destinations and budgets; approve. Use **Make yourself at home** to choose the supported websites and sign in in one visible queue. Native-app sign-ins stay in those apps. “Ready” is your confirmation, not a cookie-based claim.
4. After a site is ready, **Learn my pace** starts an explicit lesson in MORE's browser. Stop, review the numeric rhythm, and choose **Save to Learn**. No page text, field entries or tap targets are saved by this collector. This is a partial cadence sample, not gesture replay.
5. Start the morning normally. A supported page opens inside MORE or a native app opens through its supported URL. One saved step timer follows it. Use +2 minutes or Next, then finish.

Gmail uses explicit native read-only Google consent, a saved Keychain refresh credential, a bounded plaintext reader and optional local editable reply preparation. It is excluded from embedded website sign-in. Repository defaults remain unconfigured; each developer supplies matching local OAuth settings. The owner's configured ordinary build has real sign-in/count/reading confirmation; generated reply/copy and a complete run remain separate gates. [Gmail flow and limits](GMAIL-READING.md).

The hackathon proof is the owner doing this in the ordinary app, with actual permissions/data and no test launch arguments. Unit tests and earlier scripted phone checks remain engineering evidence only. Do not present sample routines or automated taps as learned autonomous behavior.

## Design

Cream paper and blue/rust ink retain MORE's light paper appearance even when the system uses Dark Mode. Fine irregular paper grain and a transparent, luminous sunset-inspired sun replace the large regular dots. Local time moves the sun and brings up a crescent at night. One native SF Pro family covers dates, headings and controls. Native SF Symbols and Liquid Glass form the icon-only bottom navigation.

Current source: there are exactly three persistent destinations: Home, Learn before a routine exists (Routine afterward, including a draft), and Settings. Learning opens directly; an existing routine is immediately editable with explicit approval after changes. The one saved routine is reused each day. Tapping the date expands a swipeable strip on Home, using actual saved evidence. Past dates cannot start or advance a morning; browsing a past day pauses active playback. Import/export stays in Settings. The old history hub, starter menu, sample entry and duplicate Home learning action are removed.

The app icon and Live Activity use the dotted sunrise. The Lock Screen stays cream. The Island uses cream/rust marks, a native live countdown and dotted native progress. iOS owns its black enclosure. Custom sun position changes on published state, not a claimed continuous background animation. A quiet-moon concept is an optional comparison, not the chosen production treatment.

## Prior verification on PR #131

- Complete local package suite: **1,209 tests** (4 Health, 572 Core, 633 Apple) across **131 suites** pass.
- Normal signed iOS app and widget build pass with Screen Time and WeatherKit entitlements. Ordinary MORE was installed on the connected iPhone; its existing data was backed up locally before the update. No XCTest runner, test arguments or sample-seeding launch was used for this installation.
- Browser collector has real JavaScript execution checks for nested scrolling, inputs, untrusted events and credential/visibility boundaries. The +2 request now transports an exact string token and preserves replay/stale-deadline rejection.
- Native component renders and two Island concept plates were inspected. They are design proofs, not final iPhone navigation or system-control proof.
- Prior owner evidence: Instagram sign-in in MORE QA and an unread result matching a real unread message. That QA site's session is separate from ordinary MORE.
- Prior device engineering evidence: AlarmKit authorization, schedule and cancellation passed in QA and normal-storage Lab. An older design passed native journeys. These do not prove the final normal-use story.

## Still needs a person on the phone

- Screen Time suggestion approval is now owner-confirmed; retain that source scope and separately validate quality/coverage on additional real observations.
- One real recording/import → local analysis → review → approval, and browser sign-ins/pace lesson.
- Alarm ringing → open MORE, spoken Siri start/Next, audible speech and live Calendar/Weather permissions/data.
- +2 from the Lock Screen after the exact-token fix, then Next/Finish and the visible Island layout.
- End-to-end rehearsal with the chosen real morning, no test runner.

Screen Time is aggregate usage, not every tap. Screen recording supplies visible media, not native touch events. MORE cannot silently monitor or drive all other apps. Detailed recording recognition is sampled and may miss quick actions. Browser rhythm measurement does not yet adapt automatic playback speed. [Apple API conditions and limits](SCREEN-TIME-INTEGRATION.md).
