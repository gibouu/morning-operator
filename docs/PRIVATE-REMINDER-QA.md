# Private exact-reminder proof

This DEBUG-only slice is separate from Long10 and video learning. Its native test is
`PrivateExactReminderJourneyTests/testAbsoluteReminderIsReviewedOnceAndReceivedInItsPinnedSession`.
It imports a manual, synthetic, unapproved one-moment subset, configures its time-only
operation in the ordinary editor, approves it, and prepares the reminder during that session.
The import does not carry an Apple operation or a reminder draft.

Activation requires all of `--ui-testing`, `--fixture-mode`,
`--ui-testing-private-exact-reminder`, `--ui-testing-native-actions`, and one
`--ui-testing-workspace=<UUID>` whose temporary directory matches exactly.
A malformed private request uses a refusing local provider; it cannot select EventKit.
The test also composes the existing closed Gmail/Slack fixtures to prevent live
transport fallback. It does not configure or execute a Gmail or Slack operation.

The normal request, native DatePicker, review and separate confirmation are used.
The test selects 16 October 2026 at 09:25, then requires the actual review to name
`Europe/Paris`. There is no time-zone picker in this form: another observed zone
fails this proof. No host/device preference, process clock, model or oracle is
used to create the provider's received payload. The native picker controls still
need to be observed in the first runtime; an unavailable control fails with AX
and screenshot evidence, rather than writing an app value directly.

An explicit date toggle/edit uses the minute precision displayed by the UI.
Loading a prepared draft, or changing only its title, preserves its original
Date. The test never rounds the received payload to make it match.

The existing synthetic provider retains only the last received reminder and a
counter capped at 24, in memory. Its private accessibility proof includes the
actual title, notes, Date bits, zone, alert and synthetic destination, plus the
session/version/moment observed synchronously at `perform`. Expected values exist
only in the test: `2026-10-16T07:25:00Z`, `Europe/Paris`, the invented notebook
title, empty notes, and an alert. No EventKit permission or write is requested.

The native acceptance gate must show zero writes before review/confirmation,
one received payload afterward, and a durable journal count of one confirmed,
zero unconfirmed, for that same session. On relaunch the in-memory count restarts
at zero and no payload is restored, while the original session and its journal
count remain. This separates a saved receipt from a new transport call.

Status: source, pure regression and native test prepared; no build or runtime
result claimed. The exact-reminder gate does not establish acoustic voice,
live Apple writes, learning from the movie, Long10 completion or MORE §10.
