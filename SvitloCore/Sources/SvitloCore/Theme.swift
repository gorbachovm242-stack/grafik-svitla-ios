// Фони й кольори віджета: палітра B «Ранковий туман» (та сама, що в «Маяку» для Android, android/design/PALETTE.md,
// і в scripting/scripts/Графік світла/theme.ts). Тут лише числа, без SwiftUI: контраст перевіряють тести.
// Фони: «Світлий» (типовий), «Нічний» і «Як система» (світлий удень, нічний у темній темі iPhone).
// «Напівпрозорого» немає: крізь звичайний віджет iOS шпалер не показує. Коли iOS сама робить віджет прозорим
// чи тонованим (режими «Прозорий» і «Тонований» на iOS 18+), вмикається clear: світлий текст, напівпрозорі малюнки.
// Зеленого немає: у кожного стану свій знак, тож колір ніколи не єдиний носій.
import Foundation

public struct RGBA: Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// «#RRGGBB».
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let n = Int(digits.prefix(6), radix: 16) ?? 0
        self.init(Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255, 1)
    }

    public static let clear = RGBA(0, 0, 0, 0)
    public static func white(_ a: Double = 1) -> RGBA { RGBA(1, 1, 1, a) }
    public static func black(_ a: Double = 1) -> RGBA { RGBA(0, 0, 0, a) }

    public func opacity(_ x: Double) -> RGBA { RGBA(r, g, b, a * x) }
    public var isClear: Bool { a <= 0 }
    public var isOpaque: Bool { a >= 1 }

    public var hex: String {
        func c(_ v: Double) -> String {
            let s = String(Int((max(0, min(1, v)) * 255).rounded()), radix: 16, uppercase: true)
            return s.count < 2 ? "0" + s : s
        }
        return "#" + c(r) + c(g) + c(b)
    }
}

private func h(_ hex: String) -> RGBA { RGBA(hex: hex) }

/// Значок стану: коло (заливка, обідок чи кільце, пунктир — немає даних), знак усередині, світіння, ярлик.
public struct IconTok: Equatable, Sendable {
    public var fill: RGBA
    public var glyph: RGBA
    public var rim: RGBA?
    public var ring: RGBA?
    public var dashed = false
    public var glow: RGBA?
    public var pillBg: RGBA?
    public var pillText: RGBA?
}

/// Сторінка тривоги: фон і текст свого стану. alpha 0 — без фону (iOS робить віджет прозорим).
public struct PageTok: Equatable, Sendable {
    public var bg0: RGBA
    public var bg1: RGBA
    public var title: RGBA
    public var text: RGBA
    public var muted: RGBA
    public var alpha: Double = 1
}

public struct Icons: Equatable, Sendable {
    public var on, off, maybe, unknown, alert, threat, nearby, quiet, stale, idle: IconTok
}

public struct SensorIcons: Equatable, Sendable {
    public var on, off, silent: IconTok
}

public struct Pages: Equatable, Sendable {
    public var alert, threat, nearby, quiet, neutral: PageTok
}

public struct Tokens: Equatable, Sendable {
    public var mode = "light"
    public var bg0 = RGBA.clear
    public var bg1 = RGBA.clear
    public var bgAlpha: Double = 1 // 1 — суцільний фон, 0 — без фону
    public var shadow = false // текст із тінню поверх шпалер
    public var text = RGBA.clear
    public var muted = RGBA.clear
    public var timer = RGBA.clear
    public var brand = RGBA.clear // дрібний акцентний текст: місце, «Завтра»
    public var titleBolt = RGBA.clear // блискавка біля заголовка, великий час без світла
    public var refresh = RGBA.clear
    public var warn = RGBA.clear // попередження в тексті (графік змінився, старі дані)
    // Будинок та інші вигляди
    public var wall0 = RGBA.clear
    public var wall1 = RGBA.clear
    public var roof = RGBA.clear
    public var lit0 = RGBA.clear
    public var lit1 = RGBA.clear
    public var litGlow = RGBA.clear
    public var dark = RGBA.clear // вікно без світла
    public var maybe = RGBA.clear
    public var now = RGBA.clear // рамка «зараз» у будинку
    public var label = RGBA.clear // підписи годин
    public var ringOn = RGBA.clear
    public var ringOff = RGBA.clear
    public var ringUnknown = RGBA.clear
    public var tileOff = RGBA.clear
    public var charge = RGBA.clear
    // Значки модулів
    public var icons: Icons
    // Стовпчик значків
    public var track = RGBA.clear // мʼяка доріжка під значками
    public var halo = RGBA.clear // відступ навколо значка
    public var marker = RGBA.clear // смужка відкритої сторінки
    public var dotOn = RGBA.clear
    public var dotOff = RGBA.clear
    // Датчик СвітлоБота: крапка біля «↻» і в рядку факту
    public var sensor: SensorIcons
    // Сторінки тривоги
    public var pages: Pages
}

public enum Theme {
    // MARK: «Світлий»

    public static func light() -> Tokens {
        let blank = IconTok(fill: .clear, glyph: .clear)
        let page = PageTok(bg0: .clear, bg1: .clear, title: .clear, text: .clear, muted: .clear)
        var t = Tokens(
            icons: Icons(on: blank, off: blank, maybe: blank, unknown: blank, alert: blank, threat: blank, nearby: blank, quiet: blank, stale: blank, idle: blank),
            sensor: SensorIcons(on: blank, off: blank, silent: blank),
            pages: Pages(alert: page, threat: page, nearby: page, quiet: page, neutral: page)
        )
        t.mode = "light"
        t.bg0 = h("#FCFCFF"); t.bg1 = h("#E6E8F3"); t.bgAlpha = 1; t.shadow = false
        t.text = h("#1C1F33"); t.muted = h("#565B76"); t.timer = h("#3B4060"); t.brand = h("#4347B5")
        t.titleBolt = h("#A26A00"); t.refresh = h("#565B76"); t.warn = h("#8A3E00")
        t.wall0 = h("#868CB1"); t.wall1 = h("#686E9A"); t.roof = h("#5A6089"); t.lit0 = h("#FFD660"); t.lit1 = h("#FFB52A")
        t.litGlow = h("#FFC233"); t.dark = h("#3E4470"); t.maybe = h("#E4CF98"); t.now = h("#FFFFFF"); t.label = h("#565B76")
        t.ringOn = h("#FFB52A"); t.ringOff = h("#BCC1DA"); t.ringUnknown = h("#E2E4EE"); t.tileOff = h("#D0D4E6"); t.charge = h("#9FA4E0")
        t.icons = Icons(
            on: IconTok(fill: h("#FFC83F"), glyph: h("#342300"), rim: h("#9E6900")),
            off: IconTok(fill: h("#3E4378"), glyph: h("#FFFFFF")),
            maybe: IconTok(fill: h("#FFF2CF"), glyph: h("#7A5400"), ring: h("#A06C00")),
            unknown: IconTok(fill: h("#EEF0F7"), glyph: h("#4E536C"), ring: h("#6F748E"), dashed: true),
            alert: IconTok(fill: h("#D6335C"), glyph: h("#FFFFFF"), glow: h("#E0406A"), pillBg: h("#D6335C"), pillText: h("#FFFFFF")),
            threat: IconTok(fill: h("#F07A1C"), glyph: h("#331600"), rim: h("#A3520A"), pillBg: h("#F07A1C"), pillText: h("#2E1300")),
            nearby: IconTok(fill: h("#FFF1E6"), glyph: h("#A54A05"), ring: h("#C55A10"), pillBg: h("#FFE6D2"), pillText: h("#7A3700")),
            quiet: IconTok(fill: h("#666DAE"), glyph: h("#FFFFFF")),
            stale: IconTok(fill: h("#EEF0F7"), glyph: h("#4E536C"), ring: h("#6F748E"), dashed: true, pillBg: h("#E3E6F1"), pillText: h("#43475F")),
            idle: IconTok(fill: h("#707590"), glyph: h("#FFFFFF"))
        )
        t.track = h("#DDE0EE"); t.halo = h("#FCFCFF"); t.marker = h("#4347B5"); t.dotOn = h("#4347B5"); t.dotOff = h("#6F758F")
        t.sensor = SensorIcons(
            on: IconTok(fill: h("#FFC83F"), glyph: .clear, rim: h("#9E6900")),
            off: IconTok(fill: h("#3E4378"), glyph: .clear),
            silent: IconTok(fill: .clear, glyph: .clear, ring: h("#6F748E"), dashed: true)
        )
        t.pages = Pages(
            alert: PageTok(bg0: h("#FFF6F8"), bg1: h("#F9DCE4"), title: h("#A2163F"), text: h("#33141F"), muted: h("#7A3D52")),
            threat: PageTok(bg0: h("#FFF6EC"), bg1: h("#FFDDBF"), title: h("#7A3700"), text: h("#3A1F0A"), muted: h("#6C4325")),
            nearby: PageTok(bg0: h("#FFFAF4"), bg1: h("#FFE8D6"), title: h("#7A3700"), text: h("#3A1F0A"), muted: h("#6C4325")),
            quiet: PageTok(bg0: h("#F6F6FE"), bg1: h("#E2E4F7"), title: h("#3E4378"), text: h("#1C1F33"), muted: h("#50556F")),
            neutral: PageTok(bg0: h("#FCFCFF"), bg1: h("#E6E8F3"), title: h("#1C1F33"), text: h("#1C1F33"), muted: h("#565B76"))
        )
        return t
    }

    // MARK: «Нічний»: темно-синє тло, лише явним вибором (або в темній темі для «Як система»)

    public static func night() -> Tokens {
        var t = light()
        t.mode = "night"
        t.bg0 = h("#232741"); t.bg1 = h("#14172A")
        t.text = h("#F3F4FF"); t.muted = h("#B5B9D6"); t.timer = h("#DDE0F7"); t.brand = h("#C7CAFF"); t.titleBolt = h("#FFC83F")
        t.refresh = h("#B5B9D6"); t.warn = h("#FFB27A")
        t.wall0 = h("#55598A"); t.wall1 = h("#43477A"); t.roof = h("#383C66"); t.dark = h("#2A2D50"); t.maybe = h("#8F7F55")
        t.label = h("#B5B9D6"); t.ringOff = h("#41466C"); t.ringUnknown = h("#2F3352"); t.tileOff = h("#3A3F63"); t.charge = h("#6F74C0")
        t.icons.off = IconTok(fill: h("#232741"), glyph: h("#D3D5F2"), ring: h("#9599CC"))
        t.icons.quiet = IconTok(fill: h("#9DA3E6"), glyph: h("#1B1E38"))
        t.icons.unknown = IconTok(fill: h("#2D3150"), glyph: h("#D3D5F2"), ring: h("#8A8EB5"), dashed: true)
        t.icons.stale = IconTok(fill: h("#2D3150"), glyph: h("#D3D5F2"), ring: h("#8A8EB5"), dashed: true, pillBg: h("#33375A"), pillText: h("#DDE0F7"))
        t.icons.maybe = IconTok(fill: h("#3A3550"), glyph: h("#FFC83F"), ring: h("#FFC83F"))
        t.icons.nearby = IconTok(fill: h("#3A2C3A"), glyph: h("#FFB07A"), ring: h("#FF9A55"), pillBg: h("#4A3036"), pillText: h("#FFD3B5"))
        t.icons.alert = IconTok(fill: h("#E5486E"), glyph: h("#FFFFFF"), glow: h("#E5486E"), pillBg: h("#C23258"), pillText: h("#FFFFFF"))
        t.icons.idle = IconTok(fill: h("#9A9EC8"), glyph: h("#1B1E38"))
        t.track = h("#2E3252"); t.halo = h("#232741"); t.marker = h("#C7CAFF"); t.dotOn = h("#C7CAFF"); t.dotOff = h("#8A8EB5")
        t.sensor = SensorIcons(
            on: IconTok(fill: h("#FFC83F"), glyph: .clear, rim: h("#FFC83F")),
            off: IconTok(fill: .clear, glyph: .clear, ring: h("#9599CC")), // на темному фоні «немає світла» кільцем
            silent: IconTok(fill: .clear, glyph: .clear, ring: h("#8A8EB5"), dashed: true)
        )
        t.pages = Pages(
            alert: PageTok(bg0: h("#3B1B2C"), bg1: h("#2A1220"), title: h("#FF9DB8"), text: h("#F7E8EE"), muted: h("#D7AFC1")),
            threat: PageTok(bg0: h("#3A2614"), bg1: h("#29190C"), title: h("#FFB872"), text: h("#F8EEE4"), muted: h("#D9BFA6")),
            nearby: PageTok(bg0: h("#33261C"), bg1: h("#231910"), title: h("#FFB872"), text: h("#F8EEE4"), muted: h("#D9BFA6")),
            quiet: PageTok(bg0: h("#232741"), bg1: h("#14172A"), title: h("#C7CAFF"), text: h("#F3F4FF"), muted: h("#B5B9D6")),
            neutral: PageTok(bg0: h("#232741"), bg1: h("#14172A"), title: h("#F3F4FF"), text: h("#F3F4FF"), muted: h("#B5B9D6"))
        )
        return t
    }

    // MARK: Без фону (iOS сама робить віджет прозорим чи тонованим): світлий текст, напівпрозорі малюнки

    public static func clear() -> Tokens {
        var t = night()
        func page(_ title: RGBA) -> PageTok { PageTok(bg0: .clear, bg1: .clear, title: title, text: .white(), muted: .white(0.85), alpha: 0) }
        t.mode = "clear"
        t.bg0 = .clear; t.bg1 = .clear; t.bgAlpha = 0; t.shadow = true
        t.text = .white(); t.muted = .white(0.85); t.timer = .white(); t.brand = .white(); t.titleBolt = h("#FFD66B")
        t.refresh = .white(0.85); t.warn = h("#FFC27A"); t.label = .white(0.8)
        t.wall0 = .white(0.3); t.wall1 = .white(0.16); t.roof = .white(0.4); t.dark = .black(0.38)
        t.maybe = .white(0.62); t.ringOn = h("#FFD66B"); t.ringOff = .white(0.38); t.ringUnknown = .white(0.2)
        t.tileOff = .white(0.28); t.charge = .white(0.5)
        t.track = .white(0.2); t.halo = .clear; t.marker = .white(); t.dotOn = .white(); t.dotOff = .white(0.6)
        t.pages = Pages(alert: page(h("#FF9DB8")), threat: page(h("#FFB872")), nearby: page(h("#FFB872")), quiet: page(.white()), neutral: page(.white()))
        return t
    }

    // MARK: Вибір фону

    public static let styleIds = ["light", "night", "auto"]
    public static let styleNames: [String: String] = ["light": "Світлий", "night": "Нічний", "auto": "Як система"]
    public static let defaultStyle = "light"

    /// Старі й чужі фони переходять на найближчий: «Індиго» на «Нічний», решта на «Світлий».
    public static func styleOf(_ id: String?) -> String {
        if let id = id, styleIds.contains(id) { return id }
        return id == "indigo" ? "night" : defaultStyle
    }

    /// dark: темна тема iPhone (для «Як система»); clear: iOS малює віджет без нашого фону.
    public static func tokens(_ style: String?, dark: Bool, clear: Bool = false) -> Tokens {
        if clear { return Theme.clear() }
        switch styleOf(style) {
        case "night": return night()
        case "auto": return dark ? night() : light()
        default: return light()
        }
    }

    // MARK: Стан → значок і сторінка

    /// Модуль світла: світло є, немає, можливе відключення; решта (зараз стан невідомий) — пунктирне коло.
    public static func lightIcon(_ t: Tokens, _ kind: LightKind?) -> IconTok {
        switch kind {
        case .on?: return t.icons.on
        case .off?: return t.icons.off
        case .maybe?, .check?: return t.icons.maybe
        default: return t.icons.unknown
        }
    }

    /// Модуль тривоги: тривога, загроза, поруч, тихо, немає даних; не налаштовано — сірий.
    public static func alertIcon(_ t: Tokens, _ kind: AlertKind?) -> IconTok {
        switch kind {
        case .alert?: return t.icons.alert
        case .threat?: return t.icons.threat
        case .nearby?: return t.icons.nearby
        case .quiet?: return t.icons.quiet
        case .nodata?: return t.icons.stale
        default: return t.icons.idle
        }
    }

    public static func alertPage(_ t: Tokens, _ kind: AlertKind?) -> PageTok {
        switch kind {
        case .alert?: return t.pages.alert
        case .threat?: return t.pages.threat
        case .nearby?: return t.pages.nearby
        case .quiet?: return t.pages.quiet
        default: return t.pages.neutral
        }
    }

    /// Знаки значків: SF Symbols.
    public static func lightGlyph(_ kind: LightKind?) -> String { kind == .off ? "bolt.slash.fill" : "bolt.fill" }

    public static func alertGlyph(_ kind: AlertKind?) -> String {
        switch kind {
        case .threat?: return "exclamationmark"
        case .quiet?: return "checkmark"
        case .setup?: return "mappin"
        default: return "light.beacon.max.fill"
        }
    }

    public static func statusSymbol(_ kind: LightKind) -> String {
        switch kind {
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        case .maybe, .check: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle"
        }
    }

    public static func statusColor(_ kind: LightKind, _ t: Tokens) -> RGBA {
        switch kind {
        case .on: return t.titleBolt
        case .off: return t.text
        case .maybe, .check: return t.warn
        default: return t.muted
        }
    }

    // MARK: Вигляди світла

    /// Чим малювати вигляд. На екрані блокування iOS фарбує віджет сама, тож важить лише прозорість.
    public struct Paint: Equatable, Sendable {
        public var lock: Bool
        public var cells: [Status: RGBA]
        public var lit: [RGBA] // градієнт світлого вікна чи лампочки
        public var wall: [RGBA]?
        public var roof: RGBA?
        public var mark: RGBA // рамка поточної години
        public var label: RGBA? // підписи годин
        public var line: RGBA // контур батареї, будинку
        public var wire: RGBA
        public var glow: RGBA?
        public var batteryOn: [RGBA]
        public var charge: [RGBA]
        public var fadePast: Bool

        public func cell(_ st: Status) -> RGBA { cells[st] ?? .clear }
    }

    public static func homePaint(_ look: String, _ t: Tokens) -> Paint {
        let house = look == "house"
        var cells: [Status: RGBA] = [.on: t.ringOn, .off: t.ringOff, .maybe: t.maybe, .unknown: t.ringUnknown]
        if house {
            cells = [.on: t.lit0, .off: t.dark, .maybe: t.maybe, .unknown: t.roof]
        } else if look == "tiles" {
            cells = [.on: t.icons.on.fill, .off: t.tileOff, .maybe: t.maybe, .unknown: t.ringUnknown]
        }
        return Paint(
            lock: false, cells: cells, lit: [house ? t.lit0 : cells[.on]!, t.lit1], wall: [t.wall0, t.wall1], roof: t.roof,
            mark: house ? t.now : t.text, label: t.label, line: t.text, wire: t.muted, glow: t.litGlow,
            batteryOn: [t.icons.on.fill, t.lit1], charge: [t.charge, t.charge], fadePast: true
        )
    }

    public struct RingColors: Equatable, Sendable {
        public var cells: [Status: RGBA]
        public var now: RGBA
        public var edge: RGBA
        public func cell(_ st: Status) -> RGBA { cells[st] ?? .clear }
    }

    public static func ringColors(_ t: Tokens) -> RingColors {
        RingColors(
            cells: [.on: t.ringOn, .off: t.ringOff, .maybe: t.maybe, .unknown: t.ringUnknown], now: t.text,
            edge: t.bgAlpha <= 0 ? .black(0.45) : t.bg0
        )
    }

    public static let lockPaint = Paint(
        lock: true,
        cells: [.on: .white(), .off: .white(0.24), .maybe: .white(0.55), .unknown: .white(0.12)],
        lit: [.white(), .white()], wall: nil, roof: nil, mark: .white(), label: nil, line: .white(), wire: .white(0.72),
        glow: nil, batteryOn: [.white(), .white()], charge: [.white(0.55), .white(0.55)], fadePast: false
    )

    /// Кільце на екрані блокування: прозорість показує стан.
    public static let lockRing = RingColors(
        cells: [.on: .white(0.32), .off: .white(), .maybe: .white(0.62), .unknown: .white(0.16)], now: .white(), edge: .black()
    )

    // MARK: Контраст WCAG (для тестів)

    public static func luminance(_ c: RGBA) -> Double {
        func ch(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let q = { (v: Double) in (v * 255).rounded() / 255 }
        return 0.2126 * ch(q(c.r)) + 0.7152 * ch(q(c.g)) + 0.0722 * ch(q(c.b))
    }

    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Колір fg із прозорістю alpha поверх bg.
    public static func over(_ fg: RGBA, _ alpha: Double, _ bg: RGBA) -> RGBA {
        func mix(_ f: Double, _ b: Double) -> Double { ((f * 255) * alpha + (b * 255) * (1 - alpha)).rounded() / 255 }
        return RGBA(mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b), 1)
    }
}
