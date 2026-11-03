import SwiftUI

// Состояние частиц пыли: «домашняя» позиция и текущая позиция.
final class Dust {
    struct Particle { var hx, hy, x, y: CGFloat }
    var items: [Particle] = []
    var size: CGSize = .zero

    func reset(_ s: CGSize, count: Int) {
        size = s
        items = (0..<count).map { _ in
            let hx = CGFloat.random(in: 0...s.width)
            let hy = CGFloat.random(in: 0...s.height)
            return Particle(hx: hx, hy: hy, x: hx, y: hy)
        }
    }
}

// Ближайшая точка отрезка a–b к точке p.
func nearest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
    let dx = b.x - a.x, dy = b.y - a.y
    let l = dx * dx + dy * dy
    let t = l == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l))
    return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
}

struct DustFaceView: View {
    @State private var dust = Dust()
    @State private var touch: CGPoint? = nil
    @Environment(\.isLuminanceReduced) private var dim   // Always-On режим

    var body: some View {
        TimelineView(.animation(minimumInterval: dim ? 60 : 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                draw(&ctx, size: size, date: tl.date)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { touch = $0.location }
                .onEnded { _ in touch = nil }
        )
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, date: Date) {
        if dust.size != size { dust.reset(size, count: 450) }

        let comps = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let sc = CGFloat(comps.second ?? 0) + CGFloat(comps.nanosecond ?? 0) / 1e9
        let mn = CGFloat(comps.minute ?? 0) + sc / 60
        let hr = CGFloat((comps.hour ?? 0) % 12) + mn / 60
        let tau = CGFloat.pi * 2
        let ang: [CGFloat] = [hr / 12 * tau, mn / 60 * tau, sc / 60 * tau]
        let len: [CGFloat] = [0.5, 0.82, 0.92]

        let S = min(size.width, size.height) / 2
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let handCount = dim ? 2 : 3

        var segs: [(CGPoint, CGPoint)] = []
        for i in 0..<3 {
            let a = ang[i]
            let tip = CGPoint(x: c.x + sin(a) * S * len[i], y: c.y - cos(a) * S * len[i])
            let tail = CGPoint(x: c.x - sin(a) * S * 0.1, y: c.y + cos(a) * S * 0.1)
            segs.append((tail, tip))
        }
        var sources = Array(segs.prefix(handCount))
        if let t = touch { sources.append((t, t)) }

        // Пыль: стрелки работают как магниты и отталкивают частицы.
        if !dim {
            let R = S * 0.32
            var dots = Path()
            for i in dust.items.indices {
                var p = dust.items[i]
                var ox: CGFloat = 0, oy: CGFloat = 0, f: CGFloat = 0
                for s in sources {
                    let n = nearest(CGPoint(x: p.hx, y: p.hy), s.0, s.1)
                    let dx = p.hx - n.x, dy = p.hy - n.y
                    let d = max(hypot(dx, dy), 0.001)
                    if d < R {
                        let q = 1 - d / R
                        let k = q * q * R * 0.9
                        ox += dx / d * k
                        oy += dy / d * k
                        f = max(f, q)
                    }
                }
                p.x += (p.hx + ox - p.x) * 0.14
                p.y += (p.hy + oy - p.y) * 0.14
                dust.items[i] = p

                let vx = p.x - p.hx, vy = p.y - p.hy
                let m = hypot(vx, vy)
                if m < 0.6 && f < 0.02 {
                    dots.addRect(CGRect(x: p.x, y: p.y, width: 1.2, height: 1.2))
                } else {
                    let L = 1.5 + min(m, S * 0.3) * 0.18 + f * 4
                    let ux = m > 0 ? vx / m : 0, uy = m > 0 ? vy / m : 0
                    var line = Path()
                    line.move(to: CGPoint(x: p.x - ux * L / 2, y: p.y - uy * L / 2))
                    line.addLine(to: CGPoint(x: p.x + ux * L / 2, y: p.y + uy * L / 2))
                    let al = 0.3 + 0.6 * min(1, m / (S * 0.15))
                    ctx.stroke(line,
                               with: .color(.white.opacity(Double(al))),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                }
            }
            ctx.fill(dots, with: .color(.white.opacity(0.28)))
        }

        // Цифры проступают, когда рядом стрелка.
        for i in 1...12 {
            let a = CGFloat(i) / 12 * tau
            let np = CGPoint(x: c.x + sin(a) * S * 0.8, y: c.y - cos(a) * S * 0.8)
            var dmin = CGFloat.greatestFiniteMagnitude
            for s in segs.prefix(handCount) {
                let q = nearest(np, s.0, s.1)
                dmin = min(dmin, hypot(np.x - q.x, np.y - q.y))
            }
            var t = max(0, min(1, 1 - (dmin - S * 0.04) / (S * 0.24)))
            t = t * t * (3 - 2 * t)
            if t < 0.01 { continue }

            var layer = ctx
            layer.opacity = Double(t)
            layer.addFilter(.shadow(color: .white.opacity(0.8), radius: S * 0.05 * t))
            let label = Text("\(i)")
                .font(.system(size: S * 0.2 * (0.85 + 0.15 * t), weight: .ultraLight))
                .foregroundColor(.white)
            layer.draw(label, at: np, anchor: .center)
        }

        // Стрелки.
        let widths: [CGFloat] = [S * 0.03, S * 0.02, S * 0.008]
        for i in 0..<handCount {
            var h = Path()
            h.move(to: segs[i].0)
            h.addLine(to: segs[i].1)
            ctx.stroke(h, with: .color(.white),
                       style: StrokeStyle(lineWidth: widths[i], lineCap: .round))
        }
    }
}
