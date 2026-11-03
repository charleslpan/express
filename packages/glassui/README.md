# GlassUI

Express's design system: tokens and, as they land, shared SwiftUI components with Liquid Glass (iOS 27+). It depends
on SwiftUI only and never on TransitKit: views take plain values (names, colours, times), and the app maps transit
models onto them.

Use the tokens instead of literals, in every screen and component.

## Tokens

| Token | What it is | Example |
| --- | --- | --- |
| `Spacing` | A 4-point scale: `xxxs` 2, `xxs` 4, `xs` 8, `sm` 12, `md` 16, `lg` 24, `xl` 32, `xxl` 48, and the aliases `screenInset`, `cardPadding`, `floatingInset`. | `.padding(Spacing.cardPadding)` |
| `Radius` | Corner radii (`xs` 6, `sm` 10, `md` 16, `lg` 24, `xl` 34), drawn continuous with `Radius.shape(_:)`. `Radius.concentric(outer:inset:)` gives a nested radius; `ConcentricRectangle()` works it out from the container (the screen, a sheet, or `.containerShape(_:)`). Use `Capsule()` for pills. | `.background(.surface, in: Radius.shape(Radius.lg))` |
| `Typography` | Type roles on system text styles, so all of them scale with Dynamic Type. Times use rounded, tabular digits. | `Text("4 min").typography(.time)` |
| Semantic colours | `ShapeStyle` members for light and dark: `canvas`, `canvasGrouped`, `surface`, `surfaceRaised`, `separatorLine`, `textPrimary`, `textSecondary`, `textTertiary`, `brand`, `statusOnTime`, `statusDelayed`, `statusDisrupted`, `statusInfo`. | `.foregroundStyle(.statusDelayed)` |
| `TravelMode` | Walk, bus, tram, subway, rail, ferry, cable car: each with a `title`, `symbolName`, accent `color`, and a legible `onColor`. | `.background(TravelMode.bus.color, in: Capsule())` |

Line colours are not tokens: they come from the transit feed at runtime (the MTA's official palette).

Rules of thumb:

- Floating controls use the native Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`).
  With Reduce Transparency on, swap glass for `.surface`.
- A gap that sits beside text that grows with Dynamic Type can grow too: `@ScaledMetric private var gap = Spacing.xs`.
- At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`), stack what normally sits side by side.

## Glass controls

The controls that float over the map, all on native Liquid Glass (`glassEffect`), interactive where they're tappable:

| Control | What it is |
| --- | --- |
| `GlassSearchField(_:text:onSubmit:accessory:)` | A floating capsule search field, as at the top of Apple Maps, with a clear button and an optional trailing accessory (plain, not glass). |
| `GlassCard { … }`, `GlassCard(action:) { … }` | A glass panel in a `Radius.lg` shape; with an action, the whole card is one button. |
| `GlassButton(_:systemImage:prominence:action:)` | A capsule button; `.prominent` tints it with `.brand` for the one primary action. |
| `GlassIconButton(_:systemImage:prominence:action:)` | A round, icon-only button, 48 points across; its title is its VoiceOver label and large content viewer text. |
| `.glassSurface(in:tint:isInteractive:)` | The glass under all of them, with their accessibility fallbacks, for a floating control of your own. |

- **Glass on the navigation layer only:** floating controls, bars, and sheets, never content. Never put glass inside
  glass: float buttons beside a card, not in it. Leave sheets to the system, which gives a half-height sheet glass on
  its own; don't give sheets custom backgrounds.
- **Group and morph:** wrap controls that sit together in `GlassEffectContainer(spacing: Spacing.floatingInset)` and
  give each `.glassEffectID(_:in:)`, so they blend and morph as they appear and disappear (see the gallery's
  "Morphing" preview).
- **Accessibility:** with Reduce Transparency on, every control draws on an opaque `.surface` with a hairline border;
  with Increase Contrast on, it gets a stronger border. Previews and the gallery force these with
  `.environment(\.forcesOpaqueGlass, true)` and `.environment(\.forcesHighContrastGlass, true)`. Every control has a
  target of at least 44 points and a VoiceOver label.

## Gallery

`GlassUIGallery` (debug builds only) shows every token, one `GallerySection` each. The app shows it through the
screenshot harness: `-screenshot gallery` for all of it, or `-screenshot gallery-<section>` (`gallery-colors`,
`gallery-modes`, `gallery-typography`, `gallery-layout`, `gallery-controls`, `gallery-control-states`,
`gallery-control-fallbacks`) for one, and CI captures each section in light, dark, and
the largest accessibility text size.

When you add components, add a `GallerySection` case and its view under `Sources/GlassUI/Gallery/`, a matching
`ScreenshotScreen` case in `apps/ios/App/Harness/ScreenshotScreen.swift`, and a test in
`apps/ios/UITests/ScreenshotTests.swift`.
