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
| Calendar | Local EventKit read less than five minutes old, correct day/zone and valid selected calendars. The next event boundary can expire the recap sooner. The read time is not a remote-account synchronization timestamp. |
| Weather | Retrieval and conditions times less than 30 minutes old; Apple's expiry can shorten this. Future or inconsistent timestamps are rejected. |
| Both | Midnight, a time-zone change, changed source settings or revoked access require revalidation. Each source can fail independently. Weather requests have a bounded deadline. |

At least one fresh configured source is needed to speak a briefing. When another configured source is missing, the recap says so briefly. With no usable facts, the step waits for the person; it never reports a fabricated success.

During a routine, the recap is pinned to that session and moment. **Repeat** uses those same sentences while they remain valid; refreshing Settings cannot replace them. If they expire, pause and open the current moment, then choose **Update this recap**. That explicit action prepares and reads a new recap without advancing the routine. Resume or Next remains your choice. The supported automatic operation advances only after speech completes.

## What is saved and sent

Only selected calendar identifiers, city name/coordinates and temperature unit are saved in `briefing-settings.json`. Calendar events, weather responses, attribution and prepared speech remain in memory; they are not added to observations, routine history or a training dataset. Full local forgetting removes these settings and clears the transient recap. Corrupt preferences block ordinary changes until you explicitly reset **Your day** settings.

City search sends the query to Apple Maps. Weather retrieval sends the selected coordinates to Apple Weather. These native services use a network connection; they are separate from local Foundation Models inference. No screen recording, OCR, message content or habit evidence is sent in those requests. See [Privacy](PRIVACY.md).

## Developer setup and remaining checks

The app target declares `com.apple.developer.weatherkit`. Its App ID and provisioning profile must also have WeatherKit enabled. Merely adding the entitlement to the source does not establish service authorization. In the current setup, signing reports no connected Xcode account and a cached wildcard profile without WeatherKit. Reconnect the developer account in Xcode → Settings → Accounts, then regenerate signing with the WeatherKit capability. Unsigned compilation does not make an installable build.

The local test providers contain labeled synthetic calendars, cities and conditions. They test selection, source failures, freshness, cancellation, storage and playback identity without reading a person's calendar or contacting Apple Weather. They do not prove real service access, image attribution rendering, microphone operation or listener audibility.

Official references: [EventKit](https://developer.apple.com/documentation/eventkit), [WeatherKit](https://developer.apple.com/weatherkit/), [WeatherKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit), [Weather attribution](https://developer.apple.com/documentation/weatherkit/weatherattribution), [Weather metadata](https://developer.apple.com/documentation/weatherkit/weathermetadata), [MapKit search](https://developer.apple.com/documentation/mapkit/mklocalsearch).
