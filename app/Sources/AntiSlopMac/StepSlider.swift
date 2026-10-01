#if os(macOS)
import AppKit
import SwiftUI

/// Native stepped input with a branded celebration reserved for the highest setting.
struct StepSlider: View {
    let title: String
    let labels: [String]
    @Binding var selection: Int
    var celebratesMaximum = false
    var bloomColor: Color = Theme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    private var celebrating: Bool { celebratesMaximum && selection == labels.count - 1 && isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title)
                Spacer()
                Text(labels[selection])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !celebrating || reduceMotion)) { timeline in
                NativeStepSlider(
                    title: title, labels: labels, selection: $selection, color: bloomColor,
                    celebratesMaximum: celebratesMaximum, animatesParticles: !reduceMotion,
                    animationTime: timeline.date.timeIntervalSinceReferenceDate
                )
                .frame(height: 30)
            }
            HStack(spacing: 0) {
                ForEach(labels.indices, id: \.self) { index in
                    Button { selection = index } label: {
                        Text(labels[index])
                            .font(.system(size: 11.5, weight: selection == index ? .semibold : .regular))
                            .foregroundColor(selection == index ? Theme.action : Theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == index ? (celebrating ? bloomColor.opacity(0.10) : Theme.statusFill) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(labels[index])")
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(Color.white)
                .shadow(color: celebrating ? bloomColor.opacity(0.25) : .clear, radius: 12)
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: celebrating ? [bloomColor.opacity(0.5), bloomColor] : [Theme.border, Theme.border],
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                ))
        }
    }
}

/// Keep AppKit's hit testing, tick snapping, focus ring, keyboard and accessibility
/// behavior and thumb. Only the maximum-level track drawing changes.
struct NativeStepSlider: NSViewRepresentable {
    let title: String
    let labels: [String]
    @Binding var selection: Int
    let color: Color
    var celebratesMaximum = false
    var animatesParticles = false
    var animationTime: TimeInterval = 0
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = BrandedSliderCell()
        slider.isVertical = false
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.focusRingType = .exterior
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.labels = labels
        slider.minValue = 0
        slider.maxValue = Double(labels.count - 1)
        slider.numberOfTickMarks = labels.count
        slider.allowsTickMarkValuesOnly = true
        slider.doubleValue = Double(selection)
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityValueDescription(labels[selection])
        if let cell = slider.cell as? BrandedSliderCell {
            cell.brandColor = NSColor(color)
            cell.celebratesMaximum = celebratesMaximum
            cell.animatesParticles = animatesParticles
            cell.animationTime = animationTime
        }
        slider.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Int>
        var labels: [String] = []
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ slider: NSSlider) {
            let index = min(labels.count - 1, max(0, Int(slider.doubleValue.rounded())))
            guard labels.indices.contains(index) else { return }
            slider.doubleValue = Double(index)
            selection.wrappedValue = index
            slider.setAccessibilityValueDescription(labels[index])
        }
    }
}

final class BrandedSliderCell: NSSliderCell {
    var brandColor = NSColor(Theme.action)
    var celebratesMaximum = false
    var animatesParticles = false
    var animationTime: TimeInterval = 0

    var isCelebrating: Bool { celebratesMaximum && isEnabled && doubleValue == maxValue }

    func maximumTrackRect(inside rect: NSRect, flipped: Bool) -> NSRect {
        // AppKit owns the thumb geometry, including its endpoint clearance.
        NSRect(x: rect.minX, y: knobRect(flipped: flipped).midY - 6, width: rect.width, height: 12)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard isCelebrating else {
            super.drawBar(inside: rect, flipped: flipped)
            return
        }
        let track = maximumTrackRect(inside: rect, flipped: flipped)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.shouldAntialias = true
        // Layered bloom shares the track's left-to-right opacity ramp.
        NSGraphicsContext.saveGraphicsState()
        let halo = NSBezierPath(rect: track.insetBy(dx: 0, dy: -6))
        halo.append(NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6))
        halo.windingRule = .evenOdd
        halo.addClip()
        for spread in stride(from: 6, through: 1, by: -1) {
            drawGradient(in: track.insetBy(dx: 0, dy: -CGFloat(spread)), opacity: 0.085)
        }
        NSGraphicsContext.restoreGraphicsState()
        drawGradient(in: track, opacity: 1)
        if animatesParticles { drawParticles(in: track, flipped: flipped) }
        // Inherit drawKnob: the native thumb stays centered and inside its bounds.
    }

    private func drawGradient(in rect: NSRect, opacity: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).addClip()
        NSGradient(starting: brandColor.withAlphaComponent(0.5 * opacity),
                   ending: brandColor.withAlphaComponent(opacity))?.draw(in: rect, angle: 0)
    }

    private func drawParticles(in track: NSRect, flipped: Bool) {
        // Draw effects in the same coordinates as the bar, behind the native thumb.
        for index in 0..<44 {
            let phase = (animationTime * 0.08 + Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
            let x = track.minX + 5 + CGFloat(phase) * max(0, track.width - 10)
            let side: CGFloat = index % 5 == 0 ? 3 : 2
            let y = track.midY + CGFloat((index * 5) % 9) - 4 - side / 2
            let shimmer = 0.6 + 0.3 * (0.5 + 0.5 * sin(animationTime * 1.5 + Double(index)))
            NSColor.white.withAlphaComponent(shimmer * directionalOpacity(at: x, in: track)).setFill()
            NSRect(x: x, y: y, width: side, height: side).fill()
        }
        for index in 0..<14 {
            let phase = (animationTime * 0.28 + Double(index) / 14).truncatingRemainder(dividingBy: 1)
            let x = track.minX + 5 + CGFloat((index * 37) % 100) / 100 * max(0, track.width - 10)
            let distance = track.height / 2 + 2 + CGFloat(phase * 5)
            let side: CGFloat = index % 3 == 0 ? 3 : 2
            let y = track.midY + (flipped ? -distance : distance) - side / 2
            brandColor.withAlphaComponent((1 - phase) * 0.85 * directionalOpacity(at: x, in: track)).setFill()
            NSRect(x: x, y: y, width: side, height: side).fill()
        }
    }

    private func directionalOpacity(at x: CGFloat, in track: NSRect) -> CGFloat {
        0.5 + 0.5 * min(1, max(0, (x - track.minX) / max(1, track.width)))
    }

    override func drawTickMarks() {} // The labelled stops below the track show every choice.
}
#endif
