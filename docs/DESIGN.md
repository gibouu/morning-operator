# MORE — ink, paper and the time of day

The reference is the owner's two-ink lake print: ultramarine, warm paper and a quiet halftone. The portable riso-paper kit supplies the spacing, print-like rules and burnt-orange accent. The native system serif keeps the look without a font download or a new font licence dependency.

## Light research and its limits

These sources guide a comfortable visual treatment. MORE does not measure light at the eye, change screen brightness or claim to improve circadian health. A small coloured app surface is not equivalent to daylight or a measured lighting intervention. Auto-Brightness, Night Shift and the person's appearance choice stay under system control.

- [CIE position statement, third edition (2024)](https://www.cie.co.at/publications/cie-position-statement-integrative-lighting-recommending-proper-light-proper-time-3rd): the timing, amount and spectrum of light exposure matter. The statement recommends more light during the day, much less before bed and near-darkness during sleep. It also calls out glare. We infer a gentler dawn surface and warmer evening paper as an aesthetic choice, not a measured light dose.
- [NIGMS: Circadian Rhythms](https://www.nigms.nih.gov/education/fact-sheets/Pages/circadian-rhythms): light and dark help synchronize the body's clock. This supports a time-aware visual language; it does not establish a best UI hex colour for morning eyes.
- [Chang et al., PNAS (2015)](https://doi.org/10.1073/pnas.1418490112): an evening light-emitting eReader experiment found changes in sleep and circadian timing. Its exposure and reading conditions cannot be transferred directly to this app's palette. We avoid claiming that warmer pixels alone improve sleep.
- [Apple: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): maintain readable contrast and support larger type, motion preferences and VoiceOver. We use semantic, scalable text styles, wrap labels and preserve action identifiers.
- [Apple: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode): test contrast across appearances and accessibility settings. Every phase has separate light and dark values; the clock never forces the person into a different appearance.
- [W3C: Contrast (Minimum)](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html): ordinary text needs at least 4.5:1 contrast. Core tests check the text tokens, both paper and card surfaces, every phase and the interpolated cycle. Primary ink clears 7:1 on paper at the sampled times.

## Palette

All values are sRGB. Orange fill is decoration; small orange text uses the darker `accentText` in light appearance or the lighter one in dark appearance. A filled primary control uses `ink` and `onInk`, never an assumed white label.

| Phase | Light paper / ink | Dark paper / ink | Accent fill |
| --- | --- | --- | --- |
| Dawn | `#F3E6D6` / `#24305E` | `#1B1A2E` / `#F0E2CE` | `#CF5220` / `#E8814A` |
| Morning | `#F6F3EC` / `#16307A` | `#0F1F45` / `#F4F1EA` | `#CF5220` / `#E8814A` |
| Day | `#F4ECDD` / `#1A2F6E` | `#12224A` / `#F3ECDD` | `#CF5220` / `#E8814A` |
| Evening | `#EFDFC4` / `#27305A` | `#1A1626` / `#EFDFC4` | `#C84E1E` / `#E07A42` |
| Night | `#E6D4B4` / `#272B4C` | `#0B1226` / `#E6D4B4` | `#C2471A` / `#D96F3A` |

`MorningDayClock` uses local calendar time. There is no existing sunrise/sunset feed in the weather service, so the live app uses fixed 07:00 / 19:00 reference hours. The palette holds between keyframes and uses smoothstep between phases: night → dawn 05:45–06:45, dawn → morning 07:30–08:15, morning → day 10:00–12:00, day → evening 17:00–18:15, evening → night 19:30–21:00. The root refreshes the blend once per minute and immediately on foreground entry. Background work is not required.

The pure logic can accept future solar times. Short winter days compress the daytime keyframes so they stay ordered. Invalid, polar or unsupported midnight-edge values fall back to the fixed cycle. The app does not ask for location to select a palette.

## Type, texture and space

- Large title and headings: native system serif, medium weight. Body and notes: native serif. Small labels and time: native monospaced styles with tabular numbers. Every size follows Dynamic Type.
- Side gutter 24 pt; card inset 18 pt; section spacing 16 pt; card radius 10 pt. Reading surfaces have an opaque fill and a hairline.
- One static Canvas path draws a small halftone screen. No animated noise, image download, shader loop or per-frame timer. Dots and the sun are decorative and ignore touch and VoiceOver.
- Reduce Transparency removes the paper texture and sun. Reduce Motion disables the sun's progress animation and existing dock transitions. Increase Contrast promotes secondary ink to primary ink. The native floating glass bar follows the system's accessibility treatment.
- The top sun reflects completed steps. The bottom sunrise remains the home control and uses the same phase ink. Texture stays behind content, never over type.

## Controls and copy

One filled primary action per immediate decision. Other actions use outline or quiet text. Learn keeps Record and Choose as the initial decision; the suggestion control remains unavailable until there is content. Existing run controls and their identifiers remain intact. Destructive confirmation keeps its explicit warning and a separate, readable red fill.

Glass belongs to system navigation and a floating command bar. Routine tiles, brief cards, first use and ordinary actions use ink and opaque paper. System sheets and bottom action bars may retain native material.

Cut text that repeats a heading, button label or nearby explanation. Keep source labels, fixtures, errors, consent, privacy scope and unavailable-feature statements. Move optional details behind existing disclosure controls. Every changed string has an English and French value; no UI-test action identifier changes.

## Verification and honest visual scope

The full shared package tests and generic iOS Simulator build-for-testing can run without a simulator runtime. They do not execute iPhone UI tests.

`RisoThemeSnapshotTests` supplies synthetic, isolated iPhone screenshots: Home and running routine in all five phases; first use, Learn, Settings, Your day, Privacy and Review in English light and French dark appearances. It writes XCTest attachments and optionally `MO_THEME_SCREENSHOT_DIR`. These tests need an installed simulator runtime or a connected phone.

A separate, local macOS ImageRenderer harness renders the real `MorningTheme`, shared cards, type, buttons and sunrise at a phone-sized canvas. It is a native component proof, not evidence that iPhone navigation, text sizes or safe areas work. Screenshots stay outside Git. The localhost review companion keeps both visual revisions and saves right-click notes with page coordinates and stable screen identifiers.
