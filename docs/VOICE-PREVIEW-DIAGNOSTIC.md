# Fixed voice sample: provider receipt

The DEBUG-only accessibility element `voice.preview.receipt` appears after
**Settings → Voice → Listen**, only with both `--ui-testing` and
`--ui-testing-real-voice-provider`. It describes only the app's bundled sample.
It contains no narration text, token, installation ID, provider error prose or
account data, and is never persisted. Closing, stopping, changing language or
gender, entering a session, backgrounding and privacy invalidation clear it.

Use one stable isolated workspace and the ordinary Composio service for the live
simulator check. Do not combine it with Gmail/Slack/calendar service-fixture
flags. `--fixture-mode` always disables the voice network, even with the real
provider flag. No microphone or conversation is needed; this sample does not
authorize uploading routine content. A morning's narration sharing still needs
its own visible consent.

## Native checks

Test contract ID: `natural-voice-fixed-preview-receipt-v1`. Observe the actual
Listen control `voice.preview`, then its receipt; do not infer a provider from
“Speaking…” or absence of the backup message alone.

| Scenario | Required receipt fields |
| --- | --- |
| Ordinary service, activated installation, provider audio played to completion | `selected=elevenLabs validatedMPEGResponse=1 drainCompleted=1 fallback=0 result=completed category=none` |
| Same real-provider flag plus `--fixture-mode` | `selected=directApple validatedMPEGResponse=0 drainCompleted=1 fallback=0 result=completed category=none`; no speech HTTP request |
| Authenticated installation refused activation, then Apple backup completes | `selected=elevenLabs validatedMPEGResponse=0 drainCompleted=1 fallback=1 result=completed category=activationRequired` |
| Validated remote audio followed by local playback failure and successful Apple backup | `selected=elevenLabs validatedMPEGResponse=1 drainCompleted=1 fallback=1 result=completed category=playback` |
| Stop, gender/language change, background or Forget while pending | Receipt cleared; late results cannot republish it or complete a replacement preview |

`validatedMPEGResponse=1` means the ordinary client accepted a successful HTTP
response with MPEG MIME/signature and size bounds. Its API does not expose the
exact status, so this receipt never claims HTTP 200. `drainCompleted=1` is set
only after the same `speakAndWait` returns successfully; with `fallback=1`, it
describes the Apple backup's completion. It does not prove audible speaker output,
listener quality, microphone input or any business action.

Existing shared boundary tests are `MorningSpeechServiceTests` (selected fields,
installation bearer, validation, sanitized activation refusal and stale response)
and `SpeechCloudOutputTests` (drain, fallback, cancellation and no retry). They use
injected transports/audio and require no provider credentials. They do not validate
this new app receipt or establish live connectivity. Native receipt checks and
current provider access must be recorded separately.

## Exact installation activation remains an operator action

No activation is performed by this diagnostic. A refused authenticated sample
records a content-free activation request on the server. On that same simulator
workspace, open an account-management page in **Settings → Connections**, then
**Shared data → Connection details → Show installation code**. This exposes
the existing installation's support code, without enrolling a replacement. An
authorized operator must correlate that code with the exact private server
installation/request, verify the intended owner, preserve all existing allowlist
entries, add only that identity to `MORE_VOICE_INSTALLATIONS_JSON`, and deploy
through the existing process. Never approve every pending request or put tokens,
support codes or installation IDs in shared logs. See the activation section of
[the Worker runbook](../Services/Composio/CLOUDFLARE.md#activate-cloud-conversation).

Preparation evidence: source parse and diff checks only. No native playback,
provider call or activation is implied by this document.
