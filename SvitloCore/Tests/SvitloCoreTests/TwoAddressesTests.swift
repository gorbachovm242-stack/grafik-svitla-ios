// Порт tools/scripting-two.test.mjs: друга адреса — дві черги, окреме сховище, віджет за параметром,
// сповіщення про обидві з назвами (Store.planNotifications). Дані синтетичні. Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

private let ONE = Config(region: "zaporizhzhia", group: "3.2")
private let TWO = Config(region: "zaporizhzhia", group: "3.2", second: Address(name: "Батьки", region: "zaporizhzhia", group: "4.1"))

/// Сторінка обленерго з одним дописом на 6 листопада.
private func zoePage(_ lines: [String]) -> [String: Route] { zoe(simpleToday(lines)) }

final class TwoAddressesTests: XCTestCase {
    // addressesOf: одна адреса без назви, дві з назвами; власний датчик лише в першої
    func testAddressesOfОднаБезНазвиДвіЗНазвами() {
        XCTAssertEqual(Logic.addressesOf(nil), [])
        var oneCfg = ONE
        oneCfg.svitlobot = "svitlobot_x"
        let one = Logic.addressesOf(oneCfg)
        XCTAssertEqual(one.count, 1)
        XCTAssertNil(one.first?.place)
        var twoCfg = TWO
        twoCfg.svitlobot = "svitlobot_x"
        twoCfg.svitlobotName = "Мій"
        let two = Logic.addressesOf(twoCfg)
        func describe(_ a: Config) -> String { "\(a.slot ?? -1) \(a.place ?? "nil") \(a.region) \(a.group)" }
        XCTAssertEqual(two.map(describe), ["0 Дім zaporizhzhia 3.2", "1 Батьки zaporizhzhia 4.1"])
        guard two.count == 2 else { return }
        XCTAssertEqual(two[0].svitlobot, "svitlobot_x")
        XCTAssertNil(two[1].svitlobot)
        XCTAssertNil(two[1].svitlobotName)
        // Назви за замовчуванням і своя назва першої адреси.
        var named = ONE
        named.name = "Квартира"
        named.second = Address(region: "kyiv", group: "1.1")
        XCTAssertEqual(Logic.addressesOf(named).map { $0.place }, ["Квартира", "Друга адреса"])
        // Недозаповнена друга адреса не рахується.
        var half = ONE
        half.second = Address(name: "Батьки", region: "kyiv", group: "")
        XCTAssertEqual(Logic.addressesOf(half).count, 1)
    }

    // slotFromParameter: «2», «друга» чи назва другої адреси показують другу
    func testSlotFromParameterДругаАдреса() {
        for p in ["2", " 2 ", "Друга", "друга адреса", "батьки", "Батьки"] { XCTAssertEqual(Logic.slotFromParameter(p, TWO), 1, p) }
        for p in ["", nil, "1", "дім", "xyz"] as [String?] { XCTAssertEqual(Logic.slotFromParameter(p, TWO), 0, String(describing: p)) }
        XCTAssertEqual(Logic.slotFromParameter("2", ONE), 0, "без другої адреси завжди перша")
    }

    // обидві адреси: сторінку обленерго вантажимо раз, графіки лежать окремо
    func testОбидвіАдресиСторінкаРазГрафікиОкремо() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 17:00"])
        let t = env.at("2026-11-06T10:00:00+02:00")
        let all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(env.http.requests.filter { $0 == ZOE }.count, 1, "та сама сторінка для обох адрес")
        XCTAssertEqual(env.store.readCache(0)?.key, "zaporizhzhia|3.2")
        XCTAssertEqual(env.store.readCache(1)?.key, "zaporizhzhia|4.1")
        let addresses = Logic.addressesOf(TWO)
        guard all.count == 2, addresses.count == 2 else { return }
        let v1 = Logic.buildGlance(addresses[0], all[0].data, t.now, nowMs: t.ms)
        let v2 = Logic.buildGlance(addresses[1], all[1].data, t.now, nowMs: t.ms)
        XCTAssertEqual(v1.title, "Світло до 12:00")
        XCTAssertEqual(v2.title, "Світло до 15:00")
        XCTAssertEqual(v2.place, "Батьки")
        XCTAssertEqual(Logic.captionText(v2), "Батьки · черга 4.1 · за графіком")
        // Збережене кожної адреси знаходить своє.
        XCTAssertEqual(env.store.cachedData(addresses[1]).sched?.key, "zaporizhzhia|4.1")
        XCTAssertEqual(env.store.cachedData(addresses[0]).sched?.key, "zaporizhzhia|3.2")
        // Віджет одразу після «Завтра ›» бере збережене обох адрес без мережі.
        env.http.clearRequests()
        let quick = await env.store.widgetDataAll(TWO, t.now, quick: true)
        XCTAssertEqual(env.http.requests, [])
        XCTAssertEqual(quick.map { $0.data.sched?.key }, ["zaporizhzhia|3.2", "zaporizhzhia|4.1"])
    }

    // одна адреса: як і раніше, без назв у текстах і з тими самими ключами сховища
    func testОднаАдресаБезНазвТіСаміКлючі() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00"])
        let t = env.at("2026-11-06T10:00:00+02:00")
        let all = await env.store.freshAll(ONE, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(env.store.readCache()?.key, "zaporizhzhia|3.2")
        XCTAssertNil(env.store.readCache(1))
        XCTAssertNotNil(env.kv.data(forKey: "cache"), "ключ першої адреси той самий, що й до двох адрес")
        env.notifier.update(env.store, ONE, all.map { $0.data.sched }, t.now, t.date)
        XCTAssertEqual(env.notifier.pending.map { $0.body },
                       ["Черга 3.2: відключення о 12:00, увімкнуть о 14:00", "Черга 3.2: світло о 14:00"])
    }

    // попередження про обидві адреси, з назвами, і зміна графіка другої
    func testПопередженняПроОбидвіАдресиЗНазвами() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 17:00"])
        var t = env.at("2026-11-06T10:00:00+02:00")
        var all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        env.notifier.update(env.store, TWO, all.map { $0.data.sched }, t.now, t.date)
        XCTAssertEqual(env.notifier.pending.map { $0.body }, [
            "Дім, черга 3.2: відключення о 12:00, увімкнуть о 14:00",
            "Дім, черга 3.2: світло о 14:00",
            "Батьки, черга 4.1: відключення о 15:00, увімкнуть о 17:00",
            "Батьки, черга 4.1: світло о 17:00",
        ])
        XCTAssertEqual(env.notifier.delivered.count, 0, "перше завантаження нічого не повідомляє")

        // Обленерго змінило графік лише другої черги.
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 18:00"])
        t = env.at("2026-11-06T10:20:00+02:00")
        all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        env.notifier.update(env.store, TWO, all.map { $0.data.sched }, t.now, t.date)
        XCTAssertEqual(env.notifier.delivered.map { [$0.title, $0.body] },
                       [["Графік відключень змінився", "Батьки, черга 4.1, сьогодні: 15:00–18:00"]])
        XCTAssertTrue(env.notifier.pending.contains { $0.body == "Батьки, черга 4.1: світло о 18:00" })
    }

    // перейменували другу адресу: заплановані попередження отримують нову назву
    func testПерейменувалиДругуАдресуНоваНазва() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 17:00"])
        let t = env.at("2026-11-06T10:00:00+02:00")
        let all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        let scheds = all.map { $0.data.sched }
        env.notifier.update(env.store, TWO, scheds, t.now, t.date)
        var renamed = TWO
        renamed.second?.name = "Дача"
        env.notifier.update(env.store, renamed, scheds, t.now, t.date)
        let bodies = env.notifier.pending.map { $0.body }
        XCTAssertTrue(bodies.contains { $0.hasPrefix("Дача, черга 4.1") }, bodies.joined(separator: " | "))
        XCTAssertFalse(bodies.contains { $0.hasPrefix("Батьки") })
    }

    // прибрали другу адресу: лишаються лише попередження першої, без назви
    func testПрибралиДругуАдресуЛишаєтьсяПерша() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 17:00"])
        let t = env.at("2026-11-06T10:00:00+02:00")
        var all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        env.notifier.update(env.store, TWO, all.map { $0.data.sched }, t.now, t.date)
        env.store.clearCache(1)
        env.store.forgetSecond()
        all = await env.store.freshAll(ONE, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        env.notifier.update(env.store, ONE, all.map { $0.data.sched }, t.now, t.date)
        XCTAssertEqual(env.notifier.pending.map { $0.body },
                       ["Черга 3.2: відключення о 12:00, увімкнуть о 14:00", "Черга 3.2: світло о 14:00"])
        XCTAssertNil(env.store.readCache(1))
    }

    // без інтернету обидві адреси показують збережене
    func testБезІнтернетуОбидвіАдресиЗбережене() async {
        let env = Env()
        env.http.routes = zoePage(["3.2: 12:00 - 14:00", "4.1: 15:00 - 17:00"])
        var t = env.at("2026-11-06T10:00:00+02:00")
        _ = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        env.http.routes = [:]
        t = env.at("2026-11-06T10:30:00+02:00")
        let all = await env.store.freshAll(TWO, t.now, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(all.map { "\($0.data.status.rawValue) \($0.data.sched?.key ?? "nil")" },
                       ["fail zaporizhzhia|3.2", "fail zaporizhzhia|4.1"])
    }
}
