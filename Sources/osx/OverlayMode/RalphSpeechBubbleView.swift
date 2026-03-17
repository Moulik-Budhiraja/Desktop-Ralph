import AppKit

@MainActor
final class RalphSpeechBubbleView: NSView {
    private let bubbleColor = NSColor(calibratedWhite: 0.98, alpha: 0.95)
    private let textField: NSTextField

    init(message: String) {
        self.textField = NSTextField(labelWithString: message)
        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        self.textField.textColor = .black
        self.textField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        self.textField.alignment = .center
        self.textField.lineBreakMode = .byWordWrapping
        self.textField.isBezeled = false
        self.textField.drawsBackground = false
        self.textField.isEditable = false
        self.textField.isSelectable = false
        self.textField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.textField)

        NSLayoutConstraint.activate([
            self.textField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            self.textField.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            self.textField.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
            self.textField.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current else {
            return
        }

        NSColor.clear.setFill()
        context.cgContext.fill(dirtyRect)

        let bubbleRect = CGRect(
            x: 0,
            y: 8,
            width: bounds.width,
            height: bounds.height - 8)

        let rounded = NSBezierPath(roundedRect: bubbleRect, xRadius: 10, yRadius: 10)

        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: 20, y: 8))
        tail.line(to: CGPoint(x: 30, y: 0))
        tail.line(to: CGPoint(x: 40, y: 8))

        self.bubbleColor.setFill()
        self.bubbleColor.setStroke()
        rounded.fill()
        rounded.stroke()
        tail.fill()
        tail.stroke()
    }
}
