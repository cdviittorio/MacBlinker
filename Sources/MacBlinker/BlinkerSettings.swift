import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("BlinkerSettingsChanged")
}

// MARK: - Speed Presets

enum SpeedPreset: String, CaseIterable {
    case turtle = "turtle"
    case normal = "normal"
    case rabbit = "rabbit"

    var label: String {
        switch self {
        case .turtle: return "🐢  Turtle"
        case .normal: return "🚶  Normal"
        case .rabbit: return "🐇  Rabbit"
        }
    }

    var defaultBPM: Double {
        switch self {
        case .turtle: return 20
        case .normal: return 60
        case .rabbit: return 120
        }
    }
}

// MARK: - Shape

enum BlinkerShape: String, CaseIterable {
    case circle  = "circle"
    case square  = "square"
    case diamond = "diamond"
    case arrow   = "arrow"
}

// MARK: - Settings

/// Persists all blink settings in UserDefaults and broadcasts changes.
class BlinkerSettings {
    static let shared = BlinkerSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let red          = "blinkColorRed"
        static let green        = "blinkColorGreen"
        static let blue         = "blinkColorBlue"
        static let bpm          = "blinkBPM"
        static let shape        = "blinkShape"
        static let isFade       = "blinkFade"
        static let presetTurtle = "presetTurtle"
        static let presetNormal = "presetNormal"
        static let presetRabbit = "presetRabbit"
        static let floatOverFullscreen = "floatOverFullscreen"
        static let overlayOriginX      = "overlayOriginX"
        static let overlayOriginY      = "overlayOriginY"
    }

    // MARK: Color

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

    // MARK: Speed

    /// Current blinks per minute — range 12 … 300
    var bpm: Double {
        get { defaults.object(forKey: Key.bpm) as? Double ?? 60.0 }
        set { defaults.set(newValue, forKey: Key.bpm); notify() }
    }

    // MARK: Presets

    var turtleBPM: Double {
        get { defaults.object(forKey: Key.presetTurtle) as? Double ?? SpeedPreset.turtle.defaultBPM }
        set { defaults.set(newValue, forKey: Key.presetTurtle); notify() }
    }

    var normalBPM: Double {
        get { defaults.object(forKey: Key.presetNormal) as? Double ?? SpeedPreset.normal.defaultBPM }
        set { defaults.set(newValue, forKey: Key.presetNormal); notify() }
    }

    var rabbitBPM: Double {
        get { defaults.object(forKey: Key.presetRabbit) as? Double ?? SpeedPreset.rabbit.defaultBPM }
        set { defaults.set(newValue, forKey: Key.presetRabbit); notify() }
    }

    func bpm(for preset: SpeedPreset) -> Double {
        switch preset {
        case .turtle: return turtleBPM
        case .normal: return normalBPM
        case .rabbit: return rabbitBPM
        }
    }

    /// Apply a preset — sets bpm to the preset's configured value
    func applyPreset(_ preset: SpeedPreset) {
        bpm = bpm(for: preset)
    }

    /// Returns the active preset if the current BPM exactly matches one
    var activePreset: SpeedPreset? {
        SpeedPreset.allCases.first { abs(bpm(for: $0) - bpm) < 0.5 }
    }

    // MARK: Shape / Transition

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

    // MARK: - Floating overlay (shows the blinker over full-screen apps)

    /// When true, a small floating dot is kept on top of everything —
    /// including apps running full-screen in their own Space (e.g. Teams) —
    /// in addition to the status-bar icon.
    var floatOverFullscreen: Bool {
        get { defaults.object(forKey: Key.floatOverFullscreen) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.floatOverFullscreen); notify() }
    }

    /// Last dragged position of the floating overlay, so it reopens where you left it.
    var overlayOrigin: NSPoint? {
        get {
            guard let x = defaults.object(forKey: Key.overlayOriginX) as? Double,
                  let y = defaults.object(forKey: Key.overlayOriginY) as? Double else { return nil }
            return NSPoint(x: x, y: y)
        }
        set {
            guard let point = newValue else { return }
            defaults.set(Double(point.x), forKey: Key.overlayOriginX)
            defaults.set(Double(point.y), forKey: Key.overlayOriginY)
            // Position changes don't need a full settings-changed broadcast/timer restart.
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
