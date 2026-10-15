# MORE continuation — 15 October 2026

The interrupted browser, Plan B and riso workstreams are combined on
`feat/126-resume-morning`. Their feature branches remain available. No changes
from the older Screen Time, extras or tethered-demo pull requests were merged
as part of this continuation.

## Try the new flow

1. Open Review, then your routine, and edit a moment.
2. Under **During this moment → Open**, choose a site **In MORE** or another app.
3. Save and approve the changed routine, then start it normally.
4. A website moment opens inside MORE. Close and **Open page** returns to it with
   the same budget. **+2 min** and **Next step** use the saved session and step.
5. Settings contains **Morning alarm** and **Shortcuts & timers**. Empty shortcut
   template links stay hidden; no ready-to-add templates have been published.

Website reads and scroll requests each require a tap. There is no automatic
scrolling or social-write script. The person signs in on the website itself.
Global Forget also clears MORE's dedicated website store. Test workspaces use
separate routine, timer, notification and website-store namespaces.

## Verified

- Complete local Swift package suite: 629 tests in 69 suites pass.
- Four JavaScript execution checks cover foreign sign-in redirects, inline
  password forms, feed-route changes and the end of a feed. Three reproduced
  defects in the recovered browser checkpoint and pass after the fixes.
- Generic iOS Simulator `build-for-testing` passes for app, widget and UI tests.
- String-catalog audit reports zero keys without French.
- Focused peer reviews found timer/notification/privacy races; the fixes were
  reviewed again with no remaining concrete findings in those paths.
- Two revisions of native macOS theme/component proofs were rendered and
  inspected. They are not screenshots of the iPhone app.
- Physical iPhone checks now pass in the separate `MORE QA` bundle:
  Home/running routine in all five phases; first use, Learn, Settings, briefing,
  Privacy and Review in English light and French dark appearances; and editing,
  approving, extending, closing/reopening and advancing a web moment.
- Twenty-four synthetic device screenshots were captured and visually checked.
  The first Privacy snapshot assertion expected an offscreen lazy row; it was
  corrected to verify the visible inventory, then the screen journey passed.
- The owner signed in to Instagram inside MORE QA and confirmed MORE's unread
  report matched an actual unread message. No exact count or private account
  content was captured; this is owner-confirmed evidence.

## Device scope and remaining checks

The owner unlocked the connected iPhone. A signed QA app uses bundle identifier
`com.gibouu.morningoperator.qa`, its own widget/test identifiers and a separate
`moreqa` URL scheme. Its temporary build omits WeatherKit entitlement and uses
synthetic briefing data. The original MORE installation and saved data were
not replaced. There is still no installed simulator runtime.

The native checks do not establish external app handoff, lock-screen Next URL
routing, AlarmKit, Siri, speech, live Calendar/Weather or the installed Screen
Time build. Those need separate checks using the corresponding capabilities.

Other third-party logins, pairing, selector accuracy across layouts, video
progression and backup/restore behavior remain unverified. Neither App Store
approval nor the services' permission is established. See [browser scope](IN-APP-BROWSER.md).
Le Monde loaded its own consent/subscription choice in WKWebView; no consent
choice or headline extraction was performed. Instagram sign-in and one matching
unread result are owner-confirmed; feed progression remains unverified.

Local notifications handle timer expiry while MORE is suspended. Exact
Dynamic Island expansion and background speech are not guaranteed. AlarmKit,
background interactive controls and Siri phrases still need device checks.
See [Plan B](PLAN-B.md) and [design](DESIGN.md).

Claude's separate review CLI could not authenticate because its OAuth session
expired. Same-model peer reviews do not replace that cross-model review. Keep
the combined pull request draft and unmerged until the remaining checks pass.
