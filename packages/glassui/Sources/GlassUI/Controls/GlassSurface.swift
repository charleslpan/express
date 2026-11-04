import SwiftUI

/// Sizes every glass control shares.
enum GlassMetrics {
    /// The smallest tap target, in points, per Apple's Human Interface Guidelines.
    static let minimumTarget: CGFloat = 44
    /// The diameter of a ``GlassIconButton`` and the height of a ``GlassSearchField`` at the default text size, as in
    /// Apple Maps.
    static let floatingControl: CGFloat = 48
}

public extension EnvironmentValues {
    /// Draws GlassUI's controls with their opaque Reduce Transparency fallback whatever the system setting says: for
    /// previews and the gallery, which can't turn the setting on. The system setting still applies when this is off.
    @Entry var forcesOpaqueGlass: Bool = false

    /// Draws GlassUI's controls with their Increase Contrast borders whatever the system setting says: for previews
    /// and the gallery. The system setting still applies when this is off.
    @Entry var forcesHighContrastGlass: Bool = false
}

public extension View {
    /// Puts this view on Liquid Glass in `shape`, or on an opaque ``ShapeStyle/surface`` with a border when Reduce
    /// Transparency is on. With Increase Contrast it also draws a stronger border.
    ///
    /// Glass belongs to the navigation layer only: controls and panels that float over content such as the map.
    /// Never put a glass view inside another (no glass on glass), and leave sheets to the system, which gives them
    /// glass on its own. Group glass views that sit together in a `GlassEffectContainer`, and give each a
    /// `glassEffectID(_:in:)` so they morph as they appear and disappear.
    ///
    /// - Parameters:
    ///   - shape: The glass's shape; a capsule for pills, ``Radius/shape(_:)`` for panels.
    ///   - tint: A colour to tint the glass with, such as ``ShapeStyle/brand`` for a primary action; the opaque
    ///     fallback fills with it.
    ///   - isInteractive: Whether the glass reacts to touch. Turn it on for anything tappable.
    func glassSurface(in shape: some InsettableShape, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, isInteractive: isInteractive))
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.forcesOpaqueGlass) private var forcesOpaqueGlass
    @Environment(\.forcesHighContrastGlass) private var forcesHighContrastGlass

    private var isOpaque: Bool {
        reduceTransparency || forcesOpaqueGlass
    }

    private var isHighContrast: Bool {
        contrast == .increased || forcesHighContrastGlass
    }

    func body(content: Content) -> some View {
        if isOpaque {
            content
                .background {
                    shape
                        .fill(tint ?? Color.surface)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                }
                .overlay {
                    shape.strokeBorder(
                        isHighContrast ? Color.textPrimary : Color.separatorLine,
                        lineWidth: isHighContrast ? 1.5 : 0.5
                    )
                }
        } else {
            content
                .glassEffect(Glass.regular.tint(tint).interactive(isInteractive), in: shape)
                .overlay {
                    if isHighContrast {
                        shape.strokeBorder(Color.textPrimary.opacity(0.5), lineWidth: 1)
                    }
                }
        }
    }
}
