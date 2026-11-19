// Розкладки віджета для всіх розмірів (порт widget_view.tsx). Таймер іде сам, навіть якщо iOS довго не оновлює віджет.
// Коли в застосунку ввімкнено тривогу, праворуч стовпчик значків модулів (світло, тривога) на мʼякій доріжці
// й під ним кружечки сторінок, як у «Маяку» для Android: дотик до значка показує сторінку модуля,
// дотик до самої сторінки відкриває застосунок. Без тривоги віджет лише про світло.
import SwiftUI
import WidgetKit
import SvitloCore

/// Що показати у віджеті в один момент таймлайну.
struct WidgetModel {
    var glance: Glance
    var now: Now
    var date: Date
    var family: WidgetFamily
    var size: CGSize
    var alert: AlertStatus? // nil: модуль тривоги вимкнено (стовпчика немає)
    var pages: [String]
    var page: String
    var pageKey: String
    /// Таймери стоять на моменті date (картинки віджетів у тестах), а не йдуть за справжнім годинником.
    var frozen = false

    /// Для таймерів: на якому моменті зупинитися (nil — живий таймер).
    var pauseAt: Date? { frozen ? date : nil }
}

/// Таймер, що рахує вгору від from: живий або зупинений на pauseAt.
func countUp(_ from: Date, pauseAt: Date?) -> Text {
    guard let pause = pauseAt else { return Text(from, style: .timer) }
    return Text(timerInterval: from...max(from, pause), pauseTime: pause, countsDown: false)
}

/// Усе, що потрібно розкладкам: модель, кольори й ширина сторінки без стовпчика.
struct Ctx {
    let m: WidgetModel
    let t: Tokens
    let contentW: CGFloat
    let alert: AlertStatus?
    let pages: [String]
    let page: String

    var view: Glance { m.glance }
    var now: Now { m.now }
    var date: Date { m.date }
    var width: CGFloat { m.size.width }
    var height: CGFloat { m.size.height }
    var rail: Bool { alert != nil }
}

let railSmall: CGFloat = 34
let railWide: CGFloat = 46

extension View {
    /// Розтягнути на все доступне місце (як frame «infinity» у Scripting).
    func expand(_ alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    func pad(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> some View {
        padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
    }
}

// MARK: - Елементи

/// Напис: «19:30 завтра» не розривається, довгий текст спершу зменшується до scale, а потім обрізається.
struct WLabel: View {
    let text: String
    var size: CGFloat
    var weight: Font.Weight = .regular
    var color: RGBA? = nil
    var lines: Int = 1
    var scale: CGFloat = 0.7
    var rounded = false
    var align: TextAlignment = .leading
    var fixed = false

    var body: some View {
        let base = Text(Logic.keepTogether(text))
            .font(.system(size: size, weight: weight, design: rounded ? .rounded : .default))
        Group {
            if let color = color {
                base.foregroundColor(color.color)
            } else {
                base
            }
        }
        .lineLimit(lines)
        .minimumScaleFactor(scale)
        .multilineTextAlignment(align)
        .truncationMode(.tail)
        .fixedSize(horizontal: fixed, vertical: false)
    }
}

/// Живий таймер до наступної зміни. Без рамки таймер у рядку забирає всю ширину, тож ширину задаємо.
struct TimerText: View {
    let c: Ctx
    let size: CGFloat
    var weight: Font.Weight = .regular
    var color: RGBA? = nil
    var align: TextAlignment = .leading
    var width: CGFloat? = nil

    var body: some View {
        let end = max(Logic.changeDate(c.view, c.now, c.date), c.date)
        let text = Text(timerInterval: c.date...end, pauseTime: c.m.pauseAt, countsDown: true)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .monospacedDigit()
        Group {
            if let color = color { text.foregroundColor(color.color) } else { text }
        }
        .multilineTextAlignment(align)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: width, alignment: align == .trailing ? .trailing : align == .center ? .center : .leading)
    }
}

/// Таймер тривоги рахує вгору від її початку.
struct AlertTimer: View {
    let s: AlertStatus
    let size: CGFloat
    let color: RGBA
    var pauseAt: Date? = nil

    var body: some View {
        countUp(Date(ms: s.since), pauseAt: pauseAt)
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(color.color)
            .lineLimit(1)
            .frame(width: (size * 0.62 * 8).rounded(), alignment: .leading)
    }
}

struct RefreshButton: View {
    let color: RGBA
    var size: CGFloat = 22

    var body: some View {
        Button(intent: RefreshIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size * 0.52, weight: .semibold, design: .default))
                .foregroundColor(color.color)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Кружечок зі станом: заливка, обідок чи кільце (пунктир — немає даних).
struct Dot: View {
    let tok: IconTok
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(tok.fill.color)
            if let rim = tok.rim { Circle().strokeBorder(rim.color, lineWidth: 1.2) }
            if let ring = tok.ring {
                Circle().strokeBorder(ring.color, style: StrokeStyle(lineWidth: 1.6, dash: tok.dashed ? [2, 1.6] : []))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Значок модуля: коло стану з відступом кольору фону, обідок чи кільце (пунктир — немає даних), знак, світіння.
struct StatusIcon: View {
    let icon: IconTok
    let glyph: String
    let size: CGFloat
    var halo: RGBA? = nil

    var body: some View {
        ZStack {
            if let halo = halo, !halo.isClear {
                Circle().fill(halo.color).frame(width: size + 4, height: size + 4)
            }
            Circle()
                .fill(icon.fill.color)
                .frame(width: size, height: size)
                .shadow(color: (icon.glow ?? .clear).color, radius: icon.glow == nil ? 0 : size * 0.2)
            if let rim = icon.rim {
                Circle().strokeBorder(rim.color, lineWidth: 1.5).frame(width: size, height: size)
            }
            if let ring = icon.ring {
                Circle()
                    .strokeBorder(ring.color, style: StrokeStyle(lineWidth: 2.5, dash: icon.dashed ? [size * 0.16, size * 0.12] : []))
                    .frame(width: size, height: size)
            }
            Image(systemName: glyph)
                .font(.system(size: (size * 0.46).rounded(), weight: .bold, design: .default))
                .foregroundColor(icon.glyph.color)
        }
        .frame(width: size + 4, height: size + 4)
    }
}

/// Датчик СвітлоБота: чи є світло насправді (бурштинова крапка — є, темна — немає, пунктир — датчик мовчить).
struct SensorDot: View {
    let c: Ctx
    var size: CGFloat = 9

    var body: some View {
        if let fact = c.view.fact {
            let tok = fact.kind == .on ? c.t.sensor.on : fact.kind == .off ? c.t.sensor.off : c.t.sensor.silent
            Dot(tok: tok, size: size)
        }
    }
}

/// Рядок датчика: крапка, слова, а без світла ще й живий таймер від вимкнення.
/// На екрані блокування iOS фарбує все сама, тож lock: без кольорів.
struct FactLine: View {
    let c: Ctx
    var compact = false
    var size: CGFloat = 11
    var lock = false

    var body: some View {
        if let fact = c.view.fact {
            let withTimer = !compact && fact.timerFrom != nil
            let short = fact.short.prefix(1).uppercased() + fact.short.dropFirst()
            let text = compact ? fact.short : withTimer ? short : fact.line + (fact.checked.map { " · \($0)" } ?? "")
            let color: RGBA? = lock ? nil : c.t.text
            HStack(spacing: 3) {
                if lock {
                    Image(systemName: fact.kind == .on || fact.kind == .off ? "circle.fill" : "circle.dashed")
                        .font(.system(size: size * 0.62, weight: .regular, design: .default))
                } else {
                    SensorDot(c: c, size: (size * 0.75).rounded())
                }
                WLabel(text: text, size: size, weight: .medium, color: color, scale: 0.75)
                if withTimer, let from = fact.timerFrom {
                    Group {
                        if let color = color {
                            countUp(Date(ms: from), pauseAt: c.m.pauseAt).foregroundColor(color.color)
                        } else {
                            countUp(Date(ms: from), pauseAt: c.m.pauseAt)
                        }
                    }
                    .font(.system(size: size, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: size * 4.6, alignment: .leading)
                }
            }
        }
    }
}

enum WidgetText {
    /// Великий час: зі світлом колір тексту, без нього той самий бурштиновий, що й блискавка.
    static func timeColor(_ c: Ctx) -> RGBA { c.view.kind == .on ? c.t.text : c.t.titleBolt }

    /// Коли адрес дві, замість «черга 3.2» назва адреси («Батьки»): так видно, який це віджет.
    static func footerText(_ view: Glance) -> String {
        view.noticeShort ?? view.place ?? "черга \(view.group ?? "—")"
    }

    /// Ширина живого таймера: «59:59», «3:53:41» чи «12:00:00» (моноширинна цифра близько 0,62 кегля).
    static func timerWidth(_ c: Ctx, _ size: CGFloat) -> CGFloat {
        let left = (c.view.changeMin ?? c.now.min) - c.now.min
        let chars: CGFloat = left >= 600 ? 8 : left >= 60 ? 7 : 5
        return (size * 0.62 * chars).rounded(.up) + 2
    }

    /// Чи показує заголовок стану живий таймер (рядок, у якому стоїть напис тривоги).
    static func statusTimer(_ c: Ctx, _ withTimer: Bool = true) -> Bool {
        c.view.notice == nil && withTimer && Logic.hasTimer(c.view, c.now)
    }

    /// Напис біля значка тривоги на сторінці світла: довгий («Тривога з 10:40»), якщо поруч із таймером вистачає місця,
    /// інакше короткий («з 10:40»). Ширину рахуємо з запасом (жирний 12 pt, близько 0,62 кегля на літеру).
    static func pillText(_ c: Ctx, _ column: CGFloat, _ withTimer: Bool = true) -> String? {
        guard let s = c.alert, let long = AlertLogic.alertPill(s, short: false) else { return nil }
        let room = column - (statusTimer(c, withTimer) ? timerWidth(c, 13) + 6 : 0)
        let width = CGFloat(long.count) * 12 * 0.62 + 18
        return width <= room ? long : AlertLogic.alertPill(s, short: true)
    }
}

struct Footer: View {
    let c: Ctx
    var size: CGFloat = 11
    var body: some View {
        WLabel(text: WidgetText.footerText(c.view), size: size, color: c.view.noticeShort != nil ? c.t.warn : c.t.muted)
    }
}

struct Checked: View {
    let c: Ctx
    var body: some View {
        if let checked = c.view.checked {
            WLabel(text: "перевірено \(Logic.hm(checked))", size: 10, color: c.t.muted)
        } else {
            Spacer()
        }
    }
}

struct Pill: View {
    let c: Ctx
    let text: String
    var body: some View {
        let s = c.alert ?? AlertStatus()
        let tok = s.kind == .setup ? c.t.icons.stale : Theme.alertIcon(c.t, s.kind)
        WLabel(text: text, size: 12, weight: .bold, color: tok.pillText ?? tok.glyph, fixed: true)
            .pad(3, 9, 3, 9)
            .background(Capsule().fill((tok.pillBg ?? tok.fill).color))
    }
}

/// Заголовок стану світла, подробиці й таймер. pill: напис тривоги в рядку таймера (праворуч, біля стовпчика).
struct StatusBlock: View {
    let c: Ctx
    var withTimer = true
    var pill: String? = nil

    var body: some View {
        let view = c.view
        let timer = WidgetText.statusTimer(c, withTimer)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: Theme.statusSymbol(view.kind))
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(Theme.statusColor(view.kind, c.t).color)
                WLabel(text: view.title, size: 18, weight: .bold, color: c.t.text)
            }
            WLabel(text: view.sub, size: 13, weight: .medium, color: c.t.text, lines: 2)
            if let notice = view.notice {
                WLabel(text: notice, size: 12, weight: .semibold, color: c.t.warn)
            }
            if timer || pill != nil {
                HStack(spacing: 4) {
                    if timer {
                        TimerText(c: c, size: 13, weight: .medium, color: c.t.timer, width: WidgetText.timerWidth(c, 13))
                    }
                    Spacer(minLength: 2)
                    if let pill = pill { Pill(c: c, text: pill) }
                }
            }
        }
    }
}

struct Centered<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
    }
}

/// Батарея з написом усередині, центрованим у частині ліворуч від блискавки.
struct BatteryDial: View {
    let c: Ctx
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let charging = Logic.isCharging(c.view)
        let words = c.view.changeMin == nil ? Logic.quietWords(c.view) : c.view.short
        ZStack {
            BatteryLook(glance: c.view, paint: Theme.homePaint("battery", c.t))
            Group {
                if Logic.hasTimer(c.view, c.now) {
                    TimerText(c: c, size: (height * 0.33).rounded(), weight: .bold, color: c.t.text, align: .center)
                } else {
                    WLabel(text: words, size: 14, weight: .semibold, color: c.t.text, lines: 2, align: .center)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, charging ? (height * 0.62).rounded() : 14)
        }
        .frame(width: width, height: height)
    }
}

/// Написи всередині кільця: дія, час і таймер або короткі слова. below: рядок про завтра під ними.
struct DialText: View {
    let c: Ctx
    let unit: CGFloat
    let withTimer: Bool
    var below: String? = nil

    var body: some View {
        let view = c.view
        let timer = withTimer && Logic.hasTimer(view, c.now)
        VStack(spacing: view.changeMin == nil ? 2 : 0) {
            if let place = view.place, view.noticeShort != nil || timer {
                WLabel(text: place, size: 11 * unit, weight: .semibold, color: c.t.brand, align: .center)
            }
            if view.changeMin == nil {
                WLabel(text: Logic.quietWords(view), size: 13 * unit, weight: .semibold, color: c.t.text, lines: 2, align: .center)
            } else {
                WLabel(text: Logic.changeVerb(view), size: 11 * unit, weight: .medium, color: c.t.muted, align: .center)
                WLabel(text: view.short, size: 26 * unit, weight: .bold, color: WidgetText.timeColor(c), rounded: true)
            }
            if let notice = view.noticeShort {
                WLabel(text: notice, size: 11 * unit, weight: .medium, color: c.t.warn, align: .center)
            } else if timer {
                TimerText(c: c, size: 12 * unit, color: c.t.timer, align: .center)
            } else {
                WLabel(text: view.place ?? "черга \(view.group ?? "—")", size: 11 * unit, weight: .medium, color: c.t.muted, align: .center)
            }
            if let below = below {
                WLabel(text: below, size: 9.5 * unit, weight: .semibold, color: c.t.brand, align: .center)
            }
        }
    }
}

struct TomorrowDialText: View {
    let c: Ctx
    let unit: CGFloat

    var body: some View {
        let windows = c.view.tomorrowWindows ?? []
        if c.view.tomorrowRuns == nil || windows.isEmpty {
            WLabel(text: c.view.tomorrowRuns != nil ? "Без\nвідключень" : "Ще\nнемає", size: 13 * unit, weight: .semibold,
                   color: c.t.text, lines: 2, align: .center)
        } else {
            VStack(spacing: 0) {
                WLabel(text: "перше", size: 11 * unit, weight: .medium, color: c.t.muted)
                WLabel(text: Logic.hm(windows[0].s), size: 25 * unit, weight: .bold, color: c.t.text, rounded: true)
            }
        }
    }
}

struct RingDial<Center: View>: View {
    let c: Ctx
    let size: CGFloat
    let runs: [Run]
    let nowMin: Int?
    let center: Center

    init(c: Ctx, size: CGFloat, runs: [Run], nowMin: Int?, @ViewBuilder center: () -> Center) {
        self.c = c
        self.size = size
        self.runs = runs
        self.nowMin = nowMin
        self.center = center()
    }

    var body: some View {
        ZStack {
            RingLook(runs: runs, nowMin: nowMin, lineWidth: 9, colors: Theme.ringColors(c.t), hoursColor: c.t.muted)
                .frame(width: size, height: size)
            center
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Стовпчик значків

/// Кружечки сторінок: відкрита — капсула, інші — кільця.
struct PageDots: View {
    let c: Ctx
    let small: Bool

    var body: some View {
        let d: CGFloat = small ? 5 : 6
        HStack(spacing: small ? 3 : 4) {
            ForEach(c.pages, id: \.self) { p in
                if p == c.page {
                    Capsule().fill(c.t.dotOn.color).frame(width: small ? 10 : 13, height: d)
                } else {
                    Circle().strokeBorder(c.t.dotOff.color, lineWidth: 1.5).frame(width: d, height: d)
                }
            }
        }
    }
}

/// Стовпчик: значки на доріжці, смужка біля значка відкритої сторінки, унизу кружечки. У малому віджеті «↻»
/// теж тут, над кружечками: на сторінці він стояв би впритул до значків і натискався б замість них.
/// Дотик до значка іншої сторінки показує її; значок відкритої сторінки не кнопка, тож відкриває застосунок.
struct Rail: View {
    let c: Ctx
    let small: Bool

    struct Item: Identifiable {
        let page: String
        let icon: IconTok
        let glyph: String
        var id: String { page }
    }

    var items: [Item] {
        let s = c.alert ?? AlertStatus()
        return [
            Item(page: AlertLogic.light, icon: Theme.lightIcon(c.t, c.view.kind), glyph: Theme.lightGlyph(c.view.kind)),
            Item(page: AlertLogic.alert, icon: Theme.alertIcon(c.t, s.kind), glyph: Theme.alertGlyph(s.kind)),
        ]
    }

    var body: some View {
        let size: CGFloat = small ? 24 : 32
        let cell = size + 4
        let pitch: CGFloat = small ? 30 : 39
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                VStack(spacing: pitch - cell) {
                    ForEach(items) { item in
                        let icon = StatusIcon(icon: item.icon, glyph: item.glyph, size: size, halo: c.t.halo)
                        if item.page == c.page {
                            icon
                        } else {
                            Button(intent: PageIntent(page: item.page, key: c.m.pageKey)) { icon }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(small ? 0 : 1)
                .background(Capsule().fill(c.t.track.color))
                VStack(spacing: pitch - cell) {
                    ForEach(items) { item in
                        ZStack {
                            if item.page == c.page {
                                Capsule().fill(c.t.marker.color).frame(width: 3, height: small ? 14 : 18)
                            }
                        }
                        .frame(width: 3, height: cell)
                    }
                }
                .padding(.vertical, small ? 0 : 1)
            }
            Spacer(minLength: 0)
            if small {
                RefreshButton(color: c.t.refresh, size: 20)
                Spacer(minLength: 4).frame(maxHeight: 4)
            }
            PageDots(c: c, small: small)
        }
        .frame(width: small ? railSmall : railWide)
        .frame(maxHeight: .infinity)
        .padding(.top, small ? 7 : 6)
        .padding(.bottom, small ? 9 : 11)
    }
}

// MARK: - Робочий екран: сторінка світла

/// Коли графіка немає, малюнку нічого показувати: лишаються слова.
struct TextOnly: View {
    let c: Ctx
    var small = false

    var body: some View {
        let pill = c.rail && !small ? WidgetText.pillText(c, c.contentW - 20) : nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                WLabel(text: Logic.captionText(c.view), size: 11, color: c.t.muted)
                Spacer(minLength: 0)
                if !c.rail { RefreshButton(color: c.t.refresh) }
            }
            StatusBlock(c: c, pill: pill)
            FactLine(c: c, size: 12)
            Spacer(minLength: 0)
            if c.rail && !small {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RefreshButton(color: c.t.refresh)
                }
            }
        }
        .pad(14, 14, 12, c.rail ? 4 : 12)
        .expand(.topLeading)
    }
}

/// Малий віджет: коли графік на завтра вже є, «завтра» і перше відключення над нижнім рядком.
struct TomorrowLines: View {
    let c: Ctx
    var size: CGFloat = 12

    var body: some View {
        if let first = Logic.tomorrowFirst(c.view) {
            VStack(alignment: .leading, spacing: 0) {
                WLabel(text: "завтра", size: size - 1, weight: .semibold, color: c.t.brand)
                WLabel(text: first, size: size, weight: .medium, color: c.t.text, scale: 0.6)
            }
        }
    }
}

struct ChangeColumn: View {
    let c: Ctx

    var body: some View {
        let view = c.view
        VStack(alignment: .leading, spacing: 0) {
            if view.changeMin == nil {
                VStack(alignment: .leading, spacing: 2) {
                    WLabel(text: view.title, size: 15, weight: .bold, color: c.t.text, lines: 2, scale: 0.8)
                    WLabel(text: view.sub, size: 12, weight: .medium, color: c.t.muted, lines: 3, scale: 0.8)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    WLabel(text: Logic.changeVerb(view), size: 13, weight: .medium, color: c.t.muted, lines: 2, scale: 0.75)
                    WLabel(text: view.short, size: 25, weight: .bold, color: WidgetText.timeColor(c), rounded: true)
                    if Logic.hasTimer(view, c.now) {
                        TimerText(c: c, size: 15, weight: .semibold, color: c.t.timer)
                    }
                }
            }
            Spacer(minLength: 3)
            TomorrowLines(c: c)
            HStack(spacing: 2) {
                if view.place != nil && view.fact != nil { Footer(c: c) }
                if view.fact != nil { SensorDot(c: c) } else { Footer(c: c) }
                Spacer(minLength: 0)
                if !c.rail { RefreshButton(color: c.t.refresh, size: 20) }
            }
            .padding(.top, Logic.hasTomorrow(view) ? 2 : 0)
        }
        .expand(.topLeading)
    }
}

struct SmallHouse: View {
    let c: Ctx

    var body: some View {
        // Будинок вузький, але колонці з часом потрібно щонайменше половину ширини.
        let height = min(136, c.height - 22, ((c.contentW * (c.rail ? 0.4 : 0.47)) / 0.545).rounded())
        HStack(spacing: c.rail ? 5 : 6) {
            HouseLook(runs: c.view.todayRuns, nowMin: c.view.nowMin, paint: Theme.homePaint("house", c.t))
                .frame(width: (height * 0.545).rounded(), height: height)
            ChangeColumn(c: c)
        }
        .pad(11, c.rail ? 7 : 8, 11, c.rail ? 2 : 8)
        .expand()
    }
}

/// Верхні два рядки малого віджета, коли малюнок займає нижню половину.
struct Headline: View {
    let c: Ctx

    var body: some View {
        let view = c.view
        if view.changeMin == nil {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    WLabel(text: view.title, size: c.rail ? 16 : 18, weight: .bold, color: c.t.text)
                    Spacer(minLength: 0)
                    SensorDot(c: c)
                    if !c.rail { RefreshButton(color: c.t.refresh, size: 20) }
                }
                WLabel(
                    text: view.noticeShort ?? (view.place.map { "\($0): \(view.sub)" } ?? view.sub),
                    size: 12, weight: .medium, color: view.noticeShort != nil ? c.t.warn : c.t.muted, lines: 2, scale: 0.8
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    WLabel(text: Logic.changeVerb(view), size: 13, weight: .medium, color: c.t.muted)
                    Spacer(minLength: 2)
                    Footer(c: c)
                    SensorDot(c: c)
                    if !c.rail { RefreshButton(color: c.t.refresh, size: 20) }
                }
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    WLabel(text: view.short, size: c.rail ? 25 : 29, weight: .bold, color: WidgetText.timeColor(c), rounded: true)
                    Spacer(minLength: 0)
                    if Logic.hasTimer(view, c.now) {
                        TimerText(c: c, size: c.rail ? 13 : 14, weight: .semibold, color: c.t.timer, align: .trailing, width: c.rail ? 54 : 62)
                    }
                }
            }
        }
    }
}

struct SmallDay: View {
    let c: Ctx
    let look: String

    var body: some View {
        let first = Logic.tomorrowFirst(c.view)
        let width = c.contentW - (c.rail ? 14 : 26)
        VStack(alignment: .leading, spacing: 0) {
            Headline(c: c)
            Spacer(minLength: 3)
            Centered {
                DayLook(look: look, runs: c.view.todayRuns, nowMin: c.view.nowMin, paint: Theme.homePaint(look, c.t))
                    .frame(width: width, height: (width * (first != nil ? 0.48 : 0.56)).rounded())
            }
            if let first = first {
                HStack(spacing: 4) {
                    WLabel(text: "завтра", size: 10, weight: .semibold, color: c.t.brand)
                    WLabel(text: first, size: 11, weight: .medium, color: c.t.text, scale: 0.6)
                }
                .padding(.top, 3)
            }
        }
        .pad(12, c.rail ? 10 : 13, 10, c.rail ? 4 : 13)
        .expand(.topLeading)
    }
}

struct SmallBattery: View {
    let c: Ctx

    var body: some View {
        let view = c.view
        let width = c.contentW - (c.rail ? 16 : 28)
        let first = Logic.tomorrowFirst(view)
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            BatteryDial(c: c, width: width, height: (width * (first != nil ? 0.5 : 0.54)).rounded())
            if view.changeMin != nil {
                WLabel(text: "\(Logic.changeVerb(view)) \(view.short)", size: c.rail ? 14 : 15, weight: .semibold, color: c.t.text)
            }
            if let first = first {
                WLabel(text: "завтра \(first)", size: 11, weight: .medium, color: c.t.brand, scale: 0.6)
            }
            HStack(spacing: 4) {
                if view.place != nil && view.fact != nil { Footer(c: c) }
                if view.fact != nil { FactLine(c: c, compact: true) } else { Footer(c: c) }
                if !c.rail { RefreshButton(color: c.t.refresh, size: 20) }
            }
            Spacer(minLength: 0)
        }
        .pad(0, 8, 0, c.rail ? 2 : 8)
        .expand()
    }
}

struct SmallRing: View {
    let c: Ctx

    var body: some View {
        let size = min(138, c.contentW - (c.rail ? 8 : 20), c.height - 14)
        let first = (c.view.tomorrowWindows ?? []).first.map { "завтра з \(Logic.hm($0.s))" }
        ZStack(alignment: .topTrailing) {
            RingDial(c: c, size: size, runs: c.view.todayRuns, nowMin: c.view.nowMin) {
                DialText(c: c, unit: size / 138, withTimer: true, below: first)
            }
            .expand()
            VStack(spacing: 2) {
                if !c.rail { RefreshButton(color: c.t.refresh, size: 24) }
                SensorDot(c: c)
            }
            .padding(.top, c.rail ? 6 : 0)
            .padding(.trailing, c.rail ? 2 : 0)
        }
        .expand()
    }
}

struct SmallLight: View {
    let c: Ctx
    let look: String

    var body: some View {
        if c.view.todayRuns.isEmpty {
            TextOnly(c: c, small: true)
        } else if look == "house" {
            SmallHouse(c: c)
        } else if look == "battery" {
            SmallBattery(c: c)
        } else if look == "ring" {
            SmallRing(c: c)
        } else {
            SmallDay(c: c, look: look)
        }
    }
}

/// Рядок дня: «Сьогодні  12:00–14:00, 18:00–20:30» — назва дня приглушеним жирним, години звичайним.
struct DayRow: View {
    let c: Ctx
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            WLabel(text: label, size: 11, weight: .bold, color: c.t.muted, fixed: true)
            WLabel(text: text, size: 13, weight: .medium, color: c.t.text, scale: 0.7)
        }
    }
}

/// Сьогодні й завтра: коли графік на завтра вже є — двома рядками; інакше заголовок і години сьогодні.
struct DayRows: View {
    let c: Ctx
    let room: CGFloat

    /// Чи вміститься рядок дня в колонку (з дозволеним зменшенням шрифту); ні — години коротко.
    static func fits(_ label: String, _ text: String, _ room: CGFloat) -> Bool {
        (CGFloat(label.count) * 11 * 0.6 + 5 + CGFloat(text.count) * 13 * 0.55) * 0.8 <= room
    }

    var body: some View {
        let view = c.view
        let today = view.place.map { "\($0) · сьогодні" } ?? "Сьогодні"
        if Logic.hasTomorrow(view) {
            let compact = !DayRows.fits(today, Logic.todayRow(view), room) || !DayRows.fits("Завтра", Logic.tomorrowRow(view), room)
            VStack(alignment: .leading, spacing: 1) {
                DayRow(c: c, label: today, text: Logic.todayRow(view, compact: compact))
                DayRow(c: c, label: "Завтра", text: Logic.tomorrowRow(view, compact: compact))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WLabel(text: today, size: 11, weight: .semibold, color: c.t.muted)
                WLabel(
                    text: !view.windowsLeft.isEmpty ? Logic.todayRow(view) : !view.todayWindows.isEmpty ? "Більше немає" : "Без відключень",
                    size: 13, weight: .medium, color: c.t.text, lines: 2, scale: 0.75
                )
            }
        }
    }
}

struct MediumLight: View {
    let c: Ctx
    let look: String

    var body: some View {
        if c.view.todayRuns.isEmpty {
            TextOnly(c: c)
        } else {
            content
        }
    }

    var picW: CGFloat {
        if look == "ring" { return c.rail ? 112 : 134 }
        let sizes = c.rail ? Pictures.mediumRail : Pictures.medium
        return (sizes[look] ?? Pictures.medium["house"]!).width
    }

    @ViewBuilder var picture: some View {
        let view = c.view
        if look == "ring" {
            RingDial(c: c, size: picW, runs: view.todayRuns, nowMin: view.nowMin) {
                DialText(c: c, unit: picW / 130, withTimer: false)
            }
        } else {
            let sizes = c.rail ? Pictures.mediumRail : Pictures.medium
            let size = sizes[look] ?? Pictures.medium["house"]!
            if look == "battery" {
                BatteryDial(c: c, width: size.width, height: size.height)
            } else {
                DayLook(look: look, runs: view.todayRuns, nowMin: view.nowMin, paint: Theme.homePaint(look, c.t))
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    var content: some View {
        let column = c.contentW - (c.rail ? 24 : 36) - picW
        let pill = c.rail ? WidgetText.pillText(c, column, look != "battery") : nil
        return HStack(spacing: c.rail ? 10 : 12) {
            picture
            VStack(alignment: .leading, spacing: 0) {
                StatusBlock(c: c, withTimer: look != "battery", pill: pill)
                Spacer(minLength: 5)
                DayRows(c: c, room: column)
                Spacer(minLength: 3)
                HStack(spacing: 2) {
                    if c.view.fact != nil { FactLine(c: c) } else { Checked(c: c) }
                    Spacer(minLength: 0)
                    RefreshButton(color: c.t.refresh)
                }
            }
            .expand(.topLeading)
        }
        .pad(10, 12, 10, c.rail ? 2 : 12)
        .expand()
    }
}

struct WindowsBlock: View {
    let c: Ctx
    let heading: String
    let windows: [Run]?
    let emptyText: String

    var body: some View {
        let all = windows ?? []
        let shown = Array(all.prefix(4))
        let rest = all.count - shown.count
        VStack(alignment: .leading, spacing: 1) {
            WLabel(text: heading, size: 11, weight: .semibold, color: c.t.muted)
            if shown.isEmpty {
                WLabel(text: emptyText, size: 13, color: c.t.text, lines: 2)
            } else {
                WLabel(text: shown.map(Logic.windowText).joined(separator: "\n"), size: 13, weight: .medium, color: c.t.text, lines: 4)
            }
            if rest > 0 { WLabel(text: "ще \(rest)", size: 11, color: c.t.muted) }
        }
    }
}

struct LargeDay: View {
    let c: Ctx
    let look: String
    let runs: [Run]
    let nowMin: Int?
    let today: Bool

    var body: some View {
        if look == "battery" {
            EmptyView() // батарея показує лише поточний відрізок, а не окремий день
        } else if look == "ring" {
            let size: CGFloat = c.rail ? 124 : 140
            RingDial(c: c, size: size, runs: runs, nowMin: nowMin) {
                if today {
                    DialText(c: c, unit: size / 130, withTimer: false)
                } else {
                    TomorrowDialText(c: c, unit: size / 130)
                }
            }
        } else {
            let size = (c.rail ? Pictures.largeRail : Pictures.large)[look] ?? Pictures.large["house"]!
            DayLook(look: look, runs: runs, nowMin: nowMin, paint: Theme.homePaint(look, c.t))
                .frame(width: size.width, height: size.height)
        }
    }
}

struct LargeLight: View {
    let c: Ctx
    let look: String

    var body: some View {
        if c.view.todayRuns.isEmpty {
            TextOnly(c: c)
        } else {
            content
        }
    }

    var content: some View {
        let view = c.view
        let pill = c.rail ? WidgetText.pillText(c, c.contentW - 20, look != "battery") : nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                WLabel(text: Logic.captionText(view), size: 11, color: c.t.muted)
                Spacer(minLength: 0)
                if !c.rail { RefreshButton(color: c.t.refresh) }
            }
            StatusBlock(c: c, withTimer: look != "battery", pill: pill)
            Spacer(minLength: 6)
            if look == "battery" {
                Centered {
                    BatteryDial(c: c, width: min(280, c.contentW - 40), height: 84)
                }
                Spacer(minLength: 6)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    LargeDay(c: c, look: look, runs: view.todayRuns, nowMin: view.nowMin, today: true)
                    WindowsBlock(c: c, heading: "Сьогодні", windows: view.todayWindows, emptyText: "Без відключень")
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    LargeDay(c: c, look: look, runs: view.tomorrowRuns ?? [], nowMin: nil, today: false)
                    WindowsBlock(c: c, heading: "Завтра", windows: view.tomorrowWindows,
                                 emptyText: view.tomorrowRuns != nil ? "Без відключень" : "Графіка ще немає")
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                if view.fact != nil { FactLine(c: c, size: 12) } else { Checked(c: c) }
                Spacer(minLength: 0)
                if c.rail { RefreshButton(color: c.t.refresh) }
            }
        }
        .pad(14, 16, 12, c.rail ? 4 : 14)
        .expand(.topLeading)
    }
}

// MARK: - Робочий екран: сторінка тривоги

enum AlertText {
    /// «Немає свіжих даних» уже каже час перевірки в подробицях.
    static func checkedLine(_ s: AlertStatus) -> String? {
        guard let checked = s.checked, s.kind != .nodata else { return nil }
        return "\(s.stale ? "дані за" : "перевірено") \(checked)"
    }

    /// Подробиці в один рядок: повні, якщо короткі, інакше лише «з 10:40».
    static func oneLine(_ s: AlertStatus, _ maxChars: Int) -> String {
        if let short = s.subShort, s.sub.count > maxChars { return short }
        return s.sub
    }
}

/// Свіжі дописи каналу моніторингу дослівно, з часом: перший до двох рядків, наступні по рядку.
struct PostsBlock: View {
    let s: AlertStatus
    let p: PageTok
    let limit: Int
    let size: CGFloat

    var body: some View {
        if !s.posts.isEmpty && limit >= 1 {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(s.posts.prefix(limit).enumerated()), id: \.offset) { i, post in
                    WLabel(text: post, size: size, weight: .medium, color: i == 0 ? p.text : p.muted, lines: i == 0 ? 2 : 1, scale: 0.85)
                }
            }
        }
    }
}

/// Інші тривоги в області: «Також тривога:» і назви по рядку, решта — «і ще N».
struct OthersBlock: View {
    let s: AlertStatus
    let p: PageTok
    let max: Int

    var body: some View {
        let skip = s.kind == .nearby ? 1 : 0 // перша вже в подробицях
        let items = Array(s.others.dropFirst(skip))
        if !items.isEmpty && max >= 2 {
            let shown = items.count > max ? Array(items.prefix(max - 1)) : items
            let head = s.kind == .alert || s.kind == .nearby ? "Також тривога:" : "В області тривога:"
            VStack(alignment: .leading, spacing: 1) {
                WLabel(text: head, size: 11, weight: .semibold, color: p.muted)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, name in
                    WLabel(text: name, size: 12, weight: .medium, color: p.text, scale: 0.8)
                }
                if items.count > shown.count {
                    WLabel(text: "і ще \(items.count - shown.count)", size: 12, color: p.muted)
                }
            }
        }
    }
}

/// Малий віджет: місце, назва, подробиці, останній допис каналу; унизу таймер тривоги чи час перевірки.
struct AlertSquare: View {
    let c: Ctx
    let s: AlertStatus
    let p: PageTok

    var body: some View {
        let foot = s.timer ? nil : AlertText.checkedLine(s)
        VStack(alignment: .leading, spacing: 1) {
            WLabel(text: AlertLogic.compactPlace(s.place).isEmpty ? "Повітряна тривога" : AlertLogic.compactPlace(s.place),
                   size: 10.5, weight: .medium, color: p.muted, scale: 0.8)
            WLabel(text: s.title, size: 16, weight: .bold, color: p.title, lines: 2, scale: 0.8)
            WLabel(text: AlertLogic.active(s) ? AlertText.oneLine(s, 20) : s.sub, size: 12, weight: .medium, color: p.text,
                   lines: AlertLogic.active(s) ? 1 : 2, scale: 0.8)
            if !s.posts.isEmpty {
                PostsBlock(s: s, p: p, limit: 1, size: 11).padding(.top, 3)
            }
            Spacer(minLength: 2)
            if s.timer {
                AlertTimer(s: s, size: 15, color: p.title, pauseAt: c.m.pauseAt)
            } else if let foot = foot {
                WLabel(text: foot, size: 10, color: s.stale ? c.t.warn : p.muted)
            }
        }
        .pad(12, 12, 10, 4)
        .expand(.topLeading)
    }
}

/// Середній і великий: місце, назва, подробиці, де оголошено, дописи каналу й інші тривоги області;
/// унизу таймер, час перевірки й «↻» (праворуч унизу, подалі від значків).
struct AlertWide: View {
    let c: Ctx
    let s: AlertStatus
    let p: PageTok
    let large: Bool

    var body: some View {
        let checked = AlertText.checkedLine(s)
        let foot = checked.map { s.timer && !large ? $0 : "\($0) · alerts.in.ua" } ?? "alerts.in.ua"
        let whereText: String? = AlertLogic.active(s) && !s.where_.isEmpty
            ? (s.where_ == "уся область" ? "на всю область" : "оголошено: \(s.where_)") : nil
        VStack(alignment: .leading, spacing: 1) {
            WLabel(text: s.place.isEmpty ? "Повітряна тривога" : s.place, size: 11, weight: .medium, color: p.muted, scale: 0.8)
            WLabel(text: s.title, size: large ? 22 : 19, weight: .bold, color: p.title, scale: 0.8)
            WLabel(text: AlertLogic.active(s) ? AlertText.oneLine(s, 34) : s.sub, size: 13, weight: .medium, color: p.text,
                   lines: AlertLogic.active(s) ? 1 : 2, scale: 0.8)
            if let whereText = whereText {
                WLabel(text: whereText, size: 12, weight: .medium, color: p.muted, scale: 0.8)
            }
            if !s.posts.isEmpty {
                PostsBlock(s: s, p: p, limit: large ? 3 : 2, size: 11.5).padding(.top, 4)
            }
            if large || s.posts.isEmpty {
                OthersBlock(s: s, p: p, max: large ? (s.posts.isEmpty ? 7 : 4) : (whereText != nil ? 0 : 2)).padding(.top, 6)
            }
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                if s.timer { AlertTimer(s: s, size: 16, color: p.title, pauseAt: c.m.pauseAt) }
                Spacer(minLength: 0)
                WLabel(text: foot, size: 10, color: s.stale ? c.t.warn : p.muted, scale: 0.8)
                RefreshButton(color: p.muted)
            }
        }
        .pad(12, 14, 10, 4)
        .expand(.topLeading)
    }
}

// MARK: - Екран блокування
// iOS фарбує віджет сама, тож кольорів тексту не задаємо.

/// Лампочка: світиться, коли світло є, перекреслена, коли немає, контур, коли можливе відключення.
struct Bulb: View {
    let view: Glance
    let size: CGFloat

    var body: some View {
        let state = Logic.bulbState(view)
        let symbol = state == .on ? "lightbulb.max.fill" : state == .off ? "lightbulb.slash.fill" : "lightbulb"
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold, design: .default))
            .frame(width: (size * 1.2).rounded(), height: (size * 1.2).rounded())
    }
}

struct LockDetail: View {
    let c: Ctx
    let timerSize: CGFloat
    var timerWeight: Font.Weight = .regular

    var body: some View {
        if let notice = c.view.notice {
            WLabel(text: notice, size: 12, lines: 2)
        } else if Logic.hasTimer(c.view, c.now) {
            TimerText(c: c, size: timerSize, weight: timerWeight)
        } else {
            WLabel(text: Logic.lockLine(c.view), size: 12, lines: 2)
        }
    }
}

/// Тривога чи загроза в обраному місці: сирена й «Тривога з 10:40» замість рядка датчика.
struct LockAlert: View {
    let s: AlertStatus
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: s.kind == .threat ? "exclamationmark.triangle.fill" : "light.beacon.max.fill")
                .font(.system(size: size * 0.9, weight: .bold, design: .default))
            WLabel(text: AlertLogic.alertShortTitle(s) + (s.subShort.map { " \($0)" } ?? ""), size: size, weight: .bold, scale: 0.75)
        }
    }
}

struct LockExtra: View {
    let c: Ctx
    var body: some View {
        if let s = c.alert, AlertLogic.active(s) {
            LockAlert(s: s)
        } else {
            FactLine(c: c, compact: true, size: 11, lock: true)
        }
    }
}

/// Великий час окремим рядком вміщується поруч із вузьким малюнком.
struct LockStacked: View {
    let c: Ctx
    var body: some View {
        let view = c.view
        VStack(alignment: .leading, spacing: 0) {
            if view.changeMin == nil {
                WLabel(text: view.title, size: 14, weight: .bold, scale: 0.8)
            } else {
                WLabel(text: Logic.lockVerb(view), size: 13, weight: .semibold, scale: 0.8)
                WLabel(text: view.short, size: 18, weight: .bold, scale: 0.8, rounded: true)
            }
            LockDetail(c: c, timerSize: 15, timerWeight: .semibold)
            LockExtra(c: c)
        }
    }
}

struct LockGarland: View {
    let c: Ctx
    var body: some View {
        let view = c.view
        let width = min(c.width, 160)
        let height = min(width * 0.3, c.height - 22).rounded()
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                WLabel(text: view.changeMin == nil ? Logic.lockLine(view) : Logic.lockTitle(view), size: 13, weight: .bold, scale: 0.6)
                Spacer(minLength: 0)
                if let notice = view.noticeShort {
                    WLabel(text: notice, size: 11)
                } else if Logic.hasTimer(view, c.now) {
                    TimerText(c: c, size: 13, weight: .semibold, align: .trailing, width: 58)
                }
            }
            if let s = c.alert, AlertLogic.active(s) {
                LockAlert(s: s)
            } else {
                GarlandLook(runs: view.todayRuns, nowMin: view.nowMin, paint: Theme.lockPaint).frame(width: width, height: height)
            }
        }
        .expand(.topLeading)
    }
}

struct LockRectangular: View {
    let c: Ctx
    let look: String

    var body: some View {
        let view = c.view
        let hasDay = !view.todayRuns.isEmpty
        if look == "garland" && hasDay {
            LockGarland(c: c)
        } else {
            let stacked = hasDay && (look == "house" || look == "tiles")
            HStack(spacing: look == "ring" ? 6 : 8) {
                picture(hasDay)
                if stacked {
                    LockStacked(c: c)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        WLabel(text: Logic.lockTitle(view), size: 14, weight: .bold, scale: 0.65)
                        LockDetail(c: c, timerSize: look == "bulb" ? 19 : 15, timerWeight: look == "bulb" ? .bold : .regular)
                        LockExtra(c: c)
                    }
                }
                Spacer(minLength: 0)
            }
            .expand()
        }
    }

    @ViewBuilder func picture(_ hasDay: Bool) -> some View {
        let view = c.view
        if look == "bulb" {
            Bulb(view: view, size: 38)
        } else if hasDay && look == "ring" {
            ZStack {
                RingLook(runs: view.todayRuns, nowMin: view.nowMin, lineWidth: 5, colors: Theme.lockRing).frame(width: 52, height: 52)
                WLabel(text: view.group ?? "", size: 12, weight: .bold, rounded: true)
            }
            .frame(width: 52, height: 52)
        } else if hasDay {
            let size = Pictures.lock[look] ?? Pictures.lock["house"]!
            Group {
                if look == "battery" {
                    BatteryLook(glance: view, paint: Theme.lockPaint)
                } else if look == "house" {
                    HouseLook(runs: view.todayRuns, nowMin: view.nowMin, paint: Theme.lockPaint)
                } else {
                    TilesLook(runs: view.todayRuns, nowMin: view.nowMin, paint: Theme.lockPaint)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// Круглий віджет: малюнок і час наступної зміни.
struct LockCircular: View {
    let c: Ctx
    let look: String

    static let boxes: [String: CGRect] = [
        "bulb": CGRect(x: 18, y: 6, width: 32, height: 32),
        "house": CGRect(x: 20, y: 6, width: 28, height: 37),
        "tiles": CGRect(x: 14, y: 15, width: 40, height: 26),
        "garland": CGRect(x: 5, y: 12, width: 58, height: 30),
        "battery": CGRect(x: 12, y: 16, width: 44, height: 24),
    ]

    var body: some View {
        let view = c.view
        let size: CGFloat = 68
        let runs = view.todayRuns
        let nowMin = runs.isEmpty ? nil : Optional(view.nowMin)
        Group {
            if look == "ring" {
                ZStack {
                    RingLook(runs: runs, nowMin: nowMin, lineWidth: 6, colors: Theme.lockRing).frame(width: size, height: size)
                    WLabel(text: view.short, size: 15, weight: .bold, rounded: true)
                }
                .frame(width: size, height: size)
            } else {
                let box = LockCircular.boxes[look] ?? LockCircular.boxes["bulb"]!
                ZStack(alignment: .topLeading) {
                    picture(runs, nowMin)
                        .frame(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                    Text(view.short)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: size, height: 18)
                        .offset(x: 0, y: 45)
                }
                .frame(width: size, height: size, alignment: .topLeading)
            }
        }
        .expand()
    }

    @ViewBuilder func picture(_ runs: [Run], _ nowMin: Int?) -> some View {
        switch look {
        case "bulb": Bulb(view: c.view, size: 26)
        case "battery": BatteryLook(glance: c.view, paint: Theme.lockPaint)
        case "house": HouseLook(runs: runs, nowMin: nowMin, paint: Theme.lockPaint)
        case "tiles": TilesLook(runs: runs, nowMin: nowMin, paint: Theme.lockPaint)
        default: GarlandLook(runs: runs, nowMin: nowMin, paint: Theme.lockPaint)
        }
    }
}

/// «Світло до 23:30» лишається правдою й тоді, коли iOS перемальовує віджет із запізненням.
/// Коли в обраному місці тривога, рядок каже про неї («Тривога з 10:40»).
struct LockInline: View {
    let c: Ctx
    var body: some View {
        if let s = c.alert, AlertLogic.active(s) {
            Text(AlertLogic.alertShortTitle(s) + (s.subShort.map { " \($0)" } ?? ""))
        } else {
            Text(c.view.title)
        }
    }
}

// MARK: - Вибір розкладки

extension WidgetFamily {
    /// Назва розміру для ключа сторінки (як Widget.family у Scripting).
    var key: String {
        switch self {
        case .systemSmall: return "systemSmall"
        case .systemMedium: return "systemMedium"
        case .systemLarge: return "systemLarge"
        case .systemExtraLarge: return "systemExtraLarge"
        case .accessoryCircular: return "accessoryCircular"
        case .accessoryRectangular: return "accessoryRectangular"
        case .accessoryInline: return "accessoryInline"
        @unknown default: return "other"
        }
    }

    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}

/// Увесь віджет. inApp: показ у застосунку (вкладка «Віджет»): там фон малюємо самі,
/// бо containerBackground працює лише у віджеті.
struct WidgetContent: View {
    let m: WidgetModel
    var inApp = false
    var dark = false
    var clear = false

    var body: some View {
        let t = Theme.tokens(m.glance.style, dark: dark, clear: clear && !m.family.isAccessory)
        let alertsOn = m.alert != nil && m.pages.contains(AlertLogic.alert)
        let small = m.family == .systemSmall
        let shown = alertsOn && m.page == AlertLogic.alert ? AlertLogic.alert : AlertLogic.light
        let c = Ctx(
            m: m, t: t, contentW: m.size.width - (alertsOn && !m.family.isAccessory ? (small ? railSmall : railWide) : 0),
            alert: alertsOn ? m.alert : nil, pages: alertsOn ? m.pages : [AlertLogic.light], page: shown
        )
        let pageTok: PageTok? = shown == AlertLogic.alert ? Theme.alertPage(t, c.alert?.kind) : nil
        let background = TokenBackground(
            bg0: pageTok?.bg0 ?? t.bg0, bg1: pageTok?.bg1 ?? t.bg1, alpha: pageTok?.alpha ?? t.bgAlpha, vertical: pageTok != nil
        )
        if m.family.isAccessory {
            accessory(c)
                .modifier(Backdrop(inApp: inApp, accessory: true) { Color.clear })
        } else {
            home(c, shown: shown)
                .widgetURL(URL(string: "\(Shared.deepLinkScheme)://\(shown)"))
                .modifier(Backdrop(inApp: inApp, accessory: false) { background })
        }
    }

    @ViewBuilder func accessory(_ c: Ctx) -> some View {
        let lockLook = Logic.lockLookOf(m.glance.lockLook)
        switch m.family {
        case .accessoryInline: LockInline(c: c)
        case .accessoryCircular: LockCircular(c: c, look: lockLook)
        default: LockRectangular(c: c, look: lockLook)
        }
    }

    @ViewBuilder func home(_ c: Ctx, shown: String) -> some View {
        let look = Logic.lookOf(m.glance.look, Logic.defaultLook)
        let page = Group {
            if shown == AlertLogic.alert, let s = c.alert {
                if m.family == .systemSmall {
                    AlertSquare(c: c, s: s, p: Theme.alertPage(c.t, s.kind))
                } else {
                    AlertWide(c: c, s: s, p: Theme.alertPage(c.t, s.kind), large: m.family != .systemMedium)
                }
            } else if m.family == .systemSmall {
                SmallLight(c: c, look: look)
            } else if m.family == .systemMedium {
                MediumLight(c: c, look: look)
            } else {
                LargeLight(c: c, look: look)
            }
        }
        if c.rail {
            HStack(spacing: 0) {
                page.expand()
                Rail(c: c, small: m.family == .systemSmall)
            }
            .expand()
        } else {
            page.expand()
        }
    }
}

/// Фон віджета: у віджеті — containerBackground (iOS прибирає його сама в прозорих і тонованих режимах),
/// у застосунку — звичайне тло з заокругленими кутами, як на робочому екрані.
struct Backdrop<Background: View>: ViewModifier {
    let inApp: Bool
    let accessory: Bool
    let background: () -> Background

    init(inApp: Bool, accessory: Bool, @ViewBuilder background: @escaping () -> Background) {
        self.inApp = inApp
        self.accessory = accessory
        self.background = background
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if inApp {
            content
                .background(accessory ? AnyView(Color.black.opacity(0.78)) : AnyView(background()))
                .foregroundColor(accessory ? .white : nil)
                .clipShape(RoundedRectangle(cornerRadius: accessory ? 14 : 22, style: .continuous))
        } else {
            content.containerBackground(for: .widget) { background() }
        }
    }
}
