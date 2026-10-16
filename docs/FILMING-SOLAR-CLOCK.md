# Filming a compressed solar day

Debug builds can compress only the landscape's solar time for a prerecorded
presentation. The palette and decorative sun/moon move through the selected
hours while clouds, weather effects and stars keep their ordinary animation
speed. This is a filming preview, not a change to the iPhone's clock or a claim
about live weather changing during the recording.

Set these launch arguments before starting the app:

```text
--theme-recording-seconds=255
--theme-recording-start-hour=8
--theme-recording-end-hour=19.5
```

Record for 300 seconds to retain 45 seconds of the final scene. The solar
progression clamps at its end; independent ambient animation continues. The
example reaches a sunset and rising moon near the last minute for Paris on
16 October 2026 with the iPhone time zone set to Europe/Paris. Actual transition
times depend on the configured location, date and iPhone time zone. Without a
location, the existing reference solar day applies. Weather cloud coverage can
still reduce star visibility.

Only `--theme-recording-seconds` enables recording. Its allowed range is 10–1800
seconds. Start/end hours accept fractional values between 0 and 24, with start
strictly before end; their defaults are 6 and 23. Invalid or duplicate options
disable the override. When a phase pin is also supplied, recording takes
precedence. There is no separate hold argument.

Complete onboarding and account setup first, then relaunch immediately before
the take: elapsed time starts when the process initializes its theme clock.
The active scene updates solar visuals at 10 Hz until the final frame. Debug
filming keeps the foreground app awake unless privacy blocks work. Existing
background and disappearance cleanup still resets the app's idle-timer request;
no device AutoLock or security setting is modified. An ordinary relaunch without
these arguments restores normal visual time.

Reduce Motion freezes the compressed solar pose and stops its frame updates,
including across background/foreground changes. Turning it off rejoins the
elapsed filming clock; it does not restart the take.

Real provider dates, weather freshness and routine timers are unchanged. No
permission, subscription, account data or cloud route is enabled by these
arguments. The recording type/parser and refresh hook are excluded from Release.
No app-owned UI, accessibility or runtime strings are introduced.

Focused logic verification:

```sh
swift test --filter MorningSolarRecordingTimelineTests
```

These tests cover mapping, endpoint holds, explicit opt-in and malformed input.
A native build and inspection of the selected recorded take are separate
acceptance checks. Signal analysis or a landscape capture cannot establish
provider effects, a completed routine or the identity of a speech provider.
