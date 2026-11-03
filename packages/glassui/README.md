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

## Gallery

`GlassUIGallery` (debug builds only) shows every token, one `GallerySection` each. The app shows it through the
screenshot harness: `-screenshot gallery` for all of it, or `-screenshot gallery-<section>` (`gallery-colors`,
`gallery-modes`, `gallery-typography`, `gallery-layout`) for one, and CI captures each section in light, dark, and
the largest accessibility text size.

When you add components, add a `GallerySection` case and its view under `Sources/GlassUI/Gallery/`, a matching
`ScreenshotScreen` case in `apps/ios/App/Harness/ScreenshotScreen.swift`, and a test in
`apps/ios/UITests/ScreenshotTests.swift`.
