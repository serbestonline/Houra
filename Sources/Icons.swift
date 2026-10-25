import SwiftUI

// Kategori ikonları: IconData.swift'teki SVG çizim yollarını SwiftUI şekline çevirir.

struct IconShape: Shape, @unchecked Sendable {
    private let cgPath: CGPath

    init?(name: String) {
        guard let entry = iconLibrary.first(where: { $0.name == name }) else { return nil }
        cgPath = SVGPath.parse(entry.path)
    }

    func path(in rect: CGRect) -> Path {
        // Kaynak 256×256; dikdörtgene sığdır
        let s = min(rect.width, rect.height) / 256
        var t = CGAffineTransform(translationX: rect.minX + (rect.width - 256 * s) / 2, y: rect.minY + (rect.height - 256 * s) / 2).scaledBy(x: s, y: s)
        return Path(cgPath.copy(using: &t) ?? cgPath)
    }
}

/// SVG "d" söz dizimini (M L H V C S Q T A Z, büyük ve küçük harf) CGPath'e çevirir.
enum SVGPath {
    static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = Tokenizer(d)
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?, lastQuad: CGPoint?
        var command: Character = "M"

        while let next = tokens.peekCommand() ?? (tokens.hasNumber ? command : nil) {
            if tokens.peekCommand() != nil { tokens.skipCommand() }
            command = next
            let rel = command.isLowercase
            func pt() -> CGPoint {
                let x = tokens.number(), y = tokens.number()
                return rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased().first! {
            case "M":
                current = pt(); start = current; path.move(to: current)
                command = rel ? "l" : "L"   // M'den sonraki sayılar çizgi sayılır
                lastControl = nil; lastQuad = nil
            case "L":
                current = pt(); path.addLine(to: current); lastControl = nil; lastQuad = nil
            case "H":
                let x = tokens.number(); current.x = rel ? current.x + x : x; path.addLine(to: current); lastControl = nil; lastQuad = nil
            case "V":
                let y = tokens.number(); current.y = rel ? current.y + y : y; path.addLine(to: current); lastControl = nil; lastQuad = nil
            case "C":
                let c1 = pt(), c2 = pt(), p = pt()
                path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = pt(), p = pt()
                path.addCurve(to: p, control1: c1, control2: c2); current = p; lastControl = c2; lastQuad = nil
            case "Q":
                let c = pt(), p = pt()
                path.addQuadCurve(to: p, control: c); current = p; lastQuad = c; lastControl = nil
            case "T":
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let p = pt()
                path.addQuadCurve(to: p, control: c); current = p; lastQuad = c; lastControl = nil
            case "A":
                let rx = tokens.number(), ry = tokens.number(), rot = tokens.number()
                let large = tokens.flag(), sweep = tokens.flag()
                let p = pt()
                addArc(path, from: current, to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                current = p; lastControl = nil; lastQuad = nil
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil; lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    /// SVG yay parametrelerinden merkezli yaya, oradan kübik eğrilere.
    private static func addArc(_ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                               rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var t = theta1
        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP, y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
        }
        func deriv(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosP - ry * cos(a) * sinP, y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
        }
        for _ in 0..<segments {
            let a0 = t, a1 = t + step
            let s = point(a0), e = point(a1), d0 = deriv(a0), d1 = deriv(a1)
            path.addCurve(to: e, control1: CGPoint(x: s.x + k * d0.x, y: s.y + k * d0.y), control2: CGPoint(x: e.x - k * d1.x, y: e.y - k * d1.y))
            t = a1
        }
    }

    /// Sayıları "1.5.5", "-2-3", "1e-3" gibi bitişik yazımlarla birlikte okur; yay bayrakları tek hanedir.
    private struct Tokenizer {
        let chars: [Character]
        var i = 0
        init(_ s: String) { chars = Array(s) }

        mutating func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        }
        mutating func peekCommand() -> Character? {
            skipSeparators()
            guard i < chars.count, chars[i].isLetter, chars[i] != "e", chars[i] != "E" else { return nil }
            return chars[i]
        }
        mutating func skipCommand() { i += 1 }
        var hasNumber: Bool {
            var j = i
            while j < chars.count, chars[j] == " " || chars[j] == "," { j += 1 }
            return j < chars.count && (chars[j].isNumber || chars[j] == "-" || chars[j] == "+" || chars[j] == ".")
        }
        mutating func flag() -> Bool {
            skipSeparators()
            guard i < chars.count else { return false }
            let f = chars[i] == "1"; i += 1
            return f
        }
        mutating func number() -> CGFloat {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            var seenDot = false, seenExp = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { s.append(c) }
                else if c == "." && !seenDot && !seenExp { seenDot = true; s.append(c) }
                else if (c == "e" || c == "E") && !seenExp {
                    seenExp = true; s.append(c)
                    if i + 1 < chars.count, chars[i + 1] == "-" || chars[i + 1] == "+" { i += 1; s.append(chars[i]) }
                } else { break }
                i += 1
            }
            return CGFloat(Double(s) ?? 0)
        }
    }
}
