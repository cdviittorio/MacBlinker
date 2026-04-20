import AppKit

class StatusBarController {
    private let statusItem: NSStatusItem
    private var contextMenu: NSMenu!
    private var timer: Timer?

    // Unified alpha drives both hard-blink and fade modes
    private var currentAlpha: CGFloat = 1.0
    // Used by hard-blink to toggle
    private var blinkOn = true
    // Used by fade to track elapsed time
    private var animationStart = Date()

    private var isPaused = false
    private var prefsWindowController: PreferencesWindowController?

    private let circleSize: CGFloat = 16
    // 30 fps for fade; blink uses a slower interval derived from BPM
    private let fadeFPS: TimeInterval = 1.0 / 30.0

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "MacBlinker"
        statusItem.behavior = .removalAllowed
        buildMenu()
        setupButton()
        refreshIcon()
        startTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onSettingsChanged),
            name: .settingsChanged,
            object: nil
        )
    }

    // MARK: - Button & click handling

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.toolTip = "Left-click: pause/resume · Right-click: preferences"
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            buildMenu()   // rebuild so preset checkmarks and BPM labels are fresh
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePause()
        }
    }

    // MARK: - Pause / resume

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
            currentAlpha = 0.3
        } else {
            startTimer()
        }
        refreshIcon()
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        animationStart = Date()
        blinkOn = true
        currentAlpha = 1.0

        if BlinkerSettings.shared.isFade {
            // High-frequency timer: alpha driven by a cosine wave
            timer = Timer.scheduledTimer(withTimeInterval: fadeFPS, repeats: true) { [weak self] _ in
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(self.animationStart)
                let period  = 60.0 / BlinkerSettings.shared.bpm
                // (1 − cos) / 2 gives 0 → 1 → 0 over one period, starting at 0
                self.currentAlpha = CGFloat((1.0 - cos(2.0 * .pi * elapsed / period)) / 2.0)
                self.refreshIcon()
            }
        } else {
            // Low-frequency timer: hard toggle every half-period
            let interval = 30.0 / BlinkerSettings.shared.bpm
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.blinkOn.toggle()
                self.currentAlpha = self.blinkOn ? 1.0 : 0.0
                self.refreshIcon()
            }
        }
    }

    // MARK: - Icon drawing

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        button.image = makeStatusImage()
    }

    private func makeStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: circleSize, height: circleSize), flipped: false) { rect in
            let alpha = self.isPaused ? 0.3 : self.currentAlpha
            BlinkerSettings.shared.color.withAlphaComponent(alpha).setFill()
            self.shapePath(in: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func shapePath(in rect: NSRect) -> NSBezierPath {
        switch BlinkerSettings.shared.shape {
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

    // MARK: - Menu

    /// Rebuilt on every right-click so checkmarks and BPM values are always fresh.
    private func buildMenu() {
        contextMenu = NSMenu()

        // Version badge
        let versionItem = NSMenuItem(title: "MacBlinker v1.2", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        contextMenu.addItem(versionItem)

        contextMenu.addItem(.separator())

        // Speed presets — checkmark shows the currently active one
        for preset in SpeedPreset.allCases {
            let presetBPM = BlinkerSettings.shared.bpm(for: preset)
            let item = NSMenuItem(
                title: "\(preset.label)  —  \(Int(presetBPM)) BPM",
                action: #selector(applyPresetFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (BlinkerSettings.shared.activePreset == preset) ? .on : .off
            contextMenu.addItem(item)
        }

        contextMenu.addItem(.separator())

        let pauseItem = NSMenuItem(title: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        contextMenu.addItem(pauseItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        contextMenu.addItem(prefsItem)

        contextMenu.addItem(.separator())

        contextMenu.addItem(NSMenuItem(title: "Quit MacBlinker",
                                        action: #selector(NSApplication.terminate(_:)),
                                        keyEquivalent: "q"))
    }

    @objc private func applyPresetFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = SpeedPreset(rawValue: raw) else { return }
        BlinkerSettings.shared.applyPreset(preset)
    }

    // MARK: - Settings change

    @objc private func onSettingsChanged() {
        guard !isPaused else { refreshIcon(); return }
        startTimer()
        refreshIcon()
    }

    @objc private func openPreferences() {
        if prefsWindowController == nil {
            prefsWindowController = PreferencesWindowController()
        }
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
