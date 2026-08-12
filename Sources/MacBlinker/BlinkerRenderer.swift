import AppKit

/// Shared drawing logic for the blink indicator, used by both the
/// status-bar icon (StatusBarController) and the floating overlay dot
/// (FloatingOverlayView) so the two always look identical.
enum BlinkerRenderer {
    static func shapePath(for shape: BlinkerShape, in rect: NSRect) -> NSBezierPath {
        switch shape {
        case .circle:
            return NSBezierPath(ovalIn: rect)

        case .square:
            return NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)

        case .diamond:
            let path = NSBezierPath()
            path.move(to:  NSPoint(x: rect.midX,  y: rect.maxY))
            path.line(to:  NSPoint(x: rect.maxX,  y: rect.midY))
            path.line(to:  NSPoint(x: rect.midX,  y: rect.minY))
            path.line(to:  NSPoint(x: rect.minX,  y: rect.midY))
            path.close()
            return path

        case .arrow:
            // Right-pointing arrow: rectangular shaft + triangular head
            let shaftH   = rect.height * 0.38
            let shaftTop = rect.midY + shaftH / 2
            let shaftBot = rect.midY - shaftH / 2
            let neckX    = rect.minX + rect.width * 0.55  // where shaft meets head

            let path = NSBezierPath()
            path.move(to:  NSPoint(x: rect.minX, y: shaftTop))   // shaft TL
            path.line(to:  NSPoint(x: neckX,     y: shaftTop))   // shaft TR / neck top
            path.line(to:  NSPoint(x: neckX,     y: rect.maxY))  // head top wing
            path.line(to:  NSPoint(x: rect.maxX, y: rect.midY))  // tip
            path.line(to:  NSPoint(x: neckX,     y: rect.minY))  // head bottom wing
            path.line(to:  NSPoint(x: neckX,     y: shaftBot))   // shaft BR / neck bottom
            path.line(to:  NSPoint(x: rect.minX, y: shaftBot))   // shaft BL
            path.close()
            return path
        }
    }
}
