// Порт tools/scripting-offline.test.mjs: віджет без інтернету — мережа має спільний крайній строк, а віджет вчасно
// малює збережене. Дані синтетичні. Над кожним тестом — назва оригіналу.
//
// Годинник тут іде далі в реальному часі від заданого моменту (Env(ticking: true)): у JS Date.now() стояв, а крайній
// строк мережі рахували справжні таймери; у Swift Net рахує крайній строк за годинником Store.
import XCTest
@testable import SvitloCore

// Малі бюджети, щоб тест ішов швидко; співвідношення ті самі, що у віджеті (8 с на все, 5 с на джерело).
private let BUDGET: Double = 300
private let REQUEST: Double = 200
private let SLACK: Double = 400 // запас на таймери

/// Факт за чергою, ніби збережений раніше: світла немає з 12:00.
private let FACT = Fact(
    channel: Logic.queueId("zaporizhzhia", "3.2"), name: "Черга 3.2", status: .off, since: ms("2026-11-06T12:00:00+02:00"),
    lastOffMin: nil, lastOffEnd: nil, postsFor: nil, checkedAt: ms("2026-11-06T10:00:00+02:00"),
    count: QueueCount(on: 0, off: 3, total: 3)
)

private func offlinePage(_ lines: [String]) -> [String: Route] { zoe(simpleToday(lines)) }

final class OfflineTests: XCTestCase {
    /// О 10:00 інтернет був: графік і факт збережено.
    private func savedAt10(file: StaticString = #filePath, line: UInt = #line) async -> Env {
        let env = Env(ticking: true)
        env.http.routes = offlinePage(["3.2: 12:00 - 14:00"])
        let got = await env.store.freshData(CFG, env.at("2026-11-06T10:00:00+02:00").now, force: false, budgetMs: BUDGET, requestMs: REQUEST)
        XCTAssertEqual(got.data.status, .ok, file: file, line: line)
        env.store.put("fact", FACT)
        return env
    }

    // без інтернету запит висить: віджет не чекає довше за бюджет і малює збережене
    func testЗапитВиситьВіджетНеЧекаєДовшеЗаБюджет() async {
        let env = await savedAt10()
        env.http.offline = .hang
        let now = env.at("2026-11-06T13:30:00+02:00").now
        let (value, elapsed) = await timed { await env.store.freshData(CFG, now, force: false, budgetMs: BUDGET, requestMs: REQUEST) }
        XCTAssertLessThan(elapsed, BUDGET + SLACK, "чекали \(Int(elapsed)) мс")
        XCTAssertEqual(value.data.status, .fail)
        XCTAssertEqual(Logic.buildGlance(CFG, value.light, now, nowMs: env.nowMs).title, "Без світла до 14:00")
        XCTAssertEqual(value.fact, FACT)
    }

    // запит не чує скасування (iOS чекає на звʼязок): віджет усе одно малює збережене вчасно
    func testЗапитНеЧуєСкасуванняВіджетУсеОдноВчасно() async {
        let env = await savedAt10()
        env.http.offline = .deaf
        let now = env.at("2026-11-06T13:30:00+02:00").now
        let (value, elapsed) = await timed { await env.store.freshData(CFG, now, force: false, budgetMs: BUDGET, requestMs: REQUEST) }
        XCTAssertLessThan(elapsed, BUDGET + SLACK, "чекали \(Int(elapsed)) мс")
        XCTAssertEqual(Logic.buildGlance(CFG, value.data, now, nowMs: env.nowMs).title, "Без світла до 14:00")
        XCTAssertEqual(value.fact, FACT)
    }

    // режим польоту: помилка одразу, і збережене теж одразу
    func testРежимПольотуПомилкаОдразу() async {
        let env = await savedAt10()
        env.http.routes = [:]
        let now = env.at("2026-11-06T13:30:00+02:00").now
        let (value, elapsed) = await timed { await env.store.freshData(CFG, now, force: false, budgetMs: BUDGET, requestMs: REQUEST) }
        XCTAssertLessThan(elapsed, 100, "чекали \(Int(elapsed)) мс")
        XCTAssertEqual(value.data.status, .fail)
        XCTAssertEqual(Logic.buildGlance(CFG, value.data, now, nowMs: env.nowMs).title, "Без світла до 14:00")
    }

    // щойно мережі не було: віджет 5 хвилин не йде в мережу, а кнопка «↻» пробує
    func testЩойноМережіНеБулоВіджет5ХвилинНеЙдеВМережу() async {
        let env = await savedAt10()
        env.http.offline = .hang
        _ = await env.store.freshData(CFG, env.at("2026-11-06T13:30:00+02:00").now, force: false, budgetMs: BUDGET, requestMs: REQUEST)
        let before = env.http.requests.count
        let later = env.at("2026-11-06T13:34:00+02:00")
        let (value, elapsed) = await timed { await env.store.freshData(CFG, later.now, force: false, budgetMs: BUDGET, requestMs: REQUEST) }
        XCTAssertEqual(env.http.requests.count, before, "віджет не пробував мережу")
        XCTAssertLessThan(elapsed, 100, "чекали \(Int(elapsed)) мс")
        XCTAssertEqual(Logic.buildGlance(CFG, value.data, Logic.kyivParts(ms: env.nowMs), nowMs: env.nowMs).title, "Без світла до 14:00")
        _ = await env.store.freshData(CFG, env.at("2026-11-06T13:34:30+02:00").now, force: true, budgetMs: BUDGET, requestMs: REQUEST)
        XCTAssertGreaterThan(env.http.requests.count, before, "кнопка «↻» пробує мережу")
        let afterButton = env.http.requests.count
        _ = await env.store.freshData(CFG, env.at("2026-11-06T13:40:00+02:00").now, force: false, budgetMs: BUDGET, requestMs: REQUEST)
        XCTAssertGreaterThan(env.http.requests.count, afterButton, "за 5 хвилин віджет пробує знову")
    }

    // інтернет повернувся: свіжий графік, позначку «без мережі» знято
    func testІнтернетПовернувсяСвіжийГрафікПозначкуЗнято() async {
        let env = await savedAt10()
        env.http.offline = .hang
        _ = await env.store.freshData(CFG, env.at("2026-11-06T13:30:00+02:00").now, force: false, budgetMs: BUDGET, requestMs: REQUEST)
        XCTAssertNotNil(env.kv.data(forKey: "offline"))
        env.http.offline = .online
        env.http.routes = offlinePage(["3.2: 12:00 - 15:00"])
        let now = env.at("2026-11-06T13:36:00+02:00").now
        let got = await env.store.freshData(CFG, now, force: false, budgetMs: BUDGET, requestMs: REQUEST)
        XCTAssertEqual(got.data.status, .ok)
        XCTAssertEqual(Logic.buildGlance(CFG, got.data, now, nowMs: env.nowMs).title, "Без світла до 15:00")
        XCTAssertNil(env.kv.data(forKey: "offline"))
    }

    // сторінка налаштувань одразу має збережене своєї черги, чуже не підставляє
    func testНалаштуванняМаютьЗбереженеСвоєїЧерги() async {
        let env = await savedAt10()
        let other = Config(region: "zaporizhzhia", group: "1.1")
        XCTAssertNotNil(env.store.cachedData(CFG).sched)
        XCTAssertNil(env.store.cachedData(other).sched)
        XCTAssertNil(env.store.cachedData(nil).sched)
        XCTAssertEqual(env.store.cachedFact(CFG), FACT)
        XCTAssertNil(env.store.cachedFact(other))
    }
}
