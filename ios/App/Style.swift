import CoreText
import UIKit

// The page's tokens (Web/index.html), light and dark, and its text face: PingFang SC, the first family of the page's
// font list, which iOS has.

extension UIColor {
    private static func pair(_ light: UInt32, _ dark: UInt32) -> UIColor {
        func c(_ v: UInt32) -> UIColor {
            UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        }
        return UIColor { $0.userInterfaceStyle == .dark ? c(dark) : c(light) }
    }
    static let ground = pair(0xeef0f2, 0x111315)
    static let panel = pair(0xffffff, 0x1a1d20)
    static let ink = pair(0x14171a, 0xe8eaec)
    static let muted = pair(0x59626b, 0x9ea6ae)
    static let rule = pair(0xd3d8dd, 0x33393f)
    /// The player's muted text: the dark theme's, whatever the phone's mode (the player is always dark).
    static let playerMuted = UIColor(red: 0x9e / 255.0, green: 0xa6 / 255.0, blue: 0xae / 255.0, alpha: 1)
}

enum Fonts {
    private static var cache: [String: CTFont] = [:]

    /// PingFang SC at the face WebKit picks for a CSS weight: it has nothing above Semibold.
    static func name(_ weight: Int) -> String {
        weight >= 600 ? "PingFangSC-Semibold" : weight >= 500 ? "PingFangSC-Medium" : "PingFangSC-Regular"
    }

    static func font(_ size: CGFloat, _ weight: Int) -> CTFont {
        let key = "\(size)-\(weight)"
        if let f = cache[key] { return f }
        let f = CTFontCreateWithName(name(weight) as CFString, size, nil)
        cache[key] = f
        return f
    }

    static func ui(_ size: CGFloat, _ weight: Int) -> UIFont {
        UIFont(name: name(weight), size: size) ?? .systemFont(ofSize: size)
    }
}

/// One line of text drawn with Core Text at the baseline WebKit gives it: in a line box of the CSS line height, the
/// font's ascent and descent (each rounded up to a whole point) sit after half the leading (rounded down). Text wider
/// than the view ends in an ellipsis, as `text-overflow: ellipsis` does. It is also the accessibility element for its
/// text, so the replica finds the same static texts natively and in the page.
final class Label: UIView {
    var text: String { didSet { accessibilityLabel = text; setNeedsDisplay() } }
    var color: UIColor { didSet { setNeedsDisplay() } }
    var centred = false
    let size: CGFloat, weight: Int, lineHeight: CGFloat

    init(_ text: String, size: CGFloat = 15, weight: Int = 400, color: UIColor = .ink, lineHeight: CGFloat = 24) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.lineHeight = lineHeight
        super.init(frame: .zero)
        isOpaque = false
        contentMode = .topLeft   // a rotation moves the text; it never stretches it
        isUserInteractionEnabled = false   // a tap on a button's words is a tap on the button
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = text
    }
    required init?(coder: NSCoder) { fatalError() }

    private func line(_ color: CGColor? = nil) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): Fonts.font(size, weight)]
        if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    var naturalWidth: CGFloat { CGFloat(CTLineGetTypographicBounds(line(), nil, nil, nil)) }

    private var drawnWidth: CGFloat = -1
    override func layoutSubviews() {
        super.layoutSubviews()
        if drawnWidth != bounds.width { drawnWidth = bounds.width; setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let font = Fonts.font(size, weight)
        let ascent = CTFontGetAscent(font).rounded(.up), descent = CTFontGetDescent(font).rounded(.up)
        let half = ((lineHeight - (ascent + descent)) / 2).rounded(.down)
        let cg = color.resolvedColor(with: traitCollection).cgColor
        var ct = line(cg)
        var width = CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil))
        if width > bounds.width + 0.5 {
            let dots = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [
                .init(kCTFontAttributeName as String): font, .init(kCTForegroundColorAttributeName as String): cg]))
            if let cut = CTLineCreateTruncatedLine(ct, Double(bounds.width), .end, dots) {
                ct = cut
                width = CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil))
            }
        }
        ctx.textMatrix = .identity
        ctx.translateBy(x: centred ? (bounds.width - width) / 2 : 0, y: half + ascent)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(ct, ctx)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsDisplay()
    }
}

/// A plain filled box: rules and sheets. Stretches with the rotation.
final class Box: UIView {
    init(_ color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = color
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The page's icons: 24 viewBox, 2px stroke, square caps, straight lines only (M and L, absolute or relative).
enum Icon {
    static let cross = "M6 6l12 12M18 6L6 18"
    static let back = "M15 5l-7 7 7 7"
    static let pip = "M3 5L21 5L21 19L3 19L3 5M12 12L18 12L18 16L12 16L12 12"

    static func path(_ d: String) -> UIBezierPath {
        let p = UIBezierPath()
        var tokens: [String] = [], cur = ""
        for ch in d {
            if ch.isLetter { if !cur.isEmpty { tokens.append(cur) }; tokens.append(String(ch)); cur = "" }
            else if ch == " " || ch == "," { if !cur.isEmpty { tokens.append(cur) }; cur = "" }
            else if ch == "-" { if !cur.isEmpty { tokens.append(cur) }; cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        var i = 0, cmd = "M", pt = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }
        while i < tokens.count {
            if let first = tokens[i].first, first.isLetter { cmd = tokens[i]; i += 1 }
            let rel = cmd == cmd.lowercased()
            let x = num(), y = num()
            pt = rel ? CGPoint(x: pt.x + x, y: pt.y + y) : CGPoint(x: x, y: y)
            if cmd.uppercased() == "M" { p.move(to: pt); cmd = rel ? "l" : "L" } else { p.addLine(to: pt) }
        }
        return p
    }
}

final class IconView: UIView {
    private let shape = CAShapeLayer()
    var tint: UIColor { didSet { update() } }
    let d: String, size: CGFloat

    init(_ d: String, size: CGFloat, tint: UIColor = .ink) {
        self.d = d
        self.size = size
        self.tint = tint
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        isUserInteractionEnabled = false
        shape.fillColor = nil
        shape.lineCap = .square
        shape.lineJoin = .miter
        layer.addSublayer(shape)
        update()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func update() {
        let path = Icon.path(d)
        path.apply(CGAffineTransform(scaleX: size / 24, y: size / 24))
        shape.path = path.cgPath
        shape.lineWidth = 2 * size / 24
        shape.strokeColor = tint.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        update()
    }
}

/// A filled block button: the page's `button` (44 high, 16 of padding each side, 600 weight). No motion: a touch
/// dims it at once.
final class Block: UIControl {
    private let label: Label
    var onTap: (() -> Void)?

    init(_ text: String, fill: UIColor, textColor: UIColor) {
        label = Label(text, size: 15, weight: 600, color: textColor, lineHeight: 24)
        super.init(frame: .zero)
        backgroundColor = fill
        label.centred = true
        label.isAccessibilityElement = false
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = text
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }

    var naturalWidth: CGFloat { 32 + label.naturalWidth }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 0, y: (bounds.height - 24) / 2, width: bounds.width, height: 24)
    }
    @objc private func tapped() { onTap?() }
}
