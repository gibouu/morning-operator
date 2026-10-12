# MORE: business hypotheses and validation

**Working brief · 10 October 2026.** MORE is the current product name; LEVE remains a naming candidate with known App Store search collisions. This document proposes an offer and a way to test it. It does not announce prices, claim customers or revenue, or turn unfinished capabilities into a paid promise. [Product direction](PRODUCT-DIRECTION.md) · [Actual verification](PHASE-ONE.md).

## The proposition

**A morning companion that learns your routine, prepares what matters and lets you spend less time managing your phone.** Connect the sources you choose, share a few mornings, review the plan, then hear a short opening and use supported voice controls. Keep the rituals you enjoy. Open the app for inspection or a meaningful change rather than repeating setup every day.

The product hypothesis is that this ongoing service earns a subscription through reliable preparation and reduced friction. It is not primarily selling a timer, another dashboard, or an instruction to be more productive. A quiet manual experience remains useful while broader automation develops.

The proposed advantage is the combination of an inspectable learned plan, user choices that persist, source/freshness-aware narration, and low-effort daily use. These are reasons to test the offer, not proven market differentiation. Existing shortcuts, calendar/weather widgets, voice assistants and manual routines are the alternatives interviewees should compare against.

## Initial customer and jobs

Start with **adults who use a compatible iPhone, repeatedly check several sources in the morning, and would prefer part of that routine aloud while getting ready**. Recruit people willing to share a small, deliberately selected learning sample and correct an initial plan. Begin with one language and a narrow supported connection set; broader device, language and accessibility coverage are product work, not reasons to hide limitations during recruitment.

| Job the person wants done | Desired outcome | What we need to learn |
|---|---|---|
| “Tell me what changed and what needs my attention.” | A useful short brief with clear sources, without repeatedly opening several apps. | Which sources matter enough to connect, what can wait, and how stale is too stale? |
| “Let me get ready while keeping control.” | Clear voice output, dependable interruption and a touch fallback when needed. | Is the available voice/route pleasant, and does starting/stopping actually feel easier? |
| “Learn my routine without asking me to design a workflow.” | A sensible first proposal after a small learning period, with easy corrections. | Will people complete three or seven mornings, and which errors make them stop trusting it? |
| “Help me change one thing without taking away the fun.” | An optional, personally chosen time/enjoyment goal that can be paused or removed. | Is a weekly debrief useful, unwanted, or better on demand? |

Do not require a productivity goal to qualify. A person may value a calmer start, keeping time for a game, hearing messages, or leaving the phone on a stand. Do not claim treatment of a condition, improved health, or a diagnostic wellbeing score.

## The first offer to test

The longer-term loop is **connect → learn for three or seven mornings → review → quiet daily use → optional debrief**. Those learning periods are alternative onboarding designs, not established accuracy thresholds. Today's app supports explicit selection of up to five dated observations; automatic multi-day collection, comparable habit averages and seven-day adaptation are not yet delivered.

Authorized historical Screen Time aggregates may eventually shorten the waiting period, if the entitlement, customer eligibility and actual returned coverage support it. Treat [bootstrap #30](https://github.com/gibouu/morning-operator/issues/30) as a feasibility experiment. Aggregate app time/pickups/notifications do not reveal the person's exact sequence, messages or gestures, so an instantly generated “complete routine” is not an available offer.

| Hypothesis | Potential value | Delivery gate before charging for it |
|---|---|---|
| Useful free start | Manual plan, selected learning trial, native Apple voice choice and local review. | A person can reach a useful approved routine without hidden obligations. Proposed limits remain undecided. |
| Core subscription | Reliable connected briefs, recurring supported automation, ongoing reviewed updates and optional debriefs. | Real source access, freshness, cancellation, approval and repeat-use reliability on the supported device. |
| Optional integration package | Additional genuinely supported accounts/sources or services with material operating cost. | Validate provider access, support burden and what the integration actually reads or does. Never charge for a connector that only exists in the roadmap. |
| Optional voice personalization | A desired voice or experience with reliable native or licensed delivery. | Rights, consent, availability and cost are established. Installed Apple voices are not an owned premium catalog; actor/family voices and cloning are not implemented. |
| Later household/companion options | Shared setup where appropriate, more output devices or differentiated profiles. | Prove personal-data separation and actual device/audio behavior first. No room-to-room or robot capability is bundled by implication. |

Privacy controls, deletion, source revocation, accessibility essentials and refusal of research stay available regardless of subscription. Canceling payment should stop future premium work clearly; do not hold the person's local data or existing export access hostage. Billing, entitlement reconciliation, purchase restoration and cancellation handling are not implemented. StoreKit is a potential implementation route, not current checkout. [Apple StoreKit](https://developer.apple.com/documentation/storekit).

## Pricing experiments

Use **€6, €10 and €15 per month** as illustrative concept-test price points for the *same clearly specified core offer*. These are proposed experiments, not market estimates, recommended final prices or published subscriptions. Present local currency appropriately when recruiting outside that test market. Avoid presenting unbuilt email/social control as included value.

First ask participants what they would replace and what they would miss if the service stopped; then show one complete offer and price. Record the reason for accepting or declining. A stated willingness to pay is weaker evidence than a completed, informed purchase after a functioning trial. Do not add an annual plan merely to improve early cash collection; test it after people experience repeated value and understand cancellation.

Possible decisions after the first trial:

- If people return but reject all prices, test whether the benefit is too small or whether the offer includes the wrong sources before changing prices.
- If they accept a price in interviews but do not start the trial, fix onboarding and trust before calling it a pricing problem.
- If value depends on an unsupported connector, narrow the offer or prove that connector first.
- If variable costs exceed realistic net revenue, change the service or pricing before scaling. A free cloud allowance is not a permanent unit-economics assumption.

## A small validation program for two collaborators

These sample sizes and time periods are planning choices, not statistically representative research or claimed results. Keep a consented, private study record; app-wide analytics or research upload is not currently implemented.

| Experiment | Proposed method | Decision evidence |
|---|---|---|
| Problem and language | Interview roughly 10–12 people in the initial profile. Ask them to describe a recent actual morning, their current workaround and which enjoyable rituals must stay. | Concrete repeated jobs and unwanted friction, rather than agreement with a polished pitch. Choose one initial source bundle. |
| Three versus seven mornings | Try a small explicitly consented cohort, roughly 8–12 people, with the implemented observation path. Compare completion, correction effort and confidence; let people stop. | How many eligible, usable days are needed for a proposal worth approving? Do not compare sampled-screen counts to whole-morning truth. |
| Repeat-use trial | Follow the same people for about two weeks with the actual supported product. Let them choose their intended usage days; weekly debrief is optional. | Useful mornings delivered, reasons for missed starts, correction burden, interruptions, and whether the person wants to continue. |
| Preparation and latency | Measure one authorized source from preparation through wake-time freshness check to first useful audible fact. Include missed background opportunities, offline and revoked access. | Does preparation reduce waiting without increasing stale or unwanted speech? A simulated schedule does not prove a daily 4 a.m. job. |
| Offer and price | Concept-test one accurately scoped offer, then test real purchases only after billing and the stated service work. | Actual acceptance/decline reasons and repeat value; stated intent and paid retention remain separate. |
| Voice/integration demand | Offer transparent descriptions or prototypes of optional additions, not fake working connectors. | Which additions improve repeat use enough to justify development, rights and support cost? |

One collaborator can own device/source reliability and evidence; the other can own the interview/trial script and product iteration. Compare observations in a shared, redacted decision log. The next investment decision should follow a demonstrated customer job and a reproducible device path, not a larger feature list.

## Metrics that correspond to the promise

| Measure | Definition and denominator |
|---|---|
| Activation | People who reach and explicitly approve their first useful routine, out of people who began the chosen onboarding path. Report manual and learned paths separately. |
| Learning completion | Eligible observed mornings supplied versus mornings the person agreed to try; report missing, unusable, undated and withdrawn days separately. |
| Repeat use | People returning on their next intended mornings, out of activated people with those scheduled opportunities. Also report starts and completions; neither proves satisfaction. |
| Useful brief delivery | Accepted starts that deliver at least one fresh, supported fact through the intended output route. Track empty, stale, revoked, canceled and failed starts separately. System speech completion alone is not listener confirmation. |
| Latency and preparation | Time from accepted start to first useful audible fact, plus preparation hit/miss rate. Label instrumented timing versus listener report; include failed/missing starts rather than hiding them from averages. |
| Effort and trust | User corrections per proposal, unwanted speech/action incidents, and user-reported ease/enjoyment. Track actual UI interactions only where measured; no inference from sparse screenshots. |
| Optional goal progress | The person's chosen baseline and period, with comparable source/coverage. Self-reported time and verified device measures remain distinct. No missing day becomes zero. |
| Payment | Paid conversion among people actually shown an available offer, renewal among people reaching renewal, cancellation reasons and refunds. No target rate is asserted here. |
| Cost to serve | Actual per-active/paying-user source, processing, licensed voice, storage and support costs. Compare against net receipts after applicable transaction costs and refunds. |

Prefer useful mornings and voluntary repeat use over app opens or time spent in MORE. The product succeeds when it demands less management. A reduction in screen time is optional and requires an appropriate measurement source; it is not inferred from completed routine steps. Keep test samples, the person's own behavior and behavior performed by automation separate in all reports.

## Preparation and cloud economics

Preparing connected facts ahead of time may lower morning latency, but it adds retrieval, cache invalidation and operating cost. Test fresh deltas at start, expiry, permission revocation, stale fallback and cancellation before promising a continuous service. Current recap facts are in memory; persisted overnight email/news preparation is future work. Exact background execution time is not guaranteed. [Preparation design](PRODUCT-DIRECTION.md#prepare-before-the-person-asks-refresh-what-changed).

Apple now documents a direct Private Cloud Compute model route for eligible developers. Its eligibility/entitlement rules and possible loss of eligibility make it a feasibility and cost scenario, not a guaranteed free backend for this business. The team has not demonstrated access, and the product has no PCC upload path. Any future cloud option must make its source-content choice clear and preserve a local/manual alternative when unavailable. [Apple's eligibility terms](https://developer.apple.com/private-cloud-compute/) · [PCC model documentation](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute).

Track the entitlement/runtime/cost experiment in [optional PCC #29](https://github.com/gibouu/morning-operator/issues/29), and preparation/fresh-delta work with [short opening #28](https://github.com/gibouu/morning-operator/issues/28). Neither changes current source-content retention or authorizes cloud transmission by this document.

## Optional research is a separate business question

A mobile-agent research dataset could be explored with willing participants and a defined buyer/research job. It is not needed to unlock the consumer app or subsidize its free tier, and there is no current collection-for-sale, upload or buyer pipeline.

Before proposing a study or retaining data for it, establish all of the following:

1. A concrete research purpose and a permitted, technically accessible data source; consent cannot create an unavailable API.
2. Separate informed enrollment, exact categories/recipients/retention, review/redaction and tested withdrawal/deletion. Consent to personal learning is not enrollment.
3. A reason each field is needed. Exclude raw private messages, other people's identifiers and HealthKit data from the default candidate payload; do not assume stripping a name anonymizes a recording.
4. Measured re-identification and third-party-content risks, access controls and a defensible permitted-use agreement. Do not promise guaranteed anonymity.
5. Buyer interest in the minimal lawful/permitted output before building a dataset pipeline. Research purchase intent is not consumer subscription demand.

The ordinary recovery clip remains a recovery artifact under its existing deletion rules; this business hypothesis does not extend that retention or authorize upload. [Research feasibility #24](https://github.com/gibouu/morning-operator/issues/24) · [Current privacy controls](PRIVACY.md).

## A pitch that stays within the evidence

“MORE helps your morning require less phone handling. You connect the sources you choose, show a few mornings and approve a plan that keeps what you enjoy. The aim is a short prepared brief and supported voice guidance, with the detail available whenever you want it. We have a native iPhone prototype with source-linked learning, review and approved spoken steps. We are testing real morning reliability, which connections matter and whether people will pay for the recurring service.”

For a demonstration, identify live connected facts, recorded historical excerpts and synthetic samples before using them. Show one source → reviewed plan → supported spoken result, plus a stop/refusal case. Explain the remaining phone/audio/model limits using the current verification record. Do not pitch complete cross-app autonomy, proven time savings, customer traction, medical benefits or a data marketplace as existing features.

The next business milestone is a repeatable useful morning and an informed decision to keep using it. Advance [repeat-use/pricing #18](https://github.com/gibouu/morning-operator/issues/18) alongside [short opening #28](https://github.com/gibouu/morning-operator/issues/28) and [reliable ingestion #27](https://github.com/gibouu/morning-operator/issues/27); keep unsupported integrations and research feasibility as separate decisions.
