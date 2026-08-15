import AppKit

final class HotkeyMenuRowView: NSView {
    var onClick: (() -> Void)?
    weak var label: NSTextField?

    private var hoverTrackingArea: NSTrackingArea?
    private var isHighlighted = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            label?.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        hoverTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hoverTrackingArea!)
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            let rect = bounds.insetBy(dx: 4, dy: 1).offsetBy(dx: 0, dy: 2)
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class LanguageMenuRowView: NSView {
    private weak var checkbox: NSButton?

    init(checkbox: NSButton, frame: NSRect) {
        self.checkbox = checkbox
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { checkbox?.performClick(self) }
}
