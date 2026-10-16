# Private second-article WebKit journey

This is a DEBUG document-input fixture for MORE's ordinary browser planner,
executor, contextual article selection and session timer. It proves neither
learning from the video nor operation on a real news service. MORE §10 remains
open. The v1 scenario, oracle, videos and compact contrast are unchanged.

Activation requires `--ui-testing`, `--fixture-mode`,
`--ui-testing-private-news` and exactly one valid
`--ui-testing-workspace=<UUID>`. The active data directory must equal that
UUID's isolated temporary workspace. The scheme is not registered as an iOS
URL entry point, is not a portable target and has no ordinary UI entry.
Standalone browsing/learning cannot activate it. An incomplete requested
activation refuses loading rather than opening the real news website.

The approved ordinary news target/behavior is configured through the editor.
Only its private document input is replaced with `more-qa-news://<UUID>`.
The four registered HTML resources contain invented Cedar News material from
the scenario, not a model output or an oracle passed to learning. WebKit uses a
nonpersistent data store. The handler has no network client, credentials,
filesystem resource lookup, redirect or fallback. The pages forbid scripts,
network resources, frames and form submission via CSP; native navigation and
the isolated DOM scripts independently admit only the exact private origin and
registered resource paths. HTTPS policy stays unchanged outside this explicit
capability. A local URLResponse is checked as a local delivery, never labelled
HTTP 200.

`PrivateNewsReadingJourneyTests` imports one manual, unapproved synthetic
moment, selects its page and read-headlines behavior through ordinary UI,
approves, and relaunches without the import payload. It then conveys the user
choice through MORE's native second-title control, which enters the existing
article utterance route. XCTest does not tap a DOM link, scroll the article for
the agent, change the session or call Store methods. MORE reobserves the links,
navigates, verifies the local destination and extracts rendered article text.
The test checks the independent exact paragraph, retained-body repeat without
another resource load, and return/resume with the same session/version/step
and exact paused timer instants. EN/FR are explicitly forced in the test
argument domain; these are not first-launch language tests or acoustic tests.

Core contracts cover missing flags, duplicate/wrong workspace, unregistered
resources, network URLs, opaque-origin confusion, stale links and page/session
changes. Ordinary HTTP destination/status refusals remain in their existing
tests. No browser feed, media, story, like, real account or provider send is
included in this slice.

Validation status: source and contracts prepared only. No build, package test,
native execution, model call, HTTP check or audible reading has been run for
this slice. Integration and runtime gates are coordinated by the parent task.
