# Gmail reading and local replies

The owner confirmed real Google sign-in and the unread Inbox count in ordinary MORE build 1516 on 15 October 2026. The message reader and local reply editor are a subsequent change; that earlier count check does not establish that these new features work on the phone.

## Normal iPhone flow

Open **Settings → Your websites → Read messages**. This choice requests `gmail.readonly` in Google's system sign-in sheet. It works directly from a disconnected reader; a count-only sign-in is not required first. **Connect Gmail · count only** remains available and requests only `gmail.metadata`.

MORE lists up to five unread messages in Inbox. Open a message to read its text. Add optional reply guidance, choose **Prepare reply**, then review and edit the result. **Copy reply** copies the text to a local-only clipboard entry that expires after five minutes. No mail is sent, marked read, modified, or saved as a Gmail draft.

The same reader opens for an approved routine moment configured as **Open → In MORE → Gmail**. It uses that moment's existing timer and Next / +2 controls. It does not add mail to the spoken briefing or routine-learning evidence.

## Boundaries

- The selected message is rendered as inert text. HTML is reduced to text; remote images, links, embedded documents, and attachments are not loaded. A missing or unsupported body is shown as unavailable.
- Requests and MIME decoding are bounded: five unread message summaries, 512 KiB wire response, 256 KiB decoded part, eight nesting levels, 64 parts, and 32,000 displayed body characters. Declared inline body sizes must match decoded bytes. Truncated bodies cannot be submitted for automatic reply preparation.
- Reply generation uses only Apple's on-device Foundation Models, with no tools or remote fallback. Email content is untrusted source text, separate from owner guidance. The draft request is limited to 4,000 body characters and 6,000 total UTF-8 JSON bytes. Unavailable inference or oversized input leaves manual editing available.
- Tokens, messages, and replies stay in memory and clear on screen dismissal, backgrounding, disconnect, or local privacy reset. Late cancelled work cannot restore cleared content. There is no refresh-token persistence. A later Gmail moment may require sign-in again.
- Count and unread-list snapshots become stale after 60 seconds. An already opened message is a fetched snapshot; it remains available while the owner reads and edits in the foreground. Its timestamp does not claim continuing mailbox monitoring.

## Developer setup and manual acceptance

The one-time Google setup uses an iOS OAuth client matching the signed bundle, Gmail API enablement, both declared Gmail scopes, and eligible test users while in Testing mode. Actual mailbox access still requires the owner's Google consent. The canonical public configuration location and local Xcode override names are recorded in `AGENTS.md`; no client secret is used.

Check the ordinary signed app manually: connect with Read messages, open a real message, verify text on the phone, prepare and edit a reply, and test Copy. Do not copy mailbox contents into issue reports. Then run one approved morning normally, including Gmail, and record where MORE itself stops or fails. Package tests and native compilation do not establish provider, model, or complete routine success.

API references: [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes), [message list](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list), [message get](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/get).
