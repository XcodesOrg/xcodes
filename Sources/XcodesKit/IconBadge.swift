import Foundation
@preconcurrency import Version

/// A badge showing an Xcode's version, drawn over the Xcode's own icon.
public struct IconBadge: Equatable, Sendable {
    /// The main text in the badge: the version number.
    let label: String
    /// The secondary text in the badge: the prerelease label, if any.
    let suffix: String
    /// Whether the badge is drawn in the prerelease color instead of the release color.
    let isPrerelease: Bool

    /// The badge's whole text: the label followed by the suffix.
    var text: String {
        label + suffix
    }

    public init(version: Version) {
        var label = "\(version.major).\(version.minor)"
        if version.patch != 0 {
            label += ".\(version.patch)"
        }
        self.label = label
        self.suffix = version.compactPrereleaseIdentifier
        self.isPrerelease = !version.prereleaseIdentifiers.isEmpty
    }
}

#if canImport(AppKit)
import AppKit
@preconcurrency import Path

public enum IconBadgeError: LocalizedError, Equatable {
    case notWritable(Path)
    case failedToSetIcon(Path)
    case failedToRenderIcon

    public var errorDescription: String? {
        switch self {
        case .notWritable(let path):
            return """
                   \(path.string) can't be modified, so its icon can't be changed.
                   If it's owned by you, your terminal may need "App Management" access: System Settings > Privacy & Security > App Management.
                   """
        case .failedToSetIcon(let path):
            return """
                   Failed to set a custom icon on \(path.string).
                   If it's owned by you, your terminal may need "App Management" access: System Settings > Privacy & Security > App Management.
                   """
        case .failedToRenderIcon:
            return "Failed to draw the badge onto the icon, so the icon was left as it was."
        }
    }
}

/// Applying a badge as a custom Finder icon.
///
/// A custom icon is stored next to the bundle's `Contents` directory (an `Icon\r` file plus a Finder info flag), so
/// Xcode's sealed code signature isn't touched and `codesign --verify` / `spctl --assess` keep passing. Only
/// `codesign --verify --strict` objects to the Finder info.
extension IconBadge {
    /// The icon art is shrunk a little so the pill doesn't cover too much of the hammer.
    static let artScale: CGFloat = 0.9
    /// The gap between the top of the icon art and the top of the icon, relative to the icon's size.
    static let artTopInset: CGFloat = 0.02
    /// The widest the pill may get, relative to the icon's size.
    static let maxPillWidth: CGFloat = 0.92
    /// The gap between the bottom of the pill and the bottom of the icon, relative to the icon's size.
    static let pillBottomInset: CGFloat = 0.035
    /// The diameter of the pill when it has no text, relative to the icon's size.
    static let emptyPillDiameter: CGFloat = 0.2
    /// The pill's drop shadow, relative to the icon's size.
    static let shadowOffset: CGFloat = 0.005
    static let shadowBlur: CGFloat = 0.02
    static let shadowAlpha: CGFloat = 0.4
    /// The faint highlight along the pill's edge: its width and inset relative to the icon's size, and its opacity.
    static let highlightWidth: CGFloat = 0.004
    static let highlightAlpha: CGFloat = 0.25
    /// Below this pixel size the label can't be read, so only the colored pill is drawn.
    static let minimumTextSize: CGFloat = 48
    /// The label's font size relative to the icon's size.
    static let labelFontScale: CGFloat = 0.22
    /// How much a label that doesn't fit is shrunk by on each attempt.
    static let labelShrinkFactor: CGFloat = 0.96
    /// The padding around the label's glyphs on every side, relative to the version's cap height.
    static let paddingScale: CGFloat = 0.6
    /// The prerelease suffix's font size relative to the version's.
    static let suffixFontScale: CGFloat = 0.78
    /// Smallest label font, in pixels, that is still worth drawing; smaller labels fall back to a bare pill.
    static let minimumFontSize: CGFloat = 7
    /// Icon bitmaps as (point size, pixel size) pairs: each point size at 1x and 2x, as in an .icns.
    static let representations: [(points: Int, pixels: Int)] = [
        (16, 16), (16, 32),
        (32, 32), (32, 64),
        (128, 128), (128, 256),
        (256, 256), (256, 512),
        (512, 512), (512, 1024),
    ]

    private var fillColor: NSColor {
        isPrerelease
            ? NSColor(srgbRed: 0.72, green: 0.36, blue: 0.98, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.61, blue: 0.27, alpha: 1)
    }

    /// Draws the badge over the stock icon of the app at `path`, and sets the result as its custom icon.
    public func setCustomIcon(of path: Path) throws {
        try Self.requireWritable(path)
        let base = try Self.stockIcon(of: path)
        // Drawn before anything is changed, so a failure can't leave the app with a worse icon than it started with.
        let image = try makeImage(base: base)
        try Self.setIcon(image, of: path)
    }

    /// Restores the stock icon of the app at `path`.
    public static func removeCustomIcon(of path: Path) throws {
        try requireWritable(path)
        try setIcon(nil, of: path)
    }

    /// An icon with a bitmap at every standard size, each drawn natively so the text stays crisp.
    func makeImage(base: NSImage) throws -> NSImage {
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for (points, pixels) in Self.representations {
            image.addRepresentation(try makeRepresentation(base: base, pixels: pixels, points: points))
        }
        return image
    }

    func makeRepresentation(base: NSImage, pixels: Int, points: Int? = nil) throws -> NSBitmapImageRep {
        let size = CGFloat(pixels)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            throw IconBadgeError.failedToRenderIcon
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high

        // The original icon, centered horizontally and nudged up, leaving room for the pill underneath.
        let artSize = size * Self.artScale
        let artRect = NSRect(x: (size - artSize) / 2, y: size - artSize - size * Self.artTopInset, width: artSize, height: artSize)
        base.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)

        drawPill(in: graphicsContext.cgContext, size: size)

        // The point size is applied after drawing: it changes the context's scale, and everything above is in pixels.
        let pointSize = CGFloat(points ?? pixels)
        representation.size = NSSize(width: pointSize, height: pointSize)
        return representation
    }

    private static func stockIcon(of path: Path) throws -> NSImage {
        // The asset catalog holds the full resolution icon. Asking Launch Services right after clearing a custom
        // icon can instead return a placeholder at the larger sizes, so that is only the fallback.
        if let bundle = Bundle(path: path.string),
           let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let image = bundle.image(forResource: NSImage.Name(iconName)) {
            return image
        }
        if hasCustomIcon(path) {
            try setIcon(nil, of: path)
        }
        return NSWorkspace.shared.icon(forFile: path.string)
    }

    private static func setIcon(_ image: NSImage?, of path: Path) throws {
        let didSetIcon = NSWorkspace.shared.setIcon(image, forFile: path.string, options: [])
        guard didSetIcon else {
            throw IconBadgeError.failedToSetIcon(path)
        }
    }

    private static func hasCustomIcon(_ path: Path) -> Bool {
        var value: AnyObject?
        try? (path.url as NSURL).getResourceValue(&value, forKey: URLResourceKey("NSURLHasCustomIconKey"))
        return (value as? NSNumber)?.boolValue ?? true
    }

    private static func requireWritable(_ path: Path) throws {
        guard FileManager.default.isWritableFile(atPath: path.string) else {
            throw IconBadgeError.notWritable(path)
        }
    }

    private func drawPill(in context: CGContext, size: CGFloat) {
        var showsText = size >= Self.minimumTextSize

        let maxWidth = size * Self.maxPillWidth
        var fontSize = size * Self.labelFontScale
        var attributedText = attributedLabel(fontSize: fontSize)
        var inkWidth = Self.inkBounds(of: attributedText).width
        // Shrink long labels until they fit.
        while showsText, inkWidth + 2 * Self.padding(for: fontSize) > maxWidth {
            fontSize *= Self.labelShrinkFactor
            if fontSize < Self.minimumFontSize {
                showsText = false
                break
            }
            attributedText = attributedLabel(fontSize: fontSize)
            inkWidth = Self.inkBounds(of: attributedText).width
        }

        let pillWidth: CGFloat
        let pillHeight: CGFloat
        if showsText {
            // The same padding all around the text: digits are cap-height tall and have no descenders, so the pill is
            // sized from the cap height and the glyphs' ink, not from the line box and advance widths, which add extra space.
            pillWidth = inkWidth + 2 * Self.padding(for: fontSize)
            pillHeight = Self.labelFont(size: fontSize).capHeight + 2 * Self.padding(for: fontSize)
        } else {
            pillWidth = size * Self.emptyPillDiameter
            pillHeight = pillWidth
        }
        let pillRect = CGRect(x: (size - pillWidth) / 2, y: size * Self.pillBottomInset, width: pillWidth, height: pillHeight)
        let radius = pillHeight / 2

        // The pill and its drop shadow.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * Self.shadowOffset),
            blur: size * Self.shadowBlur,
            color: NSColor.black.withAlphaComponent(Self.shadowAlpha).cgColor
        )
        context.setFillColor(fillColor.cgColor)
        context.addPath(CGPath(roundedRect: pillRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.restoreGState()

        // A faint inner highlight keeps the pill's edge defined against bright icon art.
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(Self.highlightAlpha).cgColor)
        context.setLineWidth(max(1, size * Self.highlightWidth))
        let inset = size * Self.highlightWidth
        context.addPath(CGPath(roundedRect: pillRect.insetBy(dx: inset, dy: inset), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
        context.restoreGState()

        if showsText {
            let font = Self.labelFont(size: fontSize)
            let baseline = pillRect.midY - font.capHeight / 2
            let ink = Self.inkBounds(of: attributedText)
            attributedText.draw(at: CGPoint(x: pillRect.midX - ink.midX, y: baseline + font.descender))
        }
    }

    /// The badge's label in a heavy weight, followed by its suffix smaller and lighter.
    private func attributedLabel(fontSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: label,
            attributes: [.font: Self.labelFont(size: fontSize), .foregroundColor: NSColor.white]
        )
        if !suffix.isEmpty {
            result.append(NSAttributedString(
                string: suffix,
                attributes: [
                    .font: Self.roundedFont(size: fontSize * Self.suffixFontScale, weight: .medium),
                    .foregroundColor: NSColor.white,
                    .kern: 0,
                ]
            ))
        }
        return result
    }

    private static func padding(for fontSize: CGFloat) -> CGFloat {
        labelFont(size: fontSize).capHeight * paddingScale
    }

    /// The bounds of the glyphs actually drawn, relative to the text's origin.
    private static func inkBounds(of text: NSAttributedString) -> CGRect {
        CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(text), .useGlyphPathBounds)
    }

    private static func labelFont(size: CGFloat) -> NSFont {
        roundedFont(size: size, weight: .heavy)
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded), let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }
}
#endif
