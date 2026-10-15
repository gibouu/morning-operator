# Your day

A short calendar and weather recap before the rest of your morning. This feature is part of the V2 development branch; see [verification](PHASE-ONE.md) for the tested source and remaining device checks.

## Set it up

1. Open **Review → Settings & connections → Your day**.
2. Choose **Connect Calendar** and approve Apple's read permission if you want calendar context. Then select the individual calendars to include. No calendar is selected automatically.
3. Optionally search for a city and select a result. Choose Celsius or Fahrenheit. Device location isn't requested.
4. Read the prepared recap or choose **Hear this recap**. **Refresh recap** updates this preview without advancing your routine.
5. If you already have a routine, choose **Add to my morning**. This creates a new draft with **Your day** first. Review and approve that draft before running it.

You can also edit a moment and choose **Read today's briefing**, or **Read today's calendar** for calendar-only speech. These are explicit operations; a model suggestion cannot grant itself permission to run them. Adding a briefing is optional, and unavailable sources do not prevent manual continuation.

## What it says

The same prepared sentences appear on screen and go to Apple's system speech. Calendar context includes all-day events, events in progress and upcoming events in your selected calendars. Completed events are omitted. The recap includes up to five events and states how many remaining events were omitted. A valid empty result says there are no remaining events in the selected calendars; a denied or failed read never becomes an empty schedule.

Weather describes current conditions in the chosen city, with an explicit temperature unit. It is not a whole-day forecast. The visible recap includes Apple Weather attribution and a data-sources link. The actual Apple image asset, live WeatherKit access and audio output still need signed-device verification.

Prepared prose currently supports English. Event titles retain their original language. The separate on-device habit model does not summarize or rewrite these facts.

## Freshness and playback

MORE prepares configured sources when the app enters the foreground, then checks them before playback. It does not promise overnight background preparation or waking the phone automatically.

| Source | Freshness rule |
|---|---|
| Calendar | Local EventKit read less than five minutes old, correct day/zone and valid selected calendars. A known EventKit store change invalidates playback admission and the next refresh re-reads the range. The next event boundary can expire the recap sooner. The read time is not a remote-account synchronization timestamp. |
| Weather | Retrieval and conditions times less than 30 minutes old; Apple's expiry can shorten this. Future or inconsistent timestamps are rejected. |
| Both | Midnight, a time-zone change, changed source settings or revoked access require revalidation. Each source can fail independently. Weather requests have a bounded deadline. |

At least one fresh configured source is needed to speak a briefing. When another configured source is missing, the recap says so briefly. With no usable facts, the step waits for the person; it never reports a fabricated success.

During a routine, the recap is pinned to that session and moment. **Repeat** uses those same sentences while they remain valid; refreshing Settings cannot replace them. If they expire, pause and open the current moment, then choose **Update this recap**. That explicit action prepares and reads a new recap without advancing the routine. Resume or Next remains your choice. The supported automatic operation advances only after speech completes.

## Sleep duration (logic only, not connected)

Sleep duration is the one health observation chosen for [issue #15](https://github.com/gibouu/morning-operator/issues/15). The shared logic exists and is tested with synthetic samples. **The app reads no health data today**: it has no HealthKit entitlement, no usage description, no screen for the choice, and it does not link the module that imports HealthKit (`MorningHealth`). That module's reader has never run against real data. A device check is still to do.

What the logic does once a reader is connected:

- **The choice.** Health is included or excluded on its own, apart from calendar and weather. It is off until the person turns it on. While it is off the reader is not called.
- **The sentence.** One sentence, the same on screen and in speech: the time recorded as asleep and the window it was recorded in, for example "Sleep recorded: 7 hours 20 minutes, between 23:40 and 07:00." No score, no judgement, no advice, no comparison with a recommended amount. A window of a day or more, possible in a recap prepared in the evening, gives each end its date as well.
- **The total.** Samples in an asleep stage that ended after 18:00 yesterday are merged, so a span recorded by two sources counts once, then added. "In bed" and "awake" add nothing, and a single span longer than 24 hours is ignored. The duration is elapsed time, so a night across a clock change is an hour longer or shorter than its two clock times suggest.
- **What the total cannot know.** Whether it was one sleep or several: a nap after 18:00 yesterday is inside the total, and the window shows it. Which source is right when two disagree: a minute counts when any source recorded it as asleep, so the total can exceed the Health app's, which applies a source order that HealthKit does not expose. A night with only "in bed" samples has no asleep record.

| State | On screen | Spoken |
|---|---|---|
| Health excluded | "Sleep is not included." | Nothing |
| No health data store on this device | "Health data is not available on this device." | Nothing, never a zero |
| No asleep record since yesterday evening | "No sleep record was found since yesterday evening." | The same sentence, when the recap has another fact |
| The newest record is older | "The latest sleep record ended on 9 October at 07:00." | The same sentence |
| The read failed or did not answer in 10 seconds | "Sleep data could not be read." | The same sentence |
| The read is more than 30 minutes old | "Sleep data needs a fresh update." | The same sentence |

No sentence says that permission was refused. HealthKit answers a refused read with no samples and no error, so "no record" can also mean the read was not permitted or the watch has not synced yet.

**Expected sources.** An Apple Watch worn at night records sleep stages. An iPhone alone records mostly "in bed" time from a sleep schedule, which is not counted. Other apps and entries typed in the Health app may record asleep time. The source kind (watch, phone, another app, manual entry, unknown) is worked out from the source's bundle identifier, its hardware model string and the "entered by the user" flag; HealthKit has no field that states it. An iPad or a Mac may have no health data store. None of this coverage has been checked on a device.

Samples, the total and the sentence stay in memory. Only the on/off choice is saved, in `briefing-settings.json`.

## What is saved and sent

Only selected calendar identifiers, city name/coordinates, temperature unit and the health on/off choice are saved in `briefing-settings.json`. Calendar events, weather responses, attribution and prepared speech remain in memory; they are not added to observations, routine history or a training dataset. Full local forgetting removes these settings and clears the transient recap. Corrupt preferences block ordinary changes until you explicitly reset **Your day** settings.

City search sends the query to Apple Maps. Weather retrieval sends the selected coordinates to Apple Weather. These native services use a network connection; they are separate from local Foundation Models inference. No screen recording, OCR, message content or habit evidence is sent in those requests. See [Privacy](PRIVACY.md).

## Developer setup and remaining checks

The app target declares `com.apple.developer.weatherkit`. Its App ID and provisioning profile must also have WeatherKit enabled, including the App ID's WeatherKit app service. Merely adding the entitlement to source does not establish service authorization. Earlier missing-account/wildcard-profile reports are historical; newer [current direction](CURRENT-DIRECTION.md) records a signed build with WeatherKit. This audit does not recheck that account/profile or establish a live WeatherKit response. Unsigned compilation does not make an installable build. See the [connection evidence](CONNECTION-EVIDENCE.md) for per-service requirements and remaining owner checks.

The local test providers contain labeled synthetic calendars, cities and conditions. They test selection, source failures, freshness, cancellation, storage and playback identity without reading a person's calendar or contacting Apple Weather. They do not prove real service access, image attribution rendering, microphone operation or listener audibility.

Official references: [EventKit](https://developer.apple.com/documentation/eventkit), [WeatherKit](https://developer.apple.com/weatherkit/), [WeatherKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit), [Weather attribution](https://developer.apple.com/documentation/weatherkit/weatherattribution), [Weather metadata](https://developer.apple.com/documentation/weatherkit/weathermetadata), [MapKit search](https://developer.apple.com/documentation/mapkit/mklocalsearch).
