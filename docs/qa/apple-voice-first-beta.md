# Apple-voice first beta

This release variant starts at frozen `de9373b7dfd4f7436670dba372080eb7c069efad`. It retains free entry, the internal Instagram browser, the bounded Dynamic Island layout and the English/French read-only HealthKit purpose text.

The app project and `project.yml` have no remote Swift package dependency. Removing ElevenLabs also removes its LiveKit, WebRTC and RustLiveKitUniFFI dependency graph. The complete SDK transport, including its track/caption helpers, is removed. Its unavailable replacement cannot connect, even if an old build cache still contains SDK modules. Settings explain in English and French that live conversation is unavailable. The start method rejects it before requesting a token, changing consent or touching audio.

Apple `AVFAudio` read-aloud and on-device `Speech` listening remain. Optional natural narration and fixed voice samples still use the existing consented `URLSession` HTTPS service and Apple fallback. The local voice path does not depend on the removed SDKs. An empty backend URL still fails immediately into that fallback.

Source encryption uses Apple frameworks only: `CryptoKit` for SHA-256 identifiers/PKCE, `Security` for random bytes and Keychain, and system `URLSession`/`AuthenticationServices`/`WebKit` networking. There is no vendored crypto, remote binary framework or Google OAuth SDK in this source variant. The app's `ITSAppUsesNonExemptEncryption` is false for this dependency-free configuration. Reassess it before restoring any external SDK or encryption implementation.

Before upload, the new signed Release archive and exported IPA must independently confirm that no ElevenLabs, LiveKit, WebRTC, RustLiveKitUniFFI, BoringSSL or SRTP code remains, validate the encryption flag, signatures, profiles, privacy manifests and matching dSYMs, and use a fresh build number above 2026101632. Source inspection alone is not evidence about a previously built artifact.

Focused checks cover the actual SDK-unavailable transport, localization catalogs and existing Apple voice policy/playback fallback tests. Native microphone accuracy, voice quality and external beta approval remain separate checks; no phone operation is part of this source change.
