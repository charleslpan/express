import TransitKit
import UIKit

/// The images a ``MapVehicle`` is drawn with: its line bullet in the feed's colours, and an arrow under it that
/// pokes out on the side it's heading.
///
/// Markers on a Google map are images, so these are drawn with Core Graphics rather than SwiftUI, and cached: a map
/// full of trains shares a few dozen. They grow with the text size, up to half again their size, so the map stays
/// readable without the bullets covering it.
@MainActor
enum VehicleMarkerImage {
    /// The bullet: a circle (a diamond for an express variant, a rounded label for any other line) with the line's
    /// name, ringed in the background colour so it stands off the map.
    static func bullet(_ bullet: LineBullet, traits: UITraitCollection) -> UIImage {
        let colors = "\(hex(bullet.color))|\(hex(bullet.textColor))"
        let key = "bullet|\(bullet.text)|\(bullet.shape)|\(colors)|\(keySuffix(traits))"
        if let cached = cache[key] {
            return cached
        }
        let diameter = bulletDiameter(traits)
        let text = label(bullet, traits: traits)
        let textSize = text.size()
        let ring = ringWidth(traits)
        let width = bulletWidth(bullet, traits: traits)
        let size = CGSize(width: width + ring * 2, height: diameter + ring * 2)

        let image = UIGraphicsImageRenderer(size: size, format: format(traits)).image { _ in
            let outer = CGRect(origin: .zero, size: size)
            let inner = outer.insetBy(dx: ring, dy: ring)
            ringColor(traits).setFill()
            path(bullet.shape, in: outer).fill()
            fillColor(bullet).setFill()
            path(bullet.shape, in: inner).fill()
            text.draw(at: CGPoint(x: outer.midX - textSize.width / 2, y: outer.midY - textSize.height / 2))
        }
        cache[key] = image
        return image
    }

    /// The arrow: a square as wide as the bullet plus its tip, with the tip at the top, for a flat marker rotated to
    /// the vehicle's bearing under the bullet. A label wider than it is tall (a bus's "M15-SBS") gets an arrow that
    /// reaches past its ends, so the tip shows whichever way the vehicle heads.
    static func arrow(_ bullet: LineBullet, traits: UITraitCollection) -> UIImage {
        let width = bulletWidth(bullet, traits: traits)
        let key = "arrow|\(hex(bullet.color))|\(width)|\(keySuffix(traits))"
        if let cached = cache[key] {
            return cached
        }
        let diameter = bulletDiameter(traits)
        let ring = ringWidth(traits)
        let tip = diameter * 0.42
        let side = width + ring * 2 + tip * 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format(traits))
            .image { _ in
                let mid = side / 2
                let halfBase = diameter * 0.36
                // The base sits as far inside the bullet as a circle's does, so a long label's arrow stays joined
                // to it rather than floating free.
                let base = tip + ring + diameter * 0.2 + (width - diameter) / 2
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: mid, y: ring))
                arrow.addLine(to: CGPoint(x: mid + halfBase, y: base))
                arrow.addLine(to: CGPoint(x: mid - halfBase, y: base))
                arrow.close()
                arrow.lineJoinStyle = .round
                arrow.lineWidth = ring * 2
                ringColor(traits).setStroke()
                arrow.stroke()
                fillColor(bullet).setFill()
                arrow.fill()
            }
        cache[key] = image
        return image
    }

    private static var cache: [String: UIImage] = [:]

    /// The bullet's text, in its colour.
    private static func label(_ bullet: LineBullet, traits: UITraitCollection) -> NSAttributedString {
        let diameter = bulletDiameter(traits)
        let font = UIFont.systemFont(ofSize: diameter * (bullet.text.count > 1 ? 0.48 : 0.62), weight: .bold)
            .withDesign(.rounded)
        return NSAttributedString(string: bullet.text, attributes: [
            .font: font,
            .foregroundColor: textColor(bullet),
        ])
    }

    /// The bullet's width inside its ring: the diameter, or wider for a label's longer text.
    private static func bulletWidth(_ bullet: LineBullet, traits: UITraitCollection) -> CGFloat {
        let diameter = bulletDiameter(traits)
        guard bullet.shape == .label else { return diameter }
        return max(diameter, (label(bullet, traits: traits).size().width + diameter * 0.6).rounded(.up))
    }

    /// The bullet's size in points: 22 at the default text size, growing with it up to 33.
    private static func bulletDiameter(_ traits: UITraitCollection) -> CGFloat {
        let base: CGFloat = 22
        return min(UIFontMetrics(forTextStyle: .caption1).scaledValue(for: base, compatibleWith: traits), base * 1.5)
    }

    private static func ringWidth(_ traits: UITraitCollection) -> CGFloat {
        bulletDiameter(traits) / 11
    }

    private static func path(_ shape: LineBullet.Shape, in rect: CGRect) -> UIBezierPath {
        switch shape {
        case .circle:
            return UIBezierPath(ovalIn: rect)
        case .label:
            return UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        case .diamond:
            let diamond = UIBezierPath()
            diamond.move(to: CGPoint(x: rect.midX, y: rect.minY))
            diamond.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            diamond.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            diamond.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            diamond.close()
            return diamond
        }
    }

    /// The line's colour, or grey where the feed gives none.
    private static func fillColor(_ bullet: LineBullet) -> UIColor {
        bullet.color.map(UIColor.init(rgb:)) ?? .systemGray
    }

    private static func textColor(_ bullet: LineBullet) -> UIColor {
        bullet.textColor.map(UIColor.init(rgb:)) ?? .white
    }

    /// The ring around the bullet and arrow: the background colour of the appearance, so it reads on either map style.
    private static func ringColor(_ traits: UITraitCollection) -> UIColor {
        UIColor.systemBackground.resolvedColor(with: traits)
    }

    private static func format(_ traits: UITraitCollection) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.opaque = false
        return format
    }

    private static func keySuffix(_ traits: UITraitCollection) -> String {
        "\(traits.userInterfaceStyle.rawValue)|\(bulletDiameter(traits))"
    }

    private static func hex(_ color: RGBColor?) -> String {
        color.map { "\($0.red),\($0.green),\($0.blue)" } ?? "-"
    }
}

private extension UIColor {
    convenience init(rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

private extension UIFont {
    /// The font in another design, such as SF Pro Rounded for bullets; the font itself where the design is missing.
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont {
        fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: pointSize) } ?? self
    }
}
