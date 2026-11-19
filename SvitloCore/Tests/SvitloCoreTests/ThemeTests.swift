// Палітра «Ранковий туман» (Theme.swift): контраст за WCAG. Порт палітрових тестів tools/scripting-alerts.test.mjs
// (без «Напівпрозорого»: на iPhone його немає) і перевірка за зразком Android-тесту «палітра: контраст у всіх фонах»
// (android/test/ua/svitlo/grafik/AlertsTest.java) з тими самими порогами: текст ≥ 4,5, значки й позначки ≥ 3.
import XCTest
@testable import SvitloCore

private let MODES: [(String, Tokens)] = [("світлий", Theme.light()), ("нічний", Theme.night())]

private func worst(_ fg: RGBA, _ bgs: [RGBA]) -> Double { bgs.map { Theme.contrast(fg, $0) }.min() ?? 0 }

private func need(_ fails: inout [String], _ what: String, _ fg: RGBA, _ bgs: [RGBA], _ min: Double) {
    let v = worst(fg, bgs)
    if v < min { fails.append("\(what): \(fg.hex) на \(bgs.map { $0.hex }.joined(separator: "/")) = \(String(format: "%.2f", v)) < \(min)") }
}

private func icons(_ t: Tokens) -> [(String, IconTok)] {
    [("світло є", t.icons.on), ("світла немає", t.icons.off), ("можливе", t.icons.maybe), ("графік невідомий", t.icons.unknown),
     ("тривога", t.icons.alert), ("загроза", t.icons.threat), ("поруч", t.icons.nearby), ("тихо", t.icons.quiet),
     ("немає даних", t.icons.stale), ("без новин", t.icons.idle)]
}

private func pages(_ t: Tokens) -> [(String, PageTok)] {
    [("alert", t.pages.alert), ("threat", t.pages.threat), ("nearby", t.pages.nearby), ("quiet", t.pages.quiet), ("nodata", t.pages.neutral)]
}

/// Тло сторінки: кінці градієнта; напівпрозора — поверх чорного й білого (як у JS-тесті).
private func pageBackgrounds(_ page: PageTok) -> [RGBA] {
    page.alpha < 1 ? [Theme.over(page.bg0, page.alpha, .black()), Theme.over(page.bg0, page.alpha, .white())] : [page.bg0, page.bg1]
}

/// Видимі частини значка чи крапки: заливка (якщо не прозора), обідок, кільце.
private func visibleParts(_ icon: IconTok) -> [RGBA] {
    ([icon.fill.isClear ? nil : icon.fill, icon.rim, icon.ring] as [RGBA?]).compactMap { $0 }.filter { !$0.isClear }
}

/// Найкращий контраст краю: досить, щоб хоч одна видима частина відрізнялася від тла.
private func edge(_ icon: IconTok, _ bgs: [RGBA]) -> Double { visibleParts(icon).map { worst($0, bgs) }.max() ?? 0 }

final class ThemeTests: XCTestCase {
    // палітра: текст ≥ 4,5 і знаки значків ≥ 3 у «Світлому», «Нічному» й «Напівпрозорому» (scripting-alerts.test.mjs)
    func testПалітраТекстІЗнакиЗначків() {
        var fails: [String] = []
        for (m, t) in MODES {
            for bg in [t.bg0, t.bg1] {
                for (key, color) in [("text", t.text), ("muted", t.muted), ("timer", t.timer), ("brand", t.brand), ("warn", t.warn), ("refresh", t.refresh)] {
                    need(&fails, "\(m): \(key)", color, [bg], 4.5)
                }
                need(&fails, "\(m): блискавка", t.titleBolt, [bg], 3)
            }
            for (name, icon) in icons(t) {
                if icon.glyph.isOpaque && icon.fill.isOpaque { need(&fails, "\(m): знак значка \(name)", icon.glyph, [icon.fill], 3) }
                if let pillBg = icon.pillBg, let pillText = icon.pillText { need(&fails, "\(m): напис \(name)", pillText, [pillBg], 4.5) }
            }
            for (name, page) in pages(t) {
                for (key, color) in [("title", page.title), ("text", page.text), ("muted", page.muted)] {
                    need(&fails, "\(m): сторінка \(name), \(key)", color, pageBackgrounds(page), 4.5)
                }
            }
        }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }

    // палітра: контраст у всіх фонах (текст ≥ 4,5, значки й позначки ≥ 3) — за зразком Android AlertsTest
    func testПалітраКонтрастУВсіхФонахЯкВAndroid() {
        var fails: [String] = []
        for (m, t) in MODES {
            let bg = [t.bg0, t.bg1]
            let texts: [(String, RGBA)] = [("текст", t.text), ("приглушений", t.muted), ("таймер", t.timer), ("підписи годин", t.label),
                                           ("попередження", t.warn), ("бренд", t.brand)]
            for (name, color) in texts { need(&fails, "\(m): \(name)", color, bg, 4.5) }
            need(&fails, "\(m): блискавка в заголовку", t.titleBolt, bg, 3)
            need(&fails, "\(m): «↻»", t.refresh, bg, 3)
            need(&fails, "\(m): позначка сторінки", t.marker, bg, 3)
            need(&fails, "\(m): активний кружечок", t.dotOn, bg, 3)
            need(&fails, "\(m): неактивний кружечок", t.dotOff, bg, 3)
            for (name, dot) in [("датчик світло є", t.sensor.on), ("датчик немає світла", t.sensor.off), ("датчик мовчить", t.sensor.silent)] {
                let v = edge(dot, bg)
                if v < 3 { fails.append("\(m): \(name) \(String(format: "%.2f", v)) < 3") }
            }
            need(&fails, "\(m): вікно зі світлом / без світла", t.lit0, [t.dark], 3)
            need(&fails, "\(m): рамка «зараз» / стіна", t.now, [t.wall0, t.wall1], 3)
            // Значки стоять на відступі кольору тла (halo).
            for (name, icon) in icons(t) {
                let v = edge(icon, [t.halo])
                if v < 3 { fails.append("\(m): край значка «\(name)» \(String(format: "%.2f", v)) < 3") }
                if icon.glyph.isOpaque && icon.fill.isOpaque { need(&fails, "\(m): знак значка «\(name)»", icon.glyph, [icon.fill], 3) }
                if let pillBg = icon.pillBg, let pillText = icon.pillText { need(&fails, "\(m): напис «\(name)»", pillText, [pillBg], 4.5) }
            }
            for (name, page) in pages(t) {
                let pbg = pageBackgrounds(page)
                need(&fails, "\(m): сторінка \(name), назва", page.title, pbg, 4.5)
                need(&fails, "\(m): сторінка \(name), текст", page.text, pbg, 4.5)
                need(&fails, "\(m): сторінка \(name), приглушений", page.muted, pbg, 4.5)
                need(&fails, "\(m): сторінка \(name), попередження", t.warn, pbg, 4.5)
            }
        }
        XCTAssertTrue(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }

    // палітра: «Як система» — пари кольорів «Світлого» й «Нічного», iOS обирає сама (scripting-alerts.test.mjs).
    // На iPhone «Як система» не зберігає пари: тему обирає віджет за темною темою телефона.
    func testЯкСистемаСвітлийУденьНічнийУТемнійТемі() {
        XCTAssertEqual(Theme.tokens("auto", dark: false), Theme.light())
        XCTAssertEqual(Theme.tokens("auto", dark: true), Theme.night())
        XCTAssertEqual(Theme.tokens("light", dark: true), Theme.light(), "явний вибір не залежить від теми телефона")
        XCTAssertEqual(Theme.tokens("night", dark: false), Theme.night())
        // Кільце значка «світла немає» є лише в нічній версії: у світлій його немає.
        XCTAssertNil(Theme.light().icons.off.ring)
        XCTAssertNotNil(Theme.night().icons.off.ring)
        XCTAssertEqual(Theme.night().icons.on.fill, Theme.light().icons.on.fill, "однакові кольори лишаються однаковими")
        XCTAssertEqual(Theme.light().bgAlpha, 1)
        XCTAssertEqual(Theme.night().bgAlpha, 1)
    }

    // фони: старі назви, вибір і прозорий фон Scripting (scripting-alerts.test.mjs). «Напівпрозорого» на iPhone немає.
    func testФониСтаріНазвиВибірІПрозорий() {
        XCTAssertEqual(Theme.styleOf("indigo"), "night")
        XCTAssertEqual(Theme.styleOf("dawn"), "light")
        XCTAssertEqual(Theme.styleOf("state"), "light")
        XCTAssertEqual(Theme.styleOf(nil), "light")
        XCTAssertEqual(Theme.styleOf("auto"), "auto")
        XCTAssertEqual(Theme.styleOf("glass"), "light", "«Напівпрозорий» на iPhone став «Світлим»")
        XCTAssertEqual(Theme.tokens("night", dark: false).mode, "night")
        XCTAssertEqual(Theme.tokens("glass", dark: false).mode, "light")
        // Фон малює iOS (прозорий чи тонований віджет): вміст без власного тла, хоч який фон обрано.
        for style in ["light", "night", "auto", "glass", nil] as [String?] {
            for dark in [false, true] {
                let t = Theme.tokens(style, dark: dark, clear: true)
                XCTAssertEqual(t.mode, "clear", "\(style ?? "nil") dark=\(dark)")
                XCTAssertEqual(t.bgAlpha, 0)
                XCTAssertTrue(t.shadow)
                XCTAssertTrue(t.bg0.isClear && t.bg1.isClear)
                XCTAssertEqual(pages(t).map { $0.1.alpha }, [0, 0, 0, 0, 0])
            }
        }
    }

    // Нове: самі формули контрасту й змішування (на них стоять перевірки палітри вище)
    func testФормулиКонтрастуЙЗмішування() {
        XCTAssertEqual(Theme.contrast(.black(), .white()), 21, accuracy: 1e-9)
        XCTAssertEqual(Theme.contrast(.white(), .black()), 21, accuracy: 1e-9)
        XCTAssertEqual(Theme.contrast(RGBA(hex: "#565B76"), RGBA(hex: "#565B76")), 1, accuracy: 1e-12)
        XCTAssertEqual(Theme.contrast(RGBA(hex: "#767676"), .white()), 4.54, accuracy: 0.01) // відома межа AA
        XCTAssertEqual(RGBA(hex: "#4347B5").hex, "#4347B5")
        XCTAssertEqual(Theme.over(.white(), 0.5, .black()).hex, "#808080")
        XCTAssertEqual(Theme.over(.white(), 1, .black()).hex, "#FFFFFF")
        XCTAssertEqual(Theme.over(.white(), 0, RGBA(hex: "#3B4A5C")).hex, "#3B4A5C")
    }
}
