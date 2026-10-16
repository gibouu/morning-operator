# Single-page iPhone access setup

16 October 2026. The entry offer now leads to one overview of supported iPhone accesses. Each line gives its purpose; expanded details remain available. Accept requests accesses in sequence without intervening app pages. Refusal continues the queue, and Not now skips it. Both paths open the existing unapproved routine preparation.

The independent Settings list is retained. The explicit filming preview uses the same overview and preserves its Screen Time-first request order when supported. Current main's free-entry behavior and activity layout are retained. Health, Contacts, account connections and selected video import keep their dedicated consent flows.

Progress records handled choices rather than system grants. A separate completion flag preserves completed legacy voice setup and resumes only pending choices after interruption. Backgrounding cancels further requests until another explicit tap. Preparing location permission does not wait for GPS.

## Verification

- Shared Swift package: 38 targeted tests passed across permission progress, voice access, location and the concurrently integrated Instagram routing/navigation suites. Includes no GPS request during access preparation and normal location refresh later.
- French/English catalog completeness check passed.
- Thirteen distinct UI scenarios passed across scoped runs on iOS 26.5: one-tap approval, denial, skipping, persistence, interruption, independent Settings choices, Screen Time review, French/English entry, day/night and accessibility text in portrait/landscape. The initial 12-case run passed 11 and exposed a pre-existing wrapper identifier replacing the visible approval button's identifier. A wait-only retry reproduced it. Moving the wrapper identifier onto its actual ScrollView restored the child button identity; the final focused review test passed in 28.874 seconds. The shortened summary and newly integrated free-entry path passed their two final focused scenarios separately.
- A separate fresh iPhone 17e simulator ran the ordinary app without --ui-testing. One Accept tap produced six actual system dialogs in order: location, calendar, reminders, speech recognition, notifications and alarms. After the final dialog, routine preparation appeared. Continuing and relaunching returned Home without another access request or an automatic morning. Native screenshots were visually inspected locally.
- The microphone dialog was not presented in this simulator's grouped voice path; Screen Time is capability-gated and absent in the ordinary simulator build. Their physical-device behavior remains a separate check.

## Evidence boundaries

Permission fixtures exercise the sequence, refusal, persistence, interruption and navigation without changing system grants. They do not prove signed-device Screen Time capability, microphone recognition, StoreKit purchase or live account data. No physical iPhone installation is part of this check. Screenshots and result bundles stay in ignored local work/ files.
