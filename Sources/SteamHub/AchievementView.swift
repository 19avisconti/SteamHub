import AppKit
import CoreText

/// Draws the Steam achievement toast: the supplied background art plus two lines of text.
///
/// Every position below is a fraction of the notification's own width/height, measured off
/// `reference.png` (1414x565) by profiling the ink rows of the rendered text. That keeps the
/// layout locked to the artwork at any display size.
final class AchievementView: NSView {

    private enum Layout {
        static let textLeft: CGFloat = 0.3543      // × width
        static let textRight: CGFloat = 0.9550     // × width
        static let titleSize: CGFloat = 0.1381     // × height
        static let titleBaseline: CGFloat = 0.3540 // × height, from the top
        static let bodySize: CGFloat = 0.0947      // × height
        static let bodyBaseline: CGFloat = 0.6844  // × height, from the top
        static let bodyLeading: CGFloat = 0.1138   // × height, baseline to baseline
        static let bodyMaxLines = 2
    }

    private static let titleColor = NSColor.white                                   // #FFFFFF
    private static let bodyColor = NSColor(srgbRed: 0xDB / 255.0, green: 0xD9 / 255.0,
                                           blue: 0xD8 / 255.0, alpha: 1)             // #DBD9D8

    private let background: NSImage?
    var title = ""
    var body = ""

    init(frame: NSRect, background: NSImage?) {
        self.background = background
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        background?.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let left = Layout.textLeft * w
        let maxWidth = Layout.textRight * w - left

        // The view is unflipped, so a baseline measured from the top becomes h - y.
        draw(title, font: font(ofSize: Layout.titleSize * h), color: Self.titleColor,
             in: ctx, x: left, maxWidth: maxWidth,
             firstBaseline: h - Layout.titleBaseline * h, leading: 0, maxLines: 1)

        draw(body, font: font(ofSize: Layout.bodySize * h), color: Self.bodyColor,
             in: ctx, x: left, maxWidth: maxWidth,
             firstBaseline: h - Layout.bodyBaseline * h, leading: Layout.bodyLeading * h,
             maxLines: Layout.bodyMaxLines)
    }

    /// Steam's client renders these strings in Arial; Helvetica is the metric-compatible fallback.
    private func font(ofSize size: CGFloat) -> NSFont {
        NSFont(name: "Arial", size: size)
            ?? NSFont(name: "Helvetica", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    /// Lays out up to `maxLines` lines by hand so each baseline lands exactly where the
    /// reference puts it, truncating the last line with an ellipsis when text remains.
    private func draw(_ string: String, font: NSFont, color: NSColor, in ctx: CGContext,
                      x: CGFloat, maxWidth: CGFloat, firstBaseline: CGFloat,
                      leading: CGFloat, maxLines: Int) {
        guard !string.isEmpty, maxWidth > 0 else { return }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let attributed = NSAttributedString(string: string, attributes: attrs)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let total = attributed.length

        var lines: [CTLine] = []
        var start = 0
        while start < total && lines.count < maxLines {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth))
            guard count > 0 else { break }

            let isLastAllowed = lines.count == maxLines - 1
            if isLastAllowed && start + count < total {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: total - start))
                let token = CTLineCreateWithAttributedString(
                    NSAttributedString(string: "\u{2026}", attributes: attrs))
                if let truncated = CTLineCreateTruncatedLine(rest, Double(maxWidth), .end, token) {
                    lines.append(truncated)
                    break
                }
            }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }

        for (i, line) in lines.enumerated() {
            ctx.textPosition = CGPoint(x: x, y: firstBaseline - CGFloat(i) * leading)
            CTLineDraw(line, ctx)
        }
    }
}
