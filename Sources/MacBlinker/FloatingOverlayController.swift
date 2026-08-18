import AppKit

/// A small borderless panel that mirrors the status-bar blink indicator.
///
/// macOS hides the global menu bar (and therefore the status item) whenever
/// another app — e.g. Teams — is running full-screen in its own Space. This
/// panel uses `.fullScreenAuxiliary` collection behavior so it can be pulled
/// into that Space and stay visible on top of the full-screen app, giving you
/// a way to keep an eye on the blinker during a call/presentation.
final class FloatingOverlayController {
    private let size: CGFloat = 28
    private var window: NSPanel?
    private var overlayView: FloatingOverlayView?

    var isVisible: Bool { window != nil }

    func show() {
        guard window == nil else { return }

        let origin = BlinkerSettings.shared.overlayOrigin ?? defaultOrigin()
        let frame = NSRect(x: origin.x, y: origin.y, width: size, height: size)

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
        panel.ignoresMouseEvents = false

        let view = FloatingOverlayView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.onDragEnded = { [weak self] in self?.persistPosition() }
        panel.contentView = view

        panel.orderFrontRegardless()

        self.window = panel
        self.overlayView = view
    }

    func hide() {
        persistPosition()
        window?.orderOut(nil)
        window = nil
        overlayView = nil
    }

    /// Called from the same timer/refresh path that drives the status-bar icon,
    /// so both indicators stay perfectly in sync.
    func update(alpha: CGFloat, isPaused: Bool) {
        overlayView?.blinkAlpha = isPaused ? 0.3 : alpha
    }

    private func persistPosition() {
        guard let frame = window?.frame else { return }
        BlinkerSettings.shared.overlayOrigin = frame.origin
    }

    private func defaultOrigin() -> NSPoint {
        // Top-right-ish corner of the main screen, clear of the notch/menu bar.
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.maxX - size - 24, y: frame.maxY - size - 24)
    }
}

/// Draws the current shape/color/alpha, identical to the status-bar icon.
private final class FloatingOverlayView: NSView {
    var onDragEnded: (() -> Void)?

    var blinkAlpha: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        BlinkerSettings.shared.color.withAlphaComponent(blinkAlpha).setFill()
        BlinkerRenderer.shapePath(for: BlinkerSettings.shared.shape, in: rect).fill()
    }

    // isMovableByWindowBackground handles the actual drag; we just need to
    // know when a drag finishes so we can persist the new position.
    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
        super.mouseUp(with: event)
    }
}
