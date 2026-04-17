import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("BlinkerSettingsChanged")
}

enum BlinkerShape: String, CaseIterable {
    case circle  = "circle"
    case square  = "square"
    case diamond = "diamond"
    case arrow   = "arrow"
}

/// Persists all blink settings in UserDefaults and broadcasts changes.
class BlinkerSettings {
    static let shared = BlinkerSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let red    = "blinkColorRed"
        static let green  = "blinkColorGreen"
        static let blue   = "blinkColorBlue"
        static let bpm    = "blinkBPM"
        static let shape  = "blinkShape"
        static let isFade = "blinkFade"
    }

    var color: NSColor {
        get {
            let r = defaults.object(forKey: Key.red)   as? CGFloat ?? 1.0
            let g = defaults.object(forKey: Key.green) as? CGFloat ?? 0.2
            let b = defaults.object(forKey: Key.blue)  as? CGFloat ?? 0.2
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }
        set {
            guard let rgb = newValue.usingColorSpace(.sRGB) else { return }
            defaults.set(rgb.redComponent,   forKey: Key.red)
            defaults.set(rgb.greenComponent, forKey: Key.green)
            defaults.set(rgb.blueComponent,  forKey: Key.blue)
            notify()
        }
    }

    /// Blinks per minute — range 12 … 300
    var bpm: Double {
        get { defaults.object(forKey: Key.bpm) as? Double ?? 60.0 }
        set { defaults.set(newValue, forKey: Key.bpm); notify() }
    }

    var shape: BlinkerShape {
        get {
            guard let raw = defaults.string(forKey: Key.shape),
                  let s = BlinkerShape(rawValue: raw) else { return .circle }
            return s
        }
        set { defaults.set(newValue.rawValue, forKey: Key.shape); notify() }
    }

    /// true = smooth sine fade, false = hard on/off blink
    var isFade: Bool {
        get { defaults.object(forKey: Key.isFade) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.isFade); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
