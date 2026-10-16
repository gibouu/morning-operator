# Cloudflare Workers Free + D1

**Status: updated on Workers Free + D1, 16 October 2026.** Origin: `https://more-composio.more-gderamchi.workers.dev`. Current version: `8eaf7dde-56e2-48bc-b598-3fc82777ce99`, a targeted final-1630 installation activation preserving the TTS runtime deployed as `b623c00b-4c3a-4166-bae8-63cf75790278` from `e245094f347592403334dbb0451b03066b214efa`. Sixteen configured services, account-bound Slack routes, the installation-gated ElevenLabs WebRTC token broker and bounded text-to-speech remain available. The previous 51 local Node/Workerd tests passed; no full backend suite was rerun for this allowlist-only change. Live synthesis returned MPEG audio for all four French/English × male/female choices, with provider logging explicitly disabled. The broker still returns a token only for an activated installation. Final-1630 fixed-sample primary playback is physically accepted; microphone conversation remains separate. OAuth/provider evidence is recorded in [CONNECTIONS.md](../../docs/CONNECTIONS.md).

At 11:11 Paris time, a fresh support code from the ordinary **2026101630** phone installation matched exactly one D1 identity. Only that identity was appended, taking the voice allowlist from two entries to three and preserving both previous activations. Live readback confirmed every other binding unchanged, including three secret bindings and D1; service/catalog/execution aggregates and canonical runtime source were preserved. The subsequent physical test passed all four complete primary samples without Apple backup, with owner-confirmed audibility and better quality. [Exact 1630 evidence and boundaries](../../docs/ELEVENLABS-1630-ACCEPTANCE-2026-10-16.md).

The deployment preserved the production configuration, D1 binding, all secrets, one approved QA installation, 16 public catalogs (2,824,019 bytes) and the business execution journal (two rows before and after). One additional synthetic QA installation remains inactive to verify the live `503` gate; the owner was not automatically activated. Smoke results: unauthenticated `401`, inactive `503`, malformed/unsupported-language `400`, approved speech `200 audio/mpeg` with `no-store`, conversation token `200`, and health/services `200` with sixteen services. No migration, plan change or provider business action was performed. Generated audio, credentials, installation identities and detailed deployment evidence remain private.

The subsequent activation update identified the ordinary iPhone through the support code displayed by that installation, without exposing its bearer or correlating timestamps/accounts. It added exactly that existing installation to the voice allowlist (one to two), preserving the previous activation, all sixteen services, three secrets, D1 and other bindings. It changed no runtime source, account assignment or provider business data. Identifiers and support codes remain private.

The ordinary iPhone app calls this HTTPS service directly. After the app is installed and configured, no Mac, local server or XCTest runner is part of the runtime. This backend does not change app signing/distribution requirements. The mobile REST and authenticated OAuth completion contract remain the same as [README.md](README.md). The public origin goes into the app's `MORNING_API_BASE_URL`; the Composio project API key never enters the app.

## Free plan boundaries

Published limits checked on 15 October 2026:

| Resource | Free allowance or limit |
| --- | --- |
| Workers requests | 100,000 per day |
| Workers CPU | 10 ms per HTTP request; waiting for network/database I/O is excluded |
| D1 rows read | 5 million per day |
| D1 rows written | 100,000 per day |
| D1 storage | 500 MB per database; 5 GB across the account |

These are account/plan quotas, not a guarantee that this connector will always cost $0. Other apps share allowances; Composio and individual providers have their own quotas, eligibility and possible charges. Stay on Workers Free unless a paid change is explicitly intended. Exceeding a Free limit can make requests fail. Measure CPU with the real catalog and representative payloads: a 20-second upstream deadline does not increase the 10 ms CPU allowance. See [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) and [D1 limits](https://developers.cloudflare.com/d1/platform/limits/).

## Configuration and deployment

The entry point is `cloudflare/worker.mjs`; it uses a native Fetch adapter around the same policy/router as the Node server. Runtime bindings are initialized inside `fetch`, not at module evaluation. Storage uses `cloudflare/storage.mjs` and migrations `0001_storage.sql`, `0002_public_catalogs.sql` and additive `0003_voice_activation.sql`. The tracked `wrangler.example.jsonc` supplies the `DB` binding and `more-composio` Worker/database names. Node compatibility remains needed for crypto/Buffer; the inherited HTTP-server compatibility flag is harmless but unused by the native adapter. Copy the template to ignored `wrangler.jsonc` for actual deployment configuration. `HOST`, `PORT` and `MORE_DATA_DIR` belong to the Node server and are not Worker storage settings.

Run from `Services/Composio` with Node 22+ and an authenticated Cloudflare account on Workers Free. `npm ci` installs the locked development/deployment tools; the following `npx --no-install` commands use that version. For an existing deployment, retain its configuration/database ID and skip creation and copying.

```sh
cd Services/Composio
npm ci
npx --no-install wrangler whoami
npx --no-install wrangler login --use-keyring --scopes account:read user:read workers_scripts:write d1:write
npx --no-install wrangler d1 create more-composio --jurisdiction eu --config wrangler.example.jsonc --update-config=false
cp -n wrangler.example.jsonc wrangler.jsonc
```

In `wrangler.jsonc`, set `d1_databases[0].database_id` from the creation result and preserve `binding: "DB"` and `migrations_dir`. Set the public origin using the account's actual `workers.dev` subdomain or configured custom domain. Then set the toolkit map and callback values below. Never deploy the placeholder configuration.

```sh
npm test
npx --no-install wrangler d1 migrations apply DB --local --config wrangler.jsonc
npx --no-install wrangler deploy --dry-run --config wrangler.jsonc
npx --no-install wrangler d1 migrations apply DB --remote --config wrangler.jsonc
npx --no-install wrangler secret put COMPOSIO_API_KEY --config wrangler.jsonc
# Prepare and apply public catalogs using the runbook below before deploying:
node --env-file=.env cloudflare/bootstrap-catalogs.mjs
node --env-file=.env cloudflare/bootstrap-catalogs.mjs --apply .wrangler/public-catalogs.json
npx --no-install wrangler deploy --config wrangler.jsonc
curl --fail --silent --show-error https://YOUR_DEPLOYED_ORIGIN/health
```

The `secret put` command prompts privately and may offer to create the named Worker before its first deployment. Review the target account/name. Keep the database ID and non-secret deployment configuration outside shared logs. See the official [D1 CLI commands](https://developers.cloudflare.com/d1/wrangler-commands/).

Configure the existing real toolkit map with each toolkit's name, auth-config ID and pinned version. Keep the production callback `more://composio/callback`; reserve `moreqa://composio/callback` for a separate QA deployment. Set `MORE_PUBLIC_BASE_URL` to the exact public HTTPS origin, with no path, query or credentials.

Store `COMPOSIO_API_KEY` only as a [Worker secret](https://developers.cloudflare.com/workers/configuration/secrets/). Enter it through the secret prompt; never put it in a command argument, Wrangler variables, source, D1, app build settings or logs. Deployment account credentials are separate from this Composio project secret. Do not copy the local `.env` into the Worker bundle.

In the Composio project, enable callback identity verification and configure its URL as `https://YOUR_DEPLOYED_ORIGIN/v1/oauth/callback`. This verifier forwards an opaque session to the native app; the authenticated `/v1/connections/complete` call must still finish authorization. Reuse the detailed [OAuth setup](README.md#oauth-setup-is-required).

## Activate cloud conversation

Keep the existing ignored `wrangler.jsonc`, database ID, sixteen-service map, callback configuration and Composio secret. Apply the additive migration before deploying the activation-request route. Store both ElevenLabs values as Worker secrets through private prompts (or `secret bulk` with a JSON object on stdin); never put them in arguments, shared files, app settings or Wrangler vars:

```sh
npm test
npx --no-install wrangler d1 migrations apply DB --remote --config wrangler.jsonc
npx --no-install wrangler secret put ELEVENLABS_API_KEY --config wrangler.jsonc
npx --no-install wrangler secret put ELEVENLABS_AGENT_ID --config wrangler.jsonc
npx --no-install wrangler deploy --config wrangler.jsonc
```

`MORE_VOICE_INSTALLATIONS_JSON` defaults to `[]`. A refused authenticated `POST /v1/voice/token` with `{}` records only `user_id` and `requested_at` in D1; it contacts no voice provider. Review these requests privately. Verify the intended device/owner through a trusted channel, then add only that generated installation ID to the private allowlist and redeploy. Do not approve every row or every newly enrolled installation. Removing an ID blocks future token minting; it does not revoke an already issued token or terminate an existing provider conversation.

For acceptance, reuse one private QA installation. Verify unauthenticated `401`, invalid-body `400`, unapproved `503`, then approved `200` with exactly one `conversationToken` field and `Cache-Control: no-store`. Keep the token and permanent secrets out of logs; record only status, response-field names and token length. Check that all existing public catalog bytes, execution-journal rows, prior configuration and the Composio secret remain present. An emitted token proves the server-to-provider path; it does not prove audio, interruption, consent UI, subscription verification or a physical-iPhone conversation.

The broker uses the [WebRTC token endpoint](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token), not the WebSocket signed-URL endpoint. The private agent's privacy/model settings must be verified with the provider separately; minting a token alone does not validate those settings. No provider audio or source data is sent by these acceptance requests.

## Refresh public catalogs

The Worker serves a precomputed JSON string from `public_catalogs`, keyed by toolkit slug and exact configured version. It authenticates the installation before reading this row. A missing version returns `503 catalog_unavailable` with no live catalog fallback. This removes provider pagination, parsing and normalization from the request CPU budget; `/execute` still rechecks current account ownership and tool metadata with Composio.

Run from `Services/Composio` with the real ignored `.env` and existing ignored `wrangler.jsonc`. Keep their toolkit/version maps aligned. Preparation only reads public Composio tool definitions; applying writes those definitions to the existing D1 database:

```sh
node --env-file=.env cloudflare/bootstrap-catalogs.mjs
npx --no-install wrangler d1 migrations apply DB --remote --config wrangler.jsonc
node --env-file=.env cloudflare/bootstrap-catalogs.mjs --apply .wrangler/public-catalogs.json
```

The first command prepares all configured services before writing a local ignored snapshot. The explicit `--apply` mode validates configured slugs/pins and schema shape, obtains Cloudflare credentials through the installed Wrangler CLI in memory, and upserts each row with bound parameters. It prints service/count/status metadata only. It creates no account, grant, installation or execution. If it fails, inspect the reported stage and reconcile the existing catalog rows before continuing; it does not broaden OAuth scopes or retry automatically. Each public row replacement is atomic; a partially completed batch leaves other service/version rows unchanged. Do not delete installation or execution tables during catalog refresh.

D1 limits a row/string to 2,000,000 bytes and SQL text to 100,000 bytes. The bootstrap caps each payload at 1,900,000 bytes and binds the payload as a parameter rather than embedding it in SQL. The 16 configured catalogs contain 1,152 tools and 2,824,019 bytes total; Outlook is largest at 761,902 bytes. YouTube adds 59 tools / 99,150 bytes and Reddit adds 33 tools / 44,186 bytes. No generated catalog is committed. See [D1 limits](https://developers.cloudflare.com/d1/platform/limits/) and the [parameterized query API](https://developers.cloudflare.com/api/resources/d1/subresources/database/methods/query/).

## Persistence and privacy

D1 must retain installation identities and the execution journal across Worker updates and restarts. A unique `(userID, requestID)` reservation must commit before any external tool dispatch. The fingerprint rejects a changed action under the same ID. Raw tool arguments and provider results are transient: do not store them in D1 or logs. Store only the token hash, generated identity/request IDs, fingerprints, execution state and sanitized receipt metadata. Replayed receipts omit provider data and return `resultAvailable:false`.

An interruption after dispatch can leave an uncertain outcome. Never delete or reset a reservation, retry under a new UUID, or replace the database merely to bypass that uncertainty. Inspect the provider's actual state before another reviewed attempt. Duplicate protection is not an exactly-once guarantee at the external provider.

The separate `public_catalogs` table contains only public tool descriptions and JSON Schemas. It contains no connected-account metadata, installation bearer, user arguments or execution results. The Worker's filesystem is temporary and cannot substitute for D1 persistence. Preserve the same database binding/ID during redeployment and rollback. Restoring an older database snapshot can also discard recent reservations; reconcile actions since that snapshot before resuming execution. Define metadata retention and erasure before public release. Forgetting the iPhone token does not erase server metadata or revoke provider grants.

Keep Worker request logging/observability off for sensitive flows. Do not enable body, Authorization-header or OAuth query logging, and do not use `wrangler tail` during real consent or tool actions. Platform metadata handling must be reviewed separately; application code avoiding logs does not prove that every hosting layer retains nothing.

## Broker evidence, 16 October 2026

`npm test` passed 44/44 Node and actual Workerd/Miniflare+D1 tests. The new cases prove that a configured but unapproved installation creates only one activation-metadata row across isolates/restarts, with no provider request; an approved synthetic installation obtains only a WebRTC token. The activated Workerd case reproduced a real `502` caused by unsupported Fetch `redirect: "error"`; `manual` plus explicit rejection of non-2xx responses fixes it without following redirects. Synthetic timeout fixtures now allow dispatch to occur on a loaded development machine; the product's twenty-second Composio deadline is unchanged.

On version `afade250-210b-42a4-ba34-b6821327c613`, the live smoke returned health `200`, authenticated services `200` with sixteen registrations, voice `401` without authentication, `400` for a client-selected agent, and `503` before explicit QA activation. The refused request persisted only generated identity/time metadata. After activating that same QA identity, the route returned `200`, exactly `conversationToken`, length 1,039, and `no-store`; no permanent key appeared in the response. No token or installation identity is recorded in this runbook. Only that QA installation is allowlisted. The existing sixteen public catalogs (2,824,019 bytes) and execution-journal row count remained unchanged; the prior Composio secret and both new voice-secret names were verified. These requests sent no audio, Health samples or source context. Provider-agent configuration and a successful token are separate from actual device conversation/interrupt behavior.

## Local evidence, 15 October 2026

`npm test` passed all 26 tests: twelve Node HTTP tests, eight actual Workerd/Miniflare+D1 tests, two bootstrap tests and four read-smoke helper tests with synthetic provider/OAuth/API responses. They cover two isolates, atomic reservations, restart persistence, metadata-only receipts, uncertain results without repeated effects, OAuth/account isolation, conditional custom-social activation, throttling, runtime initialization, a large verbatim catalog, stale/missing-pin rejection without provider fallback, and parameterized catalog writes without credential output. These checks use synthetic provider data and do not establish real provider OAuth or physical-iPhone behavior.

## Production evidence and CPU limits

The existing test installation survived successive deployments on the same D1 database. Public catalog bootstrap applied all 16 rows to that database; the installation and execution journal were preserved. The prior native Fetch version still spent approximately 17.372 ms CPU on Gmail's live catalog and 93.235 ms on Outlook's. Lightweight routes in the same bounded sample used 1.926 ms (`/health`) and 3.817 ms (`/v1/services`). This motivated the precomputed catalogs.

GraphQL `cpuTime*` values are in microseconds; divide by 1,000 for milliseconds. Cloudflare documents that CPU rollover can allow high percentiles above the nominal limit without invocation errors. Therefore zero errors does not prove a 10 ms safety margin. See [Workers metrics](https://developers.cloudflare.com/workers/observability/metrics-and-analytics/#cpu-time-per-execution) and [GraphQL query guidance](https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-workers-metrics/).

On version `b6f38bcb-69f1-4387-9fe3-2698767b7400`, a bounded production smoke at 15:35:34–15:35:58 UTC returned HTTP 200 for `/health`, `/v1/services` and all 14 catalogs. All 1,060 tool schemas validated. GraphQL associated each request with that exact version, zero invocation errors and zero provider subrequests. The same existing QA installation bearer was used; no grant or provider tool was executed.

| Route/service | Observed CPU, ms |
| --- | ---: |
| `/health` | 3.095 |
| `/v1/services` | 5.920 |
| Gmail | 4.855 |
| Google Calendar | 6.867 |
| Outlook | 13.340 |
| Google Drive | 7.454 |
| Google Docs | 4.302 |
| Google Sheets | 6.196 |
| Notion | 7.000 |
| Slack | 6.128 |
| Calendly | 3.347 |
| Instagram | 3.479 |
| WhatsApp | 3.561 |
| LinkedIn | 2.538 |
| Discord | 2.013 |
| Facebook | 3.116 |

These are single observations per route, not a load test or guaranteed percentile. Catalog preprocessing removed the large provider-processing cost, but Outlook still exceeded the nominal 10 ms allowance in this sample and completed successfully through the runtime's tolerance. Keep this limitation visible: the current Free plan is verified, while reliable CPU headroom for every cold start, external action or payload is not. No paid upgrade was made.

On version `164a0ca0-39f8-4d6b-b944-ff1b7bfa9496`, a four-request smoke at 16:05:56–16:06:00 UTC returned HTTP 200 for `/health`, `/v1/services` and the new YouTube/Reddit catalogs. The registry contained exactly 16 services and omitted the still unconfigured X/TikTok toolkits. Both new catalogs' 92 schemas validated; the existing QA installation token remained valid. GraphQL returned three corresponding invocation records for that exact version: health 2.561 ms, YouTube 2.958 ms and Reddit 2.801 ms CPU, each with zero runtime errors/provider subrequests. The services invocation had not appeared in that metrics response. These individual observations do not establish a general Free-tier CPU guarantee. No user consent flow or provider tool action was performed.

## Acceptance checks

1. Run the package's Node and Worker tests against a synthetic upstream, including concurrent duplicate dispatch, changed-payload rejection and interrupted execution. These are local checks only.
2. After deployment, check `/health` over HTTPS. This proves service reachability only. Verify required secrets, toolkit configuration and D1 schema separately without printing their values.
3. Create a dedicated test installation and verify that its identity and replay receipts survive redeployment with the same D1 database. Keep bearer tokens and request contents out of shared reports.
4. Configure the app with the public origin. Complete one reviewed provider OAuth flow on the normal iPhone, then confirm the authenticated account is active and owned by that installation. Cloudflare login and Composio catalog discovery do not substitute for this grant.
5. Run a harmless, reviewed provider read and verify its actual result. Exercise ambiguous outcomes with the synthetic upstream, not by repeating a real external write. Record cloud reachability, D1 persistence, OAuth, provider execution and physical iPhone evidence separately.

Before public exposure, apply enrollment/API abuse limits, inspect actual scopes and provider eligibility, and monitor Worker CPU/request and D1 row/storage usage. No automated identity recovery, grant rotation or uncertain-action reset is supplied by this prototype.
