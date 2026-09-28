import Foundation

/// Rectangle in global Cocoa screen coordinates (origin bottom-left, y up).
public struct PanelRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    func contains(_ other: PanelRect) -> Bool {
        other.minX >= minX - 0.5 && other.maxX <= maxX + 0.5 && other.minY >= minY - 0.5 && other.maxY <= maxY + 0.5
    }

    func intersectionArea(_ o: PanelRect) -> Double {
        let w = min(maxX, o.maxX) - max(minX, o.minX)
        let h = min(maxY, o.maxY) - max(minY, o.minY)
        return (w > 0 && h > 0) ? w * h : 0
    }

    func containsPoint(x px: Double, y py: Double) -> Bool {
        px >= minX && px <= maxX && py >= minY && py <= maxY
    }
}

public enum PanelSide: String, Equatable, Sendable {
    case right, left, below, above
    /// No selection bounds: placed near the source window or pointer, not anchored.
    case unanchored
    /// No side fit; overlap minimized.
    case overlapping
}

public struct PlacementResult: Equatable, Sendable {
    public let frame: PanelRect
    public let side: PanelSide
}

/// Choose where the floating panel goes (UX.md "Placement and animation"):
/// try right, left, below, above; clamp to the display's usable frame; avoid
/// covering the selection when feasible; minimize overlap otherwise.
public enum PanelPlacement {
    public static let gap: Double = 12

    public static func place(size: (width: Double, height: Double), selection: PanelRect?,
                             visibleFrames: [PanelRect], fallbackPoint: (x: Double, y: Double)) -> PlacementResult {
        guard !visibleFrames.isEmpty else {
            return PlacementResult(frame: PanelRect(x: fallbackPoint.x, y: fallbackPoint.y - size.height,
                                                    width: size.width, height: size.height), side: .unanchored)
        }
        guard let sel = selection else {
            let screen = screenFor(x: fallbackPoint.x, y: fallbackPoint.y, in: visibleFrames)
            let w = min(size.width, screen.width), h = min(size.height, screen.height)
            let raw = PanelRect(x: fallbackPoint.x + gap, y: fallbackPoint.y - h - gap, width: w, height: h)
            return PlacementResult(frame: clamp(raw, to: screen), side: .unanchored)
        }
        let screen = screenFor(x: sel.midX, y: sel.midY, in: visibleFrames)
        let w = min(size.width, screen.width), h = min(size.height, screen.height)

        // Align the panel's top with the selection's top for side placements.
        let candidates: [(PanelSide, PanelRect)] = [
            (.right, PanelRect(x: sel.maxX + gap, y: sel.maxY - h, width: w, height: h)),
            (.left, PanelRect(x: sel.minX - gap - w, y: sel.maxY - h, width: w, height: h)),
            (.below, PanelRect(x: sel.minX, y: sel.minY - gap - h, width: w, height: h)),
            (.above, PanelRect(x: sel.minX, y: sel.maxY + gap, width: w, height: h)),
        ]
        for (side, raw) in candidates {
            // Only the axis along the selection may slide; the side axis must fit as-is.
            let slid = slideAlongCrossAxis(raw, side: side, within: screen)
            if screen.contains(slid) && slid.intersectionArea(sel) == 0 {
                return PlacementResult(frame: slid, side: side)
            }
        }
        var best: (PanelSide, PanelRect, Double)? = nil
        for (side, raw) in candidates {
            let c = clamp(raw, to: screen)
            let overlap = c.intersectionArea(sel)
            if best == nil || overlap < best!.2 { best = (side, c, overlap) }
        }
        return PlacementResult(frame: best!.1, side: .overlapping)
    }

    static func slideAlongCrossAxis(_ r: PanelRect, side: PanelSide, within s: PanelRect) -> PanelRect {
        var out = r
        switch side {
        case .right, .left:
            out.y = min(max(r.y, s.minY), s.maxY - r.height)
        case .below, .above:
            out.x = min(max(r.x, s.minX), s.maxX - r.width)
        default:
            break
        }
        return out
    }

    static func clamp(_ r: PanelRect, to s: PanelRect) -> PanelRect {
        var out = r
        out.x = min(max(r.x, s.minX), s.maxX - r.width)
        out.y = min(max(r.y, s.minY), s.maxY - r.height)
        return out
    }

    static func screenFor(x: Double, y: Double, in frames: [PanelRect]) -> PanelRect {
        if let hit = frames.first(where: { $0.containsPoint(x: x, y: y) }) { return hit }
        return frames.min(by: { distance($0, x, y) < distance($1, x, y) }) ?? frames[0]
    }

    static func distance(_ r: PanelRect, _ x: Double, _ y: Double) -> Double {
        let dx = max(r.minX - x, 0, x - r.maxX)
        let dy = max(r.minY - y, 0, y - r.maxY)
        return dx * dx + dy * dy
    }
}
