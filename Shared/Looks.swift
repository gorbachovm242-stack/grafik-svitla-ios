// Пʼять виглядів: будинок, плитки, гірлянда, батарея, кільце. Кожна клітинка, вікно чи лампочка — одна година;
// частину години зафарбовано точно за графіком. Розміри в точках екрана, пропорції ті самі, що в looks.tsx.
import SwiftUI
import SvitloCore

let hourGutter: CGFloat = 16 // місце для підписів годин ліворуч

/// Розміри малюнка для кожного місця, як PICTURES у looks.tsx.
enum Pictures {
    static let medium: [String: CGSize] = [
        "house": CGSize(width: 84, height: 136), "tiles": CGSize(width: 146, height: 110),
        "garland": CGSize(width: 150, height: 96), "battery": CGSize(width: 140, height: 76),
    ]
    static let large: [String: CGSize] = [
        "house": CGSize(width: 96, height: 140), "tiles": CGSize(width: 146, height: 110), "garland": CGSize(width: 146, height: 100),
    ]
    static let lock: [String: CGSize] = [
        "house": CGSize(width: 44, height: 68), "tiles": CGSize(width: 58, height: 52), "battery": CGSize(width: 52, height: 36),
    ]
    // Зі стовпчиком значків малюнки менші, щоб рядкам з годинами лишилося місце.
    static let mediumRail: [String: CGSize] = [
        "house": CGSize(width: 80, height: 132), "tiles": CGSize(width: 104, height: 80),
        "garland": CGSize(width: 108, height: 72), "battery": CGSize(width: 104, height: 58),
    ]
    static let largeRail: [String: CGSize] = [
        "house": CGSize(width: 92, height: 134), "tiles": CGSize(width: 126, height: 96), "garland": CGSize(width: 126, height: 86),
    ]
}

/// Малювання годин: заливка клітинки (частини години стоять поруч без накладання) і рамка «зараз».
enum Draw {
    static func hasLight(_ parts: [Part]) -> Bool { parts.contains { $0.st == .on } }

    /// Різкі переходи всередині години: кожна частина своїм кольором, зліва направо.
    static func partsShading(_ parts: [Part], _ paint: Theme.Paint, _ rect: CGRect) -> GraphicsContext.Shading {
        if parts.count == 1 { return .color(paint.cell(parts[0].st).color) }
        var stops: [Gradient.Stop] = []
        for part in parts {
            let from = CGFloat(part.from % 60) / 60
            let to = from + CGFloat(part.to - part.from) / 60
            let color = paint.cell(part.st).color
            stops.append(Gradient.Stop(color: color, location: from))
            stops.append(Gradient.Stop(color: color, location: to))
        }
        return .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        )
    }

    static func cellShading(_ parts: [Part], _ paint: Theme.Paint, _ rect: CGRect, vertical: Bool) -> GraphicsContext.Shading {
        if parts.count == 1 && parts[0].st == .on && !paint.lock {
            return .linearGradient(
                paint.lit.gradient,
                startPoint: vertical ? CGPoint(x: rect.midX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.minY),
                endPoint: vertical ? CGPoint(x: rect.midX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.maxY)
            )
        }
        return partsShading(parts, paint, rect)
    }

    static func cell(_ ctx: inout GraphicsContext, _ rect: CGRect, radius: CGFloat, _ shading: GraphicsContext.Shading, glow: RGBA? = nil) {
        let path = Path(roundedRect: rect, cornerRadius: max(0, min(radius, min(rect.width, rect.height) / 2)))
        if let glow = glow {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: glow.color, radius: 2.5))
                layer.fill(path, with: shading)
            }
        } else {
            ctx.fill(path, with: shading)
        }
    }

    static func mark(_ ctx: inout GraphicsContext, _ rect: CGRect, radius: CGFloat, _ color: RGBA) {
        let around = rect.insetBy(dx: -1.2, dy: -1.2)
        ctx.stroke(Path(roundedRect: around, cornerRadius: radius + 1), with: .color(color.color), lineWidth: 1.6)
    }

    static func hourLabel(_ ctx: inout GraphicsContext, _ hour: Int, _ rect: CGRect, _ color: RGBA) {
        let text = Text("\(hour)").font(.system(size: 9, weight: .medium, design: .default)).foregroundColor(color.color)
        ctx.draw(text, at: CGPoint(x: hourGutter - 4, y: rect.midY), anchor: .trailing)
    }
}

// MARK: - Будинок: шість поверхів по чотири вікна, день читається зверху вниз, як текст

struct HouseLook: View {
    let runs: [Run]
    let nowMin: Int?
    let paint: Theme.Paint

    var body: some View {
        Canvas { ctx, size in
            let width = size.width
            let height = size.height
            let gutter: CGFloat = paint.label != nil ? hourGutter : 0
            let stair: CGFloat = paint.wall != nil ? height * 0.05 : 0
            let x = gutter
            let y = stair
            let w = width - gutter
            let h = height - stair
            if let wall = paint.wall {
                if let roof = paint.roof {
                    Draw.cell(&ctx, CGRect(x: x + w * 0.2, y: 0, width: w * 0.26, height: stair * 2), radius: 2, .color(roof.color))
                }
                Draw.cell(&ctx, CGRect(x: x, y: y, width: w, height: h), radius: 5,
                          .linearGradient(wall.gradient, startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + h)))
            } else {
                let frame = CGRect(x: x + 0.6, y: y + 0.6, width: w - 1.2, height: h - 1.2)
                ctx.stroke(Path(roundedRect: frame, cornerRadius: 4), with: .color(paint.line.color), lineWidth: 1.2)
            }
            let padX = w * 0.09
            let padY = h * 0.055
            let gapX = w * 0.045
            let cellW = (w - 2 * padX - 3 * gapX) / 4
            let cellH = (h - 2 * padY) / (6 + 5 * 0.45)
            let radius = cellW * 0.2
            let current = Logic.currentHour(nowMin)
            for hour in 0..<24 {
                let col = CGFloat(hour % 4)
                let row = CGFloat(hour / 4)
                let box = CGRect(x: x + padX + col * (cellW + gapX), y: y + padY + row * cellH * 1.45, width: cellW, height: cellH)
                let parts = Logic.hourParts(runs, hour)
                let glow = paint.glow != nil && Draw.hasLight(parts) ? paint.glow : nil
                Draw.cell(&ctx, box, radius: radius, Draw.cellShading(parts, paint, box, vertical: true), glow: glow)
                if hour == current { Draw.mark(&ctx, box, radius: radius, paint.mark) }
                if let label = paint.label, hour % 4 == 0 { Draw.hourLabel(&ctx, hour, box, label) }
            }
        }
    }
}

// MARK: - Плитки: чотири рядки по шість годин; минулі години притишено, поточна в рамці

struct TilesLook: View {
    let runs: [Run]
    let nowMin: Int?
    let paint: Theme.Paint

    var body: some View {
        Canvas { ctx, size in
            let gutter: CGFloat = paint.label != nil ? hourGutter : 2 // рамка поточної години не повинна вийти за край
            let edge: CGFloat = 2
            let gap = max(2, size.width * 0.02)
            let cellW = (size.width - gutter - edge - 5 * gap) / 6
            let cellH = (size.height - 2 * edge - 3 * gap) / 4
            let radius = min(cellW, cellH) * 0.22
            let current = Logic.currentHour(nowMin)
            for hour in 0..<24 {
                let col = CGFloat(hour % 6)
                let row = CGFloat(hour / 6)
                let box = CGRect(x: gutter + col * (cellW + gap), y: edge + row * (cellH + gap), width: cellW, height: cellH)
                let parts = Logic.hourParts(runs, hour)
                let past = paint.fadePast && hour < current
                var layer = ctx
                if past { layer.opacity = 0.45 }
                Draw.cell(&layer, box, radius: radius, Draw.cellShading(parts, paint, box, vertical: false))
                if hour == current { Draw.mark(&ctx, box, radius: radius, paint.mark) }
                if let label = paint.label, hour % 6 == 0 { Draw.hourLabel(&ctx, hour, box, label) }
            }
        }
    }
}

// MARK: - Гірлянда: два дроти по 12 лампочок, верхній від 0 до 12 години, нижній від 12 до 24

struct GarlandLook: View {
    let runs: [Run]
    let nowMin: Int?
    let paint: Theme.Paint

    var body: some View {
        Canvas { ctx, size in
            let width = size.width
            let height = size.height
            let spans: CGFloat = paint.glow != nil ? 2 : 1
            let rowHeight = height / 2
            let spanWidth = width / spans
            let sag = rowHeight * (spans == 2 ? 0.2 : 0.16)
            let radius = min((width / 12) * 0.36, rowHeight * 0.2)
            let margin = paint.glow != nil ? radius * 1.75 : radius + 2.5 // ореол і рамка не повинні вийти за край
            let step = (width - 2 * margin) / 11
            let current = Logic.currentHour(nowMin)
            for row in 0..<2 {
                let top = CGFloat(row) * rowHeight + 1
                var wire = Path()
                wire.move(to: CGPoint(x: 0, y: top))
                for span in 0..<Int(spans) {
                    wire.addQuadCurve(
                        to: CGPoint(x: CGFloat(span + 1) * spanWidth, y: top),
                        control: CGPoint(x: (CGFloat(span) + 0.5) * spanWidth, y: top + 2 * sag)
                    )
                }
                ctx.stroke(wire, with: .color(paint.wire.color), lineWidth: 1)
                for i in 0..<12 {
                    let hour = row * 12 + i
                    let x = margin + CGFloat(i) * step
                    let along = x.truncatingRemainder(dividingBy: spanWidth) / spanWidth
                    let y = top + 4 * sag * along * (1 - along) + radius + 1
                    let parts = Logic.hourParts(runs, hour)
                    if let glow = paint.glow, Draw.hasLight(parts) {
                        let g = radius * 1.75
                        ctx.fill(Path(ellipseIn: CGRect(x: x - g, y: y - g, width: g * 2, height: g * 2)), with: .color(glow.opacity(0.3).color))
                    }
                    let bulb = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    let lit = parts.count == 1 && parts[0].st == .on && !paint.lock
                    let shading: GraphicsContext.Shading = lit
                        ? .radialGradient(paint.lit.gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius)
                        : Draw.partsShading(parts, paint, bulb)
                    ctx.fill(Path(ellipseIn: bulb), with: shading)
                    if hour == current {
                        let around = radius + 1.6
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: x - around, y: y - around, width: around * 2, height: around * 2)),
                            with: .color(paint.mark.color), lineWidth: 1.4
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Батарея: зі світлом розряджається до вимкнення, без нього заряджається до ввімкнення

struct BatteryLook: View {
    let glance: Glance
    let paint: Theme.Paint

    var body: some View {
        Canvas { ctx, size in
            let width = size.width
            let height = size.height
            let line = max(1.5, height * 0.045)
            let nub = max(2.5, width * 0.045)
            let body = CGRect(x: line / 2, y: line / 2, width: width - nub - line * 1.6, height: height - line)
            let radius = body.height * 0.25
            let inset = line / 2 + max(2, height * 0.07)
            let inner = body.insetBy(dx: inset, dy: inset)
            let innerRadius = max(2, radius - inset * 0.6)
            let level = CGFloat(Logic.batteryLevel(glance))
            let charging = Logic.isCharging(glance)
            ctx.stroke(Path(roundedRect: body, cornerRadius: radius), with: .color(paint.line.color), lineWidth: line)
            Draw.cell(&ctx, CGRect(x: width - nub, y: height * 0.3, width: nub, height: height * 0.4), radius: nub / 2, .color(paint.line.color))
            if level > 0 {
                let fillWidth = min(inner.width, max(innerRadius * 2, inner.width * level))
                let colors = charging ? paint.charge : paint.batteryOn
                let rect = CGRect(x: inner.minX, y: inner.minY, width: fillWidth, height: inner.height)
                Draw.cell(&ctx, rect, radius: innerRadius,
                          .linearGradient(colors.gradient, startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            }
            if charging {
                let boltH = inner.height * 0.6
                let box = CGRect(x: inner.minX, y: inner.minY + (inner.height - boltH) / 2, width: inner.width - inner.height * 0.12, height: boltH)
                ctx.fill(boltPath(box), with: .color(paint.line.color))
            }
        }
    }

    /// Блискавка тієї ж форми, що й у версії для Scriptable.
    func boltPath(_ box: CGRect) -> Path {
        let unit = box.height / 20
        let left = box.minX + box.width - 11 * unit
        let shape: [(CGFloat, CGFloat)] = [(6, 0), (0, 11), (5, 11), (3, 20), (11, 8), (6, 8), (8, 0)]
        var path = Path()
        path.addLines(shape.map { CGPoint(x: left + $0.0 * unit, y: box.minY + $0.1 * unit) })
        path.closeSubpath()
        return path
    }
}

// MARK: - Кільце доби: північ угорі, час іде за годинниковою стрілкою, крапка показує, де ви зараз

struct RingLook: View {
    let runs: [Run]
    let nowMin: Int?
    let lineWidth: CGFloat
    let colors: Theme.RingColors
    var hoursColor: RGBA? = nil

    static func point(_ size: CGFloat, _ radius: CGFloat, _ minutes: Int) -> CGPoint {
        let angle = Double(minutes) / 1440 * 2 * Double.pi
        return CGPoint(x: size / 2 + radius * CGFloat(sin(angle)), y: size / 2 - radius * CGFloat(cos(angle)))
    }

    var body: some View {
        Canvas { ctx, canvas in
            let size = min(canvas.width, canvas.height)
            let radius = size / 2 - lineWidth / 2 - 3
            let circumference = 2 * CGFloat.pi * radius
            let center = CGPoint(x: size / 2, y: size / 2)
            let list = runs.isEmpty ? [Run(s: 0, e: 1440, st: .unknown)] : runs
            let whole = list.count < 2
            for run in list {
                let color = colors.cell(run.st)
                // Напівпрозорі кінці не заокруглюємо: накладання дало б темні плями.
                let rounded = !whole && color.isOpaque
                let wanted: CGFloat = whole ? 0 : (rounded ? lineWidth / 2 + 1 : 1) / circumference
                let length = CGFloat(run.e - run.s) / 1440
                let inset = min(wanted, max(length / 2 - 0.0003, 0))
                let from = CGFloat(run.s) / 1440 + inset
                let to = CGFloat(run.e) / 1440 - inset
                if to <= from { continue }
                var arc = Path()
                // У SwiftUI вісь y іде вниз, тож clockwise: false малює за годинниковою стрілкою.
                arc.addArc(center: center, radius: radius, startAngle: .degrees(-90 + 360 * from), endAngle: .degrees(-90 + 360 * to), clockwise: false)
                ctx.stroke(arc, with: .color(color.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: rounded ? .round : .butt))
            }
            if let nowMin = nowMin {
                let p = RingLook.point(size, radius, nowMin)
                let outer = lineWidth + 4
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - outer / 2, y: p.y - outer / 2, width: outer, height: outer)), with: .color(colors.edge.color))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - lineWidth / 2, y: p.y - lineWidth / 2, width: lineWidth, height: lineWidth)), with: .color(colors.now.color))
            }
            // Кільце показує 24 години, а без підписів його читають як звичайний 12-годинний циферблат.
            if let hoursColor = hoursColor {
                let font = max(8, size * 0.065)
                let inner = radius - lineWidth / 2 - font * 0.9
                for (minutes, label) in [(0, "0"), (360, "6"), (720, "12"), (1080, "18")] {
                    let p = RingLook.point(size, inner, minutes)
                    ctx.draw(Text(label).font(.system(size: font, weight: .medium, design: .default)).foregroundColor(hoursColor.color), at: p, anchor: .center)
                }
            }
        }
    }
}

/// Будинок, плитки чи гірлянда за назвою вигляду.
struct DayLook: View {
    let look: String
    let runs: [Run]
    let nowMin: Int?
    let paint: Theme.Paint

    var body: some View {
        switch look {
        case "house": HouseLook(runs: runs, nowMin: nowMin, paint: paint)
        case "tiles": TilesLook(runs: runs, nowMin: nowMin, paint: paint)
        default: GarlandLook(runs: runs, nowMin: nowMin, paint: paint)
        }
    }
}
