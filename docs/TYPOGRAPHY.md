# One readable family

MORE uses the native default system design for all app-owned text. On iPhone this is SF Pro, with system language fallbacks where needed. Titles, dates, body text, button labels, timer numbers and review text share that family. Size and weight provide hierarchy; tabular digits keep running times stable without switching to SF Mono. Website content inside the visible browser retains the website's own typography.

The default design was chosen over SF Pro Rounded after comparing both with the same native components and text. Default SF Pro has a quieter reading texture and matches native dates, lists, text entry and permission sheets. Rounded is readable, but makes the controls more playful without improving the morning's longer review text. This is a visual judgment from the local comparison, not a measured legibility study.

## System implementation

`MorningTheme.Typography` uses `.system` semantic styles with `design: .default`. The display and title use semibold; body and notes use regular; controls use semibold body. The existing scaled numerical displays also use `.default`. Buttons retain their original padding, minimum touch targets and labels.

An ordinary `.font(.caption)` or native date/list label already resolves to the same system family. It does not need a custom font registration or a separate font-size override. The old Patrick Hand asset can be removed from the project resources during integration; no app source requests it.

## Primary guidance

- [Apple: Typography](https://developer.apple.com/design/human-interface-guidelines/typography) recommends minimizing typefaces, expressing hierarchy through size and weight, and preferring readable Regular, Medium, Semibold or Bold weights. Built-in text styles support Dynamic Type. Apple's system design also supplies optical sizing and language support.
- [SwiftUI: system(_:design:weight:)](https://developer.apple.com/documentation/swiftui/font/system(_:design:weight:)) creates fonts from semantic styles. Explicit `.default` selects the native default design.
- [SwiftUI: monospacedDigit()](https://developer.apple.com/documentation/swiftui/font/monospaceddigit()) uses fixed-width digits within the current font, preserving a stable timer without changing the family of surrounding text.

## Proof scope

The local `more-design-wave-1/typography` output contains two native macOS SwiftUI component comparisons, SF Pro default and rounded, rendered from the real theme and button implementations with the same sample copy. They show date, title, body, English and French accents, buttons and timer digits. They are component proofs, not iPhone screenshots or evidence of phone navigation, safe areas, system sheets or every accessibility size. Images stay outside Git.

Final iPhone appearance and larger-text layout require the normal integration check. No phone automation, fixture routine, installation or recording is used for this font change.
