import AppKit

/// Small floating readout shown while Coaching Mode is on — live WPM plus
/// the word count behind it, color-coded to the current pace band, so you
/// can glance at your pace without hunting for the tiny menu-bar icon.
final class CoachingHUDController {
    private let size = NSSize(width: 118, height: 40)
    private var window: NSPanel?
    private var hudView: CoachingHUDView?

    var isVisible: Bool { window != nil }

    func show() {
        guard window == nil else { return }

        let origin = BlinkerSettings.shared.coachingHUDOrigin ?? defaultOrigin()
        let frame = NSRect(origin: origin, size: size)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let view = CoachingHUDView(frame: NSRect(origin: .zero, size: size))
        view.onDragEnded = { [weak self] in self?.persistPosition() }
        panel.contentView = view

        panel.orderFrontRegardless()
        self.window = panel
        self.hudView = view
    }

    func hide() {
        persistPosition()
        window?.orderOut(nil)
        window = nil
        hudView = nil
    }

    func update(words: Int, wpm: Double?, color: NSColor) {
        hudView?.words = words
        hudView?.wpm = wpm
        hudView?.color = color
    }

    private func persistPosition() {
        guard let frame = window?.frame else { return }
        BlinkerSettings.shared.coachingHUDOrigin = frame.origin
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 160) }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.maxX - size.width - 24, y: frame.maxY - size.height - 64)
    }
}

private final class CoachingHUDView: NSView {
    var onDragEnded: (() -> Void)?

    var words: Int = 0 { didSet { needsDisplay = true } }
    var wpm: Double? = nil { didSet { needsDisplay = true } }
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        let dotRect = NSRect(x: 12, y: bounds.midY - 6, width: 12, height: 12)
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let wpmText = wpm != nil ? "\(Int(wpm!)) wpm" : "-- wpm"
        let wpmAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        wpmText.draw(at: NSPoint(x: 32, y: bounds.midY - 1), withAttributes: wpmAttrs)

        let wordsText = "\(words) words"
        let wordsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            .paragraphStyle: paragraph
        ]
        wordsText.draw(at: NSPoint(x: 32, y: bounds.midY - 16), withAttributes: wordsAttrs)
    }

    // isMovableByWindowBackground handles the actual drag; we just need to
    // know when a drag finishes so we can persist the new position.
    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
        super.mouseUp(with: event)
    }
}
