# Explicit synthetic OCR comparison

`SyntheticOpenAIComparisonTests` is an optional diagnostic for the owner's explicit consent to compare only the invented OCR texts from the compact French test movie with OpenAI. It does not enable remote inference in the app.

The test accepts one frozen extraction report by its SHA-256, verifies its synthetic acquisition and movie fingerprint, and replays its existing OCR through ordinary evidence preparation, the existing OpenAI route and native proposal validation. It reads no movie, audio, personal data or expected routine. The expected oracle is never sent. Each outgoing prompt, schema, endpoint, model, instructions and request options must match the prepared request exactly. The current route on main is `gpt-6-luna`, with high reasoning, `store: false`, strict structured output and no redirects. Preparation used the earlier GPT-5 mini route, but made no network call before the current main configuration was integrated.

Both `MO_RUN_OPENAI_SYNTHETIC_COMPARISON=1` and `MO_OPENAI_SYNTHETIC_TEXT_CONSENT=1` are required. `MO_OPENAI_SYNTHETIC_INPUT` and `MO_OPENAI_SYNTHETIC_OUTPUT` must be absolute JSON paths inside this checkout's private `work/` directory. The output must not already exist. `MO_OPENAI_SYNTHETIC_KEY_FILE` must reference an owner-only regular file outside Git; credentials live in ephemeral memory only and are never included in logs or reports. Do not put a key in a shell argument or commit one.

The private report records the exact input and instruction hashes, actual HTTP attempt/return counts, status codes, elapsed time, sanitized failure category and validated proposal. It is explicitly an OCR replay, not a fresh extraction/classification, full movie-pipeline result, learned personal routine or MORE acceptance result. A proposed draft remains synthetic and unapproved, with no target, automation or Keep authority.

The always-local guards verify rejection of symbolic-link or oversized input and changed source text, instructions, storage options, unexpected data, schema, endpoint and method. Input and key reads require an owner-only regular file, `O_NOFOLLOW` and a bounded read from the checked descriptor. The optional live test is disabled in normal package and CI runs.

16 October2026, source `6b73592`: all three diagnostic tests pass. The live replay takes81.709s with7 actual requests and7 HTTP200 responses, yielding8 natively validated synthetic draft moments. Interface language EN, quoted source text FR. Independent review verifies9/9 byte-exact citations across9 of24 sampled frames and18 proposed minutes. Eight of nine source families have some cited content, but the structure is incomplete: Gmail/Slack merge into one generic moment, the feed is split twice and music is omitted. Personal Keep and the explicitly added recap must not be invented. This result does not establish movie extraction, faithful reconstruction, app approval/execution, personal learning or MORE §10. The protected raw report remains in the private test workspace.

## Resumed OCR-only replay

A second replay on frozen `e5f79b6` returns seven HTTP200 responses in94.469s,
but native evidence policy refuses the final result. Its generic diagnostic
does not establish a particular rejection cause. The later structured batch
diagnostic does not retrospectively explain this historical failure.

The third replay on16October uses the same289,560-byte frozen input
(`fcad0666217a3638c6e786d88a9554a98285448e2539f9c0ad08a4cb7c536e20`),
ordinary `gpt-6-luna` high route, seven bounded requests and unchanged proposal
policy. The actual test passes in77.910s:7/7 HTTP200, seven validated batch
outcomes. Five explicitly abstain; two return four synthetic, unapproved moments
covering news, social, reminder and reading, with10 proposed minutes. Exact
quoted source bytes bind to sampled frame times730.2,876.4,1314.6 and1387.6s.
Calendar, Gmail, Slack, video and music are absent; **4/9 source families is a
partial result**. There is no automation, target, Keep or execution permission.

The raw report and receipt remain private under
`work/openai-synthetic-comparison/ocr-luna-high-replay-v3-structured-policy*.json`.
The protected temporary key file was deleted after the run. This replay does not
configure OpenAI in the ordinary app, upload media, rerun video extraction, or
certify learning the complete synthetic routine. The local full-movie v11
0/9 result remains unresolved.
