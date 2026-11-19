// Порт tools/scripting-tomorrow.test.mjs: графік на завтра рядком поруч із сьогодні, і перемикання сторінок дотиком
// до значка не ходить у мережу. Дані синтетичні. Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

// Сторінка обленерго: на 6 листопада одне відключення, на 7 (завтра) два по 3 години.
private let TWO_DAYS = "<html><body>" + simplePost(TOMORROW_TITLE, ["3.2: 06:00 - 09:00, 15:00 - 18:00"])
    + simplePost(TODAY_TITLE, ["3.2: 12:00 - 14:00"]) + "</body></html>"
private let TODAY_ONLY = "<html><body>" + simplePost(TODAY_TITLE, ["3.2: 12:00 - 14:00"]) + "</body></html>"

/// Як viewAt() у JS: графік із цієї сторінки на момент iso.
private func viewAt(_ iso: String, _ html: String, file: StaticString = #filePath, line: UInt = #line) async throws -> (now: Now, view: Glance) {
    let nowMs = ms(iso)
    let now = Logic.kyivParts(ms: nowMs)
    let res = await Logic.fetchSchedule(CFG, now.ymd, { _ in html })
    XCTAssertEqual(res.status, .ok, file: file, line: line)
    guard case .ok(var sched) = res else { throw TestNetError.unexpected("графік не завантажено") }
    sched.fetchedAt = nowMs
    return (now, Logic.buildGlance(CFG, LightData(sched: sched, status: .ok), now, nowMs: nowMs))
}

final class TomorrowTests: XCTestCase {
    // outagesWord: 1 і 2–4 «відключення», решта «відключень»
    func testOutagesWordВідмінки() {
        let cases: [(Int, String)] = [(0, "відключень"), (1, "відключення"), (2, "відключення"), (4, "відключення"), (5, "відключень"),
                                      (11, "відключень"), (12, "відключень"), (14, "відключень"), (21, "відключення"), (22, "відключення"),
                                      (25, "відключень"), (111, "відключень")]
        for (n, word) in cases { XCTAssertEqual(Logic.outagesWord(n), word, "n = \(n)") }
    }

    // графік на завтра є: підсумок і дата
    func testГрафікНаЗавтраЄПідсумокІДата() async throws {
        let (now, view) = try await viewAt("2026-11-06T20:00:00+02:00", TWO_DAYS)
        XCTAssertTrue(Logic.hasTomorrow(view))
        XCTAssertEqual(Logic.tomorrowSummary(view), "2 відключення · 6 год")
        XCTAssertEqual(Logic.dateWords(Logic.addDays(now.ymd, 1)), "7 листопада")
        XCTAssertEqual(Logic.dateWords("2026-01-01"), "1 січня")
    }

    // завтра рядком: сьогодні й завтра для середнього, перше відключення для малого
    func testЗавтраРядкомСьогодніЙЗавтра() async throws {
        // Удень: сьогодні ще буде відключення, завтра два.
        let day = try await viewAt("2026-11-06T10:00:00+02:00", TWO_DAYS)
        XCTAssertEqual(Logic.todayRow(day.view), "12:00–14:00")
        XCTAssertEqual(Logic.tomorrowRow(day.view), "06:00–09:00, 15:00–18:00")
        XCTAssertEqual(Logic.tomorrowFirst(day.view), "06:00–09:00 +1")
        // Увечері сьогодні вже все минуло.
        let evening = try await viewAt("2026-11-06T20:00:00+02:00", TWO_DAYS)
        XCTAssertEqual(Logic.todayRow(evening.view), "більше немає")
        // Графіка на завтра ще немає: рядка про завтра теж.
        let (_, view) = try await viewAt("2026-11-06T20:00:00+02:00", TODAY_ONLY)
        XCTAssertFalse(Logic.hasTomorrow(view))
        XCTAssertNil(Logic.tomorrowFirst(view))
        XCTAssertEqual(Logic.tomorrowSummary(view), "Графіка ще немає")
    }

    // завтра без відключень: «без відключень» і в рядку, і в підсумку
    func testЗавтраБезВідключень() {
        var view = Glance()
        view.tomorrowRuns = [Run(s: 0, e: 1440, st: .on)]
        view.tomorrowWindows = []
        view.windowsLeft = []
        view.todayWindows = []
        XCTAssertEqual(Logic.tomorrowSummary(view), "Без відключень")
        XCTAssertEqual(Logic.tomorrowRow(view), "без відключень")
        XCTAssertEqual(Logic.tomorrowFirst(view), "без відключень")
        XCTAssertEqual(Logic.todayRow(view), "без відключень")
    }

    // «19:30 завтра» не розривається: нерозривний пробіл лише перед «завтра» після часу
    func testЗавтраНеРозриваєтьсяНерозривнийПробіл() {
        let nbsp = "\u{00A0}"
        XCTAssertEqual(Logic.keepTogether("Потім без світла до 06:00 завтра"), "Потім без світла до 06:00\(nbsp)завтра")
        XCTAssertEqual(Logic.keepTogether("Світло до 23:30"), "Світло до 23:30")
        XCTAssertEqual(Logic.keepTogether("завтра з 06:00"), "завтра з 06:00")
    }

    // дотик до значка: віджет одразу малює збережене без мережі
    func testДотикДоЗначкаЗбереженеБезМережі() async throws {
        let env = Env()
        // О 19:30 інтернет був: графік на два дні збережено.
        env.http.routes = [ZOE: .text(TWO_DAYS)]
        let online = await env.store.widgetDataAll(CFG, env.at("2026-11-06T19:30:00+02:00").now, quick: false)
        XCTAssertEqual(online.first?.data.status, .ok)
        XCTAssertFalse(env.http.requests.isEmpty)

        // О 20:00 (кеш уже старший за 10 хвилин) торкнулися значка тривоги.
        let t = env.at("2026-11-06T20:00:00+02:00")
        env.store.writePage("systemMedium|", "alert")
        let mode = AlertLogic.pageMode(env.store.readPage("systemMedium|"), AlertLogic.pagesOf(true), env.nowMs + 500)
        XCTAssertEqual(mode, PageMode(page: "alert", until: t.ms + 15 * 60000, quick: true))

        env.http.clearRequests()
        env.http.routes = [:] // мережі «немає»: будь-який запит дав би помилку
        let quickAll = await env.store.widgetDataAll(CFG, t.now, quick: mode.quick)
        let quick = try XCTUnwrap(quickAll.first)
        XCTAssertEqual(env.http.requests, [], "перемикання не ходить у мережу")
        let view = Logic.buildGlance(CFG, quick.light, t.now, nowMs: t.ms)
        XCTAssertEqual(Logic.tomorrowSummary(view), "2 відключення · 6 год")

        // Без дотику той самий застарілий кеш віджет оновлює з мережі.
        env.http.routes = [ZOE: .text(TWO_DAYS)]
        _ = await env.store.widgetDataAll(CFG, t.now, quick: false)
        XCTAssertFalse(env.http.requests.isEmpty, "планове оновлення йде в мережу")
    }
}
