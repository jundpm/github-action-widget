import AppKit
import SwiftUI

/// GitHub 마크 벡터 — 메뉴바 아이콘과 패널 헤더에서 쓴다. (앱 아이콘은 Resources/AppIcon.svg)
enum GitHubMark {
    static let viewBox: CGFloat = 24
    private static let d =
        "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 "
        + "0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 "
        + "17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 "
        + "1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 "
        + "1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 "
        + "3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 "
        + "3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 "
        + "0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 "
        + "12.297c0-6.627-5.373-12-12-12"
    private static let basePath: CGPath = SVGPath.parse(d)

    /// rect 안에 꽉 차게 배치한 경로. yUp=true 는 AppKit/CG(아래가 원점) 좌표계용.
    static func path(in rect: CGRect, yUp: Bool) -> CGPath {
        let s = min(rect.width, rect.height) / viewBox
        let ox = rect.minX + (rect.width - viewBox * s) / 2
        let oy = rect.minY + (rect.height - viewBox * s) / 2
        var t = yUp
            ? CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: ox, ty: oy + viewBox * s)
            : CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: ox, ty: oy)
        return basePath.copy(using: &t) ?? basePath
    }

    /// 메뉴바 아이콘. badge 가 없으면 템플릿 이미지(시스템이 밝기/어둡기 자동 처리).
    static func menuBarImage(badge: NSColor?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(path(in: rect.insetBy(dx: 1, dy: 1), yUp: true))
            ctx.setFillColor((badge == nil ? NSColor.black : NSColor.labelColor).cgColor)
            ctx.fillPath()
            if let badge {
                let r: CGFloat = 3.8
                let ring: CGFloat = 1.4
                let c = CGPoint(x: rect.maxX - r - 0.2, y: rect.minY + r + 0.2)
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: c.x - r - ring, y: c.y - r - ring,
                                           width: (r + ring) * 2, height: (r + ring) * 2))
                ctx.setBlendMode(.normal)
                ctx.setFillColor(badge.cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            return true
        }
        img.isTemplate = (badge == nil)
        return img
    }

    /// 확인용: 메뉴바 아이콘을 지정 배경 위에 크게 렌더.
    static func previewPNG(badge: NSColor?, background: NSColor, pixels: Int = 144) -> Data? {
        guard let rep = bitmap(pixels) else { return nil }
        draw(into: rep) { ctx, s in
            ctx.setFillColor(background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            menuBarImage(badge: badge).draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func bitmap(_ px: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    private static func draw(into rep: NSBitmapImageRep, _ body: (CGContext, CGFloat) -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.current = g
        body(g.cgContext, CGFloat(rep.pixelsWide))
    }
}

struct GitHubMarkShape: Shape {
    func path(in rect: CGRect) -> Path { Path(GitHubMark.path(in: rect, yUp: false)) }
}

/// SVG path `d` 의 M/L/H/V/C/S/Q/Z (대·소문자) 만 지원하는 작은 파서.
enum SVGPath {
    private enum Token { case cmd(Character), num(CGFloat) }

    private static func tokenize(_ d: String) -> [Token] {
        let pattern = "([MmLlHhVvCcSsQqZz])|([-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = d as NSString
        return re.matches(in: d, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            if m.range(at: 1).location != NSNotFound {
                return .cmd(Character(ns.substring(with: m.range(at: 1))))
            }
            if let v = Double(ns.substring(with: m.range(at: 2))) { return .num(CGFloat(v)) }
            return nil
        }
    }

    static func parse(_ d: String) -> CGPath {
        let tokens = tokenize(d)
        let path = CGMutablePath()
        var i = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl: CGPoint?
        var cmd: Character = "M"

        func hasNum() -> Bool {
            if i < tokens.count, case .num = tokens[i] { return true }
            return false
        }
        func n() -> CGFloat {
            guard i < tokens.count, case .num(let v) = tokens[i] else { return 0 }
            i += 1
            return v
        }
        func pt(_ rel: Bool) -> CGPoint {
            let x = n(), y = n()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            if case .cmd(let c) = tokens[i] {
                cmd = c
                i += 1
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    cur = start
                    lastCtrl = nil
                    continue
                }
            }
            guard hasNum() else { continue }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                let p = pt(rel)
                path.move(to: p)
                cur = p
                start = p
                lastCtrl = nil
                cmd = rel ? "l" : "L"
            case "L", "l":
                let p = pt(rel)
                path.addLine(to: p)
                cur = p
                lastCtrl = nil
            case "H", "h":
                let x = n()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastCtrl = nil
            case "V", "v":
                let y = n()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastCtrl = nil
            case "C", "c":
                let c1 = pt(rel), c2 = pt(rel), p = pt(rel)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p
                lastCtrl = c2
            case "S", "s":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = pt(rel), p = pt(rel)
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p
                lastCtrl = c2
            case "Q", "q":
                let c1 = pt(rel), p = pt(rel)
                path.addQuadCurve(to: p, control: c1)
                cur = p
                lastCtrl = nil
            default:
                i += 1
            }
        }
        return path
    }
}
