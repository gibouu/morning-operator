# MORE — ink, paper and the time of day

The reference is the owner's two-ink lake print: ultramarine, warm paper and a quiet halftone. The owner's next pass makes separate round dots the shared language for the sunrise, app icon, navigation, controls and quiet card edges. Patrick Hand gives short titles a handwritten voice; plain native text carries longer reading and controls. The font is bundled under SIL OFL 1.1, with its licence and provenance in `Resources/Fonts`.

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

- Display and section titles: Patrick Hand Regular. Body, notes and controls: native sans serif. Times keep tabular numbers. Every size follows Dynamic Type; no font request occurs at runtime.
- Side gutter 24 pt; card inset 18 pt; section spacing 16 pt; card radius 10 pt. Reading surfaces stay opaque, with sparse dotted edges.
- One static Canvas path draws a small halftone screen. No animated noise, image download, shader loop or per-frame timer. Dots and the sun are decorative and ignore touch and VoiceOver.
- Reduce Transparency removes the decorative texture and sky. Reduce Motion disables sun/moon interpolation and existing dock transitions. Increase Contrast promotes secondary ink to primary ink and strengthens small dotted glyphs.
- The sun starts at the lower centre around dawn, rises towards midday and returns towards sunset. A dotted crescent rises after sunset and lowers before dawn. Positions follow local clock time independently of routine completion, using the same fixed solar reference as the palette. The drawing is decorative, not measured astronomy. Texture stays behind content, with opaque reading surfaces.

## Controls and copy

Primary actions are printed paper tickets with dotted ink edges and handwritten labels. Secondary actions use dotted underlines or quiet text; they are not filled system capsules. Learn keeps Record and Choose as the initial decision; the suggestion control remains unavailable until there is content. Existing run controls and their identifiers remain intact. Destructive confirmation keeps its explicit warning and a separate, readable red fill.

Four icon-only destinations keep the bottom bar quiet: Morning, Routine, Learn and Settings. Accessible names remain explicit. The date opens history. Routine, Learn and Settings use full-page presentations; compact capture, voice and invitation tasks may use sheets. Large settings pages use the same full-page treatment. Browser chrome uses the same paper, dot icons and short labels while the website stays visible. Reads and scroll requests still require a tap; the saved routine timer remains shared.

Cut text that repeats a heading, button label or nearby explanation. Keep source labels, fixtures, errors, consent, privacy scope and unavailable-feature statements. Move optional details behind disclosure controls. Changed product copy has English and French values. Stored observations can still recognize earlier MORE wording, even after it leaves the visible interface.

## Verification and honest visual scope

The full shared package tests and generic iOS Simulator build-for-testing can run without a simulator runtime. They do not execute iPhone UI tests.

`RisoThemeSnapshotTests` supplies synthetic, isolated iPhone screenshots: Home and running routine in all five phases; first use, Learn, Settings, Your day, Privacy and Review in English light and French dark appearances. It writes XCTest attachments and optionally `MO_THEME_SCREENSHOT_DIR`. These tests need an installed simulator runtime or a connected phone.

A separate, local macOS ImageRenderer harness renders the real `MorningTheme`, shared cards, type, buttons and sunrise at a phone-sized canvas. It is a native component proof, not evidence that iPhone navigation, text sizes or safe areas work. Screenshots stay outside Git. The localhost review companion keeps both visual revisions and saves right-click notes with page coordinates and stable screen identifiers.

Before the dotted-journey revision, a separate MORE QA app passed the five-phase Home/running tour and the English-light/French-dark main-screen journey on the connected iPhone 15 Pro Max. Twenty-two design screenshots plus two web-routine screenshots remain available for comparison. The new revision must be captured and reviewed again. Captures establish their standard text size, not every Dynamic Type or accessibility setting.

## 15 October direction

MORE always selects light appearance; its five clock palettes still move warm paper from dawn to night. System dark mode does not invert the app or Lock Screen art. The latest signed ordinary app/widget build and full 1,204-test package run pass. No further scripted iPhone routines run after the owner’s request. Final phone acceptance remains manual; see [CURRENT-DIRECTION.md](CURRENT-DIRECTION.md).
