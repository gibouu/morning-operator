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

## Still needs device evidence

No iPhone installation or UI test was performed during this continuation. The
connected phone was locked. There is no installed simulator runtime. Run
`RisoThemeSnapshotTests` on an unlocked device or compatible simulator to inspect
the real iPhone screens. Existing installed data was not touched.

Third-party login, pairing, current DOM selectors, video progression and
backup/restore behavior remain unverified. Neither App Store approval nor the
services' permission is established. See [browser scope](IN-APP-BROWSER.md).

Local notifications handle timer expiry while MORE is suspended. Exact
Dynamic Island expansion and background speech are not guaranteed. AlarmKit,
background interactive controls and Siri phrases still need device checks.
See [Plan B](PLAN-B.md) and [design](DESIGN.md).

Claude's separate review CLI could not authenticate because its OAuth session
expired. Same-model peer reviews do not replace that cross-model review. Keep
the combined pull request draft and unmerged until the remaining checks pass.
