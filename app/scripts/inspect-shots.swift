// Prints recognized text (Vision OCR) with positions and a few sampled colors
// for screenshots, so UI evidence can be checked from a CI log.
//   swift scripts/inspect-shots.swift shots/app-panel-ready.png ...
import AppKit
import Foundation
import Vision

func hex(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "n/a" }
    return String(format: "#%02X%02X%02X a=%.2f", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                  Int(c.blueComponent * 255), c.alphaComponent)
}

for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("== \(path): cannot open")
        continue
    }
    print("== \(path) \(cg.width)x\(cg.height)")
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
    let lines = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
    for obs in lines {
        let b = obs.boundingBox
        let text = obs.topCandidates(1).first?.string ?? ""
        print(String(format: "  top=%.2f left=%.2f width=%.2f  ", 1 - b.maxY, b.minX, b.width) + text)
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    let points: [(String, Double, Double)] = [("shell (left edge, mid)", 0.02, 0.5), ("top-left inset", 0.06, 0.03),
                                              ("center", 0.5, 0.5), ("lower-right (button area)", 0.9, 0.92)]
    for (label, fx, fy) in points {
        let x = min(cg.width - 1, max(0, Int(Double(cg.width) * fx)))
        let y = min(cg.height - 1, max(0, Int(Double(cg.height) * fy)))
        print("  color \(label): \(hex(rep.colorAt(x: x, y: y)))")
    }
}
