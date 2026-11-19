// Порт tools/scripting-store.test.mjs, розділ «Кеш»: графік зі сховища й мережі (Store.getSchedule).
// Розділ «Сповіщення» того самого файла — у NotifyTests. Дані синтетичні. Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

final class StoreTests: XCTestCase {
    // протягом 10 хвилин мережу не чіпаємо, потім оновлюємо
    func testПротягом10ХвилинМережуНеЧіпаємо() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        XCTAssertEqual(env.http.requests.count, 1)
        _ = await env.refresh("2026-11-06T10:05:00+02:00")
        XCTAssertEqual(env.http.requests.count, 1)
        _ = await env.refresh("2026-11-06T10:11:00+02:00")
        XCTAssertEqual(env.http.requests.count, 2)
    }

    // кнопка «↻» оновлює одразу, навіть якщо кеш свіжий
    func testКнопкаОновитиОдразуНавітьЗіСвіжимКешем() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        _ = await env.refresh("2026-11-06T10:01:00+02:00", CFG, force: true)
        XCTAssertEqual(env.http.requests.count, 2)
    }

    // мережа зникла: працює зі збереженим, а потім чесно каже, що дані старі
    func testМережаЗниклаЗбереженеЙПозначкаСтарихДаних() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        env.http.routes = [:]
        let later = await env.refresh("2026-11-06T13:30:00+02:00")
        XCTAssertEqual(later.data.status, .fail)
        let view = Logic.buildGlance(CFG, later.data, later.now, nowMs: env.nowMs)
        XCTAssertEqual(view.title, "Без світла до 14:00")
        XCTAssertEqual(view.notice, "Дані від 10:00")
    }

    // зміна черги не використовує кеш попередньої
    func testЗмінаЧергиНеБереКешПопередньої() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00", "1.1: 10:30 - 12:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        let other = Config(region: "zaporizhzhia", group: "1.1")
        let got = await env.refresh("2026-11-06T10:02:00+02:00", other)
        XCTAssertEqual(env.http.requests.count, 2)
        XCTAssertEqual(Logic.buildGlance(other, got.data, got.now, nowMs: env.nowMs).title, "Світло до 10:30")
    }
}
