import AppKit

@MainActor
final class RalphSpeechBubbleView: NSView {
    private let bubbleColor = NSColor(calibratedWhite: 0.98, alpha: 0.95)
    private var message: String
    private let textColor = NSColor(calibratedWhite: 0.1, alpha: 0.95)
    private static let preferredFontNames = [
        "Menlo",
        "Menlo-Regular",
        "Courier New",
        "Courier",
    ]
    private static let maximumFontSize: CGFloat = 13
    private static let minimumFontSize: CGFloat = 8
    private static let horizontalInset: CGFloat = 10
    private static let verticalInset: CGFloat = 8
    private static let minimumBubbleWidth: CGFloat = 96
    private static let maximumTextWidth: CGFloat = 156
    private static let minimumBubbleHeight: CGFloat = 42

    init(message: String) {
        self.message = message
        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func preferredSize(for message: String) -> CGSize {
        let text = NSString(string: message)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = Self.pickFont(size: Self.maximumFontSize)
        let textBounds = text.boundingRect(
            with: CGSize(width: Self.maximumTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ])

        return CGSize(
            width: max(Self.minimumBubbleWidth, ceil(textBounds.width) + (Self.horizontalInset * 2)),
            height: max(Self.minimumBubbleHeight, ceil(textBounds.height) + (Self.verticalInset * 2)))
    }

    override var isFlipped: Bool { true }

    func updateMessage(_ message: String) {
        guard self.message != message else { return }
        self.message = message
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bubblePath = NSBezierPath(roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        self.bubbleColor.setFill()
        bubblePath.fill()
        self.bubbleColor.setStroke()
        bubblePath.stroke()

        let contentRect = self.bounds.insetBy(
            dx: Self.horizontalInset,
            dy: Self.verticalInset)
        guard !contentRect.isEmpty, !self.message.isEmpty else { return }

        let font = self.fittedFont(for: contentRect)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: self.textColor,
            .paragraphStyle: paragraphStyle,
        ]

        let textRect = NSString(string: self.message).boundingRect(
            with: contentRect.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes)
        let centeredRect = CGRect(
            x: contentRect.minX + ((contentRect.width - textRect.width) / 2),
            y: contentRect.minY + ((contentRect.height - textRect.height) / 2),
            width: textRect.width,
            height: textRect.height)
            .integral

        (NSString(string: self.message) as NSString).draw(
            with: centeredRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil)
    }

    private func fittedFont(for bounds: CGRect) -> NSFont {
        let text = NSString(string: self.message)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        var fontSize = Self.maximumFontSize
        while fontSize >= Self.minimumFontSize {
            let font = Self.pickFont(size: fontSize)
            let textRect = text.boundingRect(
                with: bounds.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                ])

            if textRect.height <= bounds.height && textRect.width <= bounds.width {
                return font
            }
            fontSize -= 0.5
        }

        return Self.pickFont(size: Self.minimumFontSize)
    }

    private static func pickFont(size: CGFloat) -> NSFont {
        for name in Self.preferredFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }
}
