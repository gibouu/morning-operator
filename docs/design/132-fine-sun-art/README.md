# Fine sunset sun artwork · #132

The previous sun uses a coarse regular grid of circles. This optional replacement uses a natural sunset-inspired image with microscopic stochastic grain, creamy light and a feathered rust edge. This is original generated artwork, not a documentary photograph. No source photograph was supplied. The owner's marked screenshot was a rejected-style reference only; its pixels were not used as an edit target or forwarded to the generation tool.

## Integration

```swift
MorningSolarArtwork(opacity: scene.sun.opacity)
    .frame(width: diameter, height: diameter)
    .position(x: geometry.size.width * scene.sun.centerX,
              y: geometry.size.height * scene.sun.centerY)
```

The view defaults to the bundled `SolarSunFineV1` image and original multicolor rendering. It owns no solar timing, position, animation or hit targets. Existing clock positions and reduced-motion behavior remain at the callsite. It is hidden from accessibility and cannot consume taps. The optional `image:` initializer argument lets the native proof use the exact PNG without compiling an app asset catalog.

The transparent canvas contains a sun with a visible diameter of about 78% of its frame. Keep the soft margin for feathering. Set a larger frame only when the old disc's exact visible diameter is needed. No template tint, mask or artificial shadow is required. This branch supplies a sun only; the existing moon remains available to the integration owner.

`project.yml` already collects the app source directory and asset catalog. The integration owner must regenerate the Xcode project when combining this source file. This branch does not change the existing theme, art layer, navigation or project.

## Provenance

- Built-in `image_gen` tool, transparent background enabled, one generation on 2026-10-15.
- New image generation, no referenced input images.
- Original generated PNG copied unchanged into `Resources/Assets.xcassets/SolarSunFineV1.imageset/solar-sun-fine-v1.png`.
- Original generated output retained at the tool's normal generated-images location.
- SHA-256: `ac24b5026e23d4b8021dc9291703e9f94ab7fcb4df26253fc5b92f06ae237bbf`.
- Dimensions: 1254 × 1254, RGBA. All four corner alpha values are 0. There are 821,020 transparent pixels and 751,495 partially transparent pixels. Alpha is preserved; no pixel edits, recoloring, background removal or post-generation filters were applied.
- Full generation prompt is in `prompt.txt`.

## Verification

Run `zsh docs/design/132-fine-sun-art/render.sh` on macOS with Xcode. It compiles the actual `MorningSolarArtwork` view and renders that view on three paper backgrounds with native SwiftUI `ImageRenderer`, using the unchanged PNG. Default output is `.build/fine-sun-proof/sun-paper-compositing.png`.

The native plate was inspected at 342 pt canvas size on early-light ivory, day cream and warm-evening paper. The grain reads as fine photographic texture; no large repeated circle rows, purple, text, hard matte rectangle or visible clipping appears in the asset. The plate is a component proof, not an executed iPhone screen. No phone automation, routine seeding, device install or account capture was performed. No screenshots or proof PNGs are committed.

### Independent acceptance review · 15 October 2026

The same command also produces `sun-size-opacity-acceptance.png`: the actual view at 120, 240 and 300 pt canvas sizes, plus a 300 pt opacity comparison at 0%, 30% and 100%, rendered at 3×. The 300 pt frame matches the existing solar layer's upper size limit; placement and final opacity remain integration choices. Fine grain and the soft edge remain clear at these sizes. The 30% example is deliberately faint. Pixel inspection confirms that the 0% artwork region contains only the single paper color.

The component and PNG are unchanged from `e03c235`; no artwork fix was needed. A fresh SHA-256 check matches the provenance above. Alpha has 256 distinct levels, one opaque pixel, and no matte rectangle. Sparse generated pixels reach the outermost canvas with alpha at most 1/255; all four corners are fully transparent. Keep this original alpha rather than cropping or masking the feathered edge.

Local verification also compiles the asset catalog with iPhone `actool` and type-checks `MorningSolarArtwork.swift` for `arm64-apple-ios26.0` with Swift 6 mode. Both pass. These checks establish asset/source validity; the proof still uses the `image:` override. Default image lookup in the combined app, clock-driven placement, animation and real iPhone appearance remain for the integration owner to verify after regenerating the Xcode project.
