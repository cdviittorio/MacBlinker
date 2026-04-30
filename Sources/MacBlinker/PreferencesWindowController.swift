import AppKit
import SwiftUI

class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacBlinker Preferences"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.center()
        self.init(window: window)
    }
}

// MARK: - Main Preferences View

struct PreferencesView: View {
    @State private var color:     Color        = Color(BlinkerSettings.shared.color)
    @State private var speed:     Double       = BlinkerSettings.shared.bpm
    @State private var shape:     BlinkerShape = BlinkerSettings.shared.shape
    @State private var isFade:    Bool         = BlinkerSettings.shared.isFade
    @State private var turtleBPM: Double       = BlinkerSettings.shared.turtleBPM
    @State private var normalBPM: Double       = BlinkerSettings.shared.normalBPM
    @State private var rabbitBPM: Double       = BlinkerSettings.shared.rabbitBPM

    /// Returns the matching preset if `bpm` exactly matches one of the configured preset values.
    /// Uses local @State values so it reacts instantly when presets are edited in this panel.
    private func activePreset(for bpm: Double) -> SpeedPreset? {
        if abs(bpm - turtleBPM) < 0.5 { return .turtle }
        if abs(bpm - normalBPM) < 0.5 { return .normal }
        if abs(bpm - rabbitBPM) < 0.5 { return .rabbit }
        return nil
    }

    private func symbol(for shape: BlinkerShape) -> String {
        switch shape {
        case .circle:  return "circle.fill"
        case .square:  return "square.fill"
        case .diamond: return "diamond.fill"
        case .arrow:   return "arrowtriangle.right.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // ── Color ─────────────────────────────────────────────
            row(label: "Color") {
                ColorPicker("", selection: $color)
                    .labelsHidden()
                    .onChange(of: color) { BlinkerSettings.shared.color = NSColor($0) }
            }

            // ── Speed ─────────────────────────────────────────────
            row(label: "Speed") {
                VStack(alignment: .leading, spacing: 4) {
                    SpeedControl(speed: $speed, min: 12, max: 300) {
                        BlinkerSettings.shared.bpm = speed
                    }
                    // Active preset / custom indicator
                    HStack(spacing: 4) {
                        Image(systemName: activePreset(for: speed) != nil ? "checkmark.circle.fill" : "slider.horizontal.3")
                            .font(.caption)
                            .foregroundColor(activePreset(for: speed) != nil ? .green : .secondary)
                        Text(activePreset(for: speed).map { "Preset: \($0.label)  —  \(Int(speed)) BPM" } ?? "Custom speed — \(Int(speed)) BPM")
                            .font(.caption)
                            .foregroundColor(activePreset(for: speed) != nil ? .green : .secondary)
                    }
                }
            }

            // ── Shape ─────────────────────────────────────────────
            row(label: "Shape") {
                Picker("", selection: $shape) {
                    ForEach(BlinkerShape.allCases, id: \.self) { s in
                        Image(systemName: symbol(for: s)).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: shape) { BlinkerSettings.shared.shape = $0 }
            }

            // ── Transition ────────────────────────────────────────
            row(label: "Transition") {
                Picker("", selection: $isFade) {
                    Text("Hard blink").tag(false)
                    Text("Fade").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: isFade) { BlinkerSettings.shared.isFade = $0 }
            }

            Divider()

            // ── Presets ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Speeds")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                PresetRow(label: "🐢  Turtle", bpm: $turtleBPM, currentSpeed: speed) {
                    BlinkerSettings.shared.turtleBPM = turtleBPM
                }
                PresetRow(label: "🚶  Normal", bpm: $normalBPM, currentSpeed: speed) {
                    BlinkerSettings.shared.normalBPM = normalBPM
                }
                PresetRow(label: "🐇  Rabbit", bpm: $rabbitBPM, currentSpeed: speed) {
                    BlinkerSettings.shared.rabbitBPM = rabbitBPM
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 340, height: 460)
    }

    @ViewBuilder
    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            content()
        }
    }
}

// MARK: - Speed Control (±5 coarse, ±1 fine)

struct SpeedControl: View {
    @Binding var speed: Double
    let min: Double
    let max: Double
    let onChange: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                stepButton(symbol: "minus.circle.fill", size: .title, step: -5)
                VStack(spacing: 1) {
                    Text("\(Int(speed))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 64, alignment: .center)
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                stepButton(symbol: "plus.circle.fill", size: .title, step: +5)
            }
            HStack(spacing: 6) {
                fineButton(label: "−1", step: -1)
                Text("fine").font(.caption2).foregroundColor(.secondary)
                fineButton(label: "+1", step: +1)
            }
        }
    }

    @ViewBuilder
    private func stepButton(symbol: String, size: Font, step: Double) -> some View {
        Button { nudge(by: step) } label: {
            Image(systemName: symbol)
                .font(size)
                .foregroundColor(canNudge(by: step) ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canNudge(by: step))
    }

    @ViewBuilder
    private func fineButton(label: String, step: Double) -> some View {
        Button { nudge(by: step) } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canNudge(by: step))
    }

    private func nudge(by step: Double) {
        speed = Swift.max(min, Swift.min(max, speed + step))
        onChange()
    }

    private func canNudge(by step: Double) -> Bool {
        step < 0 ? speed > min : speed < max
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    let label: String
    @Binding var bpm: Double
    let currentSpeed: Double   // speed currently set in the Speed control
    let onChange: () -> Void

    private var isActive: Bool { abs(bpm - currentSpeed) < 0.5 }

    var body: some View {
        HStack(spacing: 0) {
            // Preset name
            Text(label)
                .frame(width: 100, alignment: .leading)

            // Stored BPM value
            Text("\(Int(bpm)) BPM")
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            // Update button — stamps current speed into this preset
            Button {
                bpm = currentSpeed
                onChange()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isActive ? "checkmark" : "arrow.up.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(isActive ? "Active" : "Set to \(Int(currentSpeed)) BPM")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                .foregroundColor(isActive ? .green : .accentColor)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isActive)
        }
    }
}
