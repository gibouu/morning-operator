# Morning Operator

Personal Apple development prototype. Shared setup, priorities and verified results are in `docs/ONBOARDING.md`, `docs/ROADMAP.md` and `docs/PHASE-ONE.md`. An optional owner-only product brief may exist at `docs/PROJECT-BRIEF.md`; it is ignored by Git and is not required for a fresh clone. Do not upload or copy it into shared documentation.

- Build real, inspectable behavior; label fixtures and unavailable capabilities.
- Keep XCTest phone control in the UI-test target, never in the ordinary app target.
- Keep Apple inference and screen content local. No silent remote-model fallback.
- Do not commit recordings, screenshots, inbox content, tokens, pairing secrets or signing credentials.
- The first useful slice is teach → review/edit → approve → run with local speech.
- Model output proposes actions; validated application policy decides execution.
- An ambiguous external effect must be reconciled before retrying it.
- Use Swift Package Manager tests for shared logic. Xcode/device checks are separate; do not claim they passed when only package tests ran.
- Preserve user edits and distinguish retained semantic learning from expiring raw media.
- Do not modify the parent project's read-only `sources/` directory.

# Project Context

- Google configuration: `~/.config/google-cli/accounts.ini`, section `[morning-operator]`.
- Public configuration keys: `account`, `project_id`, `ios_client_id`, `callback_scheme`, `bundle_id`.
- Local Xcode overrides: `MORE_GOOGLE_CLIENT_ID` and `MORE_GOOGLE_CALLBACK_SCHEME`.
- Native iOS OAuth needs no client secret. Keep actual configuration values outside this repository.
