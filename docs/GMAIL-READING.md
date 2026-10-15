# Gmail reading and local replies

The owner confirmed real Google sign-in and the unread Inbox count in ordinary MORE build 1516 on 15 October 2026, then confirmed reading messages in build 1517. Local reply generation and the complete morning remain unconfirmed. The owner rejected the repeated per-screen sign-ins; #151 replaces that first credential design with a securely saved connection.

## Normal iPhone flow

Open **Settings → Your websites → Connect Gmail** once. Google's system sign-in sheet requests `gmail.readonly` and offline authorization. MORE keeps only the refresh credential in this iPhone's non-syncing Keychain. Opening the reader again renews access without a sign-in sheet. **Retry Gmail** handles temporary network/storage failures without discarding the saved connection. A missing, revoked or expired Google grant can require Connect again.

**Disconnect Gmail** forgets this iPhone's saved login. It does not revoke Google's account grant; manage or remove that separately in your Google Account, as the reader's Connection details explain.

MORE lists up to five unread messages in Inbox. Open a message to read its text; **Read full message** expands the five-line preview. Add optional reply guidance, choose **Prepare reply**, then review and edit the result. **Copy reply** copies the text to a local-only clipboard entry that expires after five minutes. No mail is sent, marked read, modified, or saved as a Gmail draft.

The same reader opens for an approved routine moment configured as **Open → In MORE → Gmail**. It uses that moment's existing timer and Next / +2 controls. It does not add mail to the spoken briefing or routine-learning evidence.

## Boundaries

- The selected message is rendered as inert text. HTML is reduced to text; remote images, links, embedded documents, and attachments are not loaded. A missing or unsupported body is shown as unavailable.
- Requests and MIME decoding are bounded: five unread message summaries, 512 KiB wire response, 256 KiB decoded part, eight nesting levels, 64 parts, and 32,000 displayed body characters. Declared inline body sizes must match decoded bytes. Truncated bodies cannot be submitted for automatic reply preparation.
- Reply generation uses only Apple's on-device Foundation Models, with no tools or remote fallback. Email content is untrusted source text, separate from owner guidance. The draft request is limited to 4,000 body characters and 6,000 total UTF-8 JSON bytes. Unavailable inference or oversized input leaves manual editing available.
- Message text, counts, access sessions and replies stay in memory and clear on screen dismissal/background. The saved refresh credential remains until **Disconnect Gmail**, privacy reset, an invalid grant, or a detected reinstall. Keychain accessibility is WhenUnlockedThisDeviceOnly. Writes/rotations check the current privacy generation and original credential, so late work cannot undo a reset or Disconnect. An explicit copy remains on the local clipboard for up to five minutes.
- Count and unread-list snapshots become stale after 60 seconds. An already opened message is a fetched snapshot; it remains available while the owner reads and edits in the foreground. Its timestamp does not claim continuing mailbox monitoring.

## Developer setup and manual acceptance

The one-time Google setup uses an iOS OAuth client matching the signed bundle, Gmail API enablement, both declared Gmail scopes, and eligible test users while in Testing mode. Actual mailbox access still requires the owner's Google consent. The canonical public configuration location and local Xcode override names are recorded in `AGENTS.md`; no client secret is used.

Check the ordinary signed app manually: Connect Gmail, leave and reopen the reader without signing in again, open a real message, prepare/edit a reply, and test Copy. Do not copy mailbox contents into issue reports. Then run one approved morning normally, including Gmail, and record where MORE itself stops or fails. Package tests and native compilation do not establish provider, model, or complete routine success.

API references: [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [message list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list), [message get](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get).
