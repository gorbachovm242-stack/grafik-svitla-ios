// Порт tools/scripting-store.test.mjs, розділ «Сповіщення»: тепер це план Store.planNotifications, який застосовує
// FakeNotifier (як updateNotifications у notifications.ts на заглушці). Дані синтетичні. Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

final class NotifyTests: XCTestCase {
    // лише три види сповіщень і жодного іншого
    func testЛишеТриВидиСповіщень() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00, 18:00 - 20:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        let titles = Set(env.notifier.pending.map { $0.title })
        XCTAssertEqual(titles.sorted(), ["Через 10 хв вимкнуть світло", "Через 10 хв увімкнуть світло"])
        XCTAssertEqual(env.notifier.pending.count, 4)
        XCTAssertEqual(env.notifier.delivered.count, 0, "перше завантаження нічого не повідомляє")
        guard let first = env.notifier.pending.first else { return XCTFail("нічого не заплановано") }
        // У JS: first.trigger.timeInterval — секунди від «зараз» до показу.
        let nowSeconds: Double = env.nowMs / 1000
        let interval: Double = first.fireAt.timeIntervalSince1970 - nowSeconds
        let expected: Int = (11 * 60 + 50 - 10 * 60) * 60
        XCTAssertEqual(interval, Double(expected))
    }

    // той самий набір не переставляється при кожному оновленні віджета
    func testТойСамийНабірНеПереставляється() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        let before = env.notifier.pending
        let replacements = env.notifier.replacements
        let again = await env.refresh("2026-11-06T10:20:00+02:00")
        XCTAssertNil(again.plan.replace, "набір не мінявся, тож і сповіщення ті самі")
        XCTAssertNil(again.plan.signature)
        XCTAssertEqual(env.notifier.replacements, replacements)
        XCTAssertEqual(env.notifier.pending, before)
    }

    // графік змінився: одразу сповіщення, а заплановані замінено
    func testГрафікЗмінивсяОдразуСповіщенняЗапланованіЗамінено() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        env.http.routes = zoe(simpleToday(["3.2: 15:00 - 17:00"]))
        _ = await env.refresh("2026-11-06T10:20:00+02:00")
        XCTAssertEqual(env.notifier.delivered.map { [$0.title, $0.body] }, [["Графік відключень змінився", "Черга 3.2, сьогодні: 15:00–17:00"]])
        XCTAssertEqual(env.notifier.pending.map { $0.body }, ["Черга 3.2: відключення о 15:00, увімкнуть о 17:00", "Черга 3.2: світло о 17:00"])
    }

    // зʼявився графік на завтра: сповіщення про новий графік
    func testЗявивсяГрафікНаЗавтраНовийГрафік() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T18:00:00+02:00")
        env.http.routes = zoe(simpleTomorrow(["3.2: 06:00 - 11:00"]), simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T19:00:00+02:00")
        XCTAssertEqual(env.notifier.delivered.map { $0.title }, ["Новий графік відключень"])
    }

    // вимкнене сповіщення про зміну мовчить, а попередження лишаються
    func testВимкненеСповіщенняПроЗмінуМовчить() async {
        let env = Env()
        let cfg = Config(region: "zaporizhzhia", group: "3.2", notifyChange: false)
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00", cfg)
        env.http.routes = zoe(simpleToday(["3.2: 15:00 - 17:00"]))
        _ = await env.refresh("2026-11-06T10:20:00+02:00", cfg)
        XCTAssertEqual(env.notifier.delivered.count, 0)
        XCTAssertEqual(env.notifier.pending.count, 2)
    }

    // усі три вимкнено: жодного сповіщення, заплановані прибрано
    func testУсіТриВимкненоЗапланованіПрибрано() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        XCTAssertEqual(env.notifier.pending.count, 2)
        let off = Config(region: "zaporizhzhia", group: "3.2", notifyChange: false, notifyOff: false, notifyOn: false)
        env.http.routes = zoe(simpleToday(["3.2: 15:00 - 17:00"]))
        _ = await env.refresh("2026-11-06T10:20:00+02:00", off)
        XCTAssertEqual(env.notifier.pending.count, 0)
        XCTAssertEqual(env.notifier.delivered.count, 0)
    }

    // нова черга не вважається «зміною графіка»
    func testНоваЧергаНеЗмінаГрафіка() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00", "1.1: 08:00 - 09:00"]))
        _ = await env.refresh("2026-11-06T07:00:00+02:00")
        _ = await env.refresh("2026-11-06T07:05:00+02:00", Config(region: "zaporizhzhia", group: "1.1"), force: true)
        XCTAssertEqual(env.notifier.delivered.count, 0)
    }

    // скидання прибирає заплановані й памʼять про графік
    func testСкиданняПрибираєЗапланованіЙПамять() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        _ = await env.refresh("2026-11-06T10:00:00+02:00")
        env.notifier.reset(env.store)
        XCTAssertEqual(env.notifier.pending.count, 0)
        XCTAssertNil(env.kv.data(forKey: "known"))
        XCTAssertNil(env.kv.data(forKey: "planned"))
        // Позначки набору вже немає: наступне оновлення ставить попередження знову.
        let again = await env.refresh("2026-11-06T10:20:00+02:00")
        XCTAssertNotNil(again.plan.replace)
        XCTAssertEqual(env.notifier.pending.count, 2)
    }

    // Нове для Swift: набір запамʼятовується лише після commitPlanned (його кличе Notifier, коли сповіщення поставлено).
    func testБезCommitPlannedНабірСтавитьсяЗнову() async {
        let env = Env()
        env.http.routes = zoe(simpleToday(["3.2: 12:00 - 14:00"]))
        let t = env.at("2026-11-06T10:00:00+02:00")
        let data = await env.store.getSchedule(CFG, t.now, force: false)
        let first = env.store.planNotifications(CFG, [data.sched], t.now, t.date)
        XCTAssertEqual(first.replace?.count, 2)
        let second = env.store.planNotifications(CFG, [data.sched], t.now, t.date)
        XCTAssertEqual(second.replace?.count, 2, "без commitPlanned набір не запамʼятовано")
        XCTAssertEqual(second.signature, first.signature)
        env.store.commitPlanned(second.signature ?? "")
        let third = env.store.planNotifications(CFG, [data.sched], t.now, t.date)
        XCTAssertNil(third.replace)
    }
}
