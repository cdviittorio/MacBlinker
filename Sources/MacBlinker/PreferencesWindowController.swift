import AppKit
import SwiftUI

class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 310),
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

struct PreferencesView: View {
    @State private var color:  Color        = Color(BlinkerSettings.shared.color)
    @State private var speed:  Double       = BlinkerSettings.shared.bpm
    @State private var shape:  BlinkerShape = BlinkerSettings.shared.shape
    @State private var isFade: Bool         = BlinkerSettings.shared.isFade

    // SF Symbol name for each shape
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
            VStack(alignment: .leading, spacing: 6) {
                row(label: "Speed") {
                    Text("\(Int(speed)) BPM")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Text("Slow").font(.caption).foregroundColor(.secondary)
                    Slider(value: $speed, in: 12...300, step: 1)
                        .onChange(of: speed) { BlinkerSettings.shared.bpm = $0 }
                    Text("Fast").font(.caption).foregroundColor(.secondary)
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

            Spacer()
        }
        .padding(24)
        .frame(width: 340, height: 310)
    }

    // Small helper to keep label + control aligned consistently
    @ViewBuilder
    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            content()
        }
    }
}
