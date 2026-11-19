// Порт tools/scripting-fact.test.mjs: фактичний стан із датчика СвітлоБота (Fact.swift). Усі канали, адреси й дописи вигадані.
// Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

/// Рядок списку каналів: стан;&;час зміни;&;назва;&;канал;&;кількість[;&;широта;&;довгота].
private func line(_ code: Int, _ iso: String, _ name: String, _ id: String, _ users: Int, _ geo: String = "") -> String {
    "\(code);&;\(iso);&;\(name);&;\(id);&;\(users)\(geo)"
}

private let LIST = [
    line(1, "2026-11-09T08:10:00+00:00", "Тестове -> Каштанова 7", "svitlobot_test_kashtan7", 41),
    line(2, "2026-11-09T04:53:00+00:00", "Тестове -> Каштанова 9", "svitlobot_test_kashtan9", 6, ";&;47.8;&;35.1"),
    line(3, "2026-10-01T10:00:00+00:00", "Інше місто -> Зав'язана 1", "svitlobot_test_other", 3),
    "зламаний рядок",
    line(1, "не дата", "Тестове -> Без часу", "svitlobot_test_notime", 1),
    line(1, "2026-11-09T08:10:00+00:00", "Погана назва", "погана назва", 5),
].joined(separator: "\n")

private func fact(
    channel: String = "svitlobot_test_kashtan7", name: String = "Тестове, Каштанова 7", status: FactStatus = .on,
    since: Millis? = ms("2026-11-09T08:10:00Z"), lastOffMin: Int? = nil, lastOffEnd: Millis? = nil, postsFor: Millis? = nil,
    checkedAt: Millis = ms("2026-11-09T08:12:00Z"), count: QueueCount? = nil
) -> Fact {
    Fact(channel: channel, name: name, status: status, since: since, lastOffMin: lastOffMin, lastOffEnd: lastOffEnd,
         postsFor: postsFor, checkedAt: checkedAt, count: count)
}

/// Сторінка t.me/s: текст допису й час окремими блоками, апостроф закодовано.
private func tgPage(_ posts: [(String, String)]) -> String {
    let items = posts.map { iso, text in
        "<div class=\"tgme_widget_message_wrap\"><div class=\"tgme_widget_message_text js-message_text\" dir=\"auto\"><i class=\"emoji\"><b>🟢</b></i> \(text)</div>\n"
            + "<div class=\"tgme_widget_message_footer\"><a class=\"tgme_widget_message_date\" href=\"#\"><time datetime=\"\(iso)\" class=\"time\">x</time></a></div></div>"
    }
    return "<html><body>\(items.joined(separator: "\n"))</body></html>"
}

/// Список для мапи СвітлоБота: з розкладом (чергою) і координатами.
private func mapLine(_ code: Int, _ iso: String, _ name: String, _ id: String, _ users: Int, _ queue: String) -> String {
    ["-1", "\(code)", iso, name, id, "\(users)", "47.8", "35.1", "0", queue, "1", ""].joined(separator: ";&&&;")
}

private let MAP_LINES = [
    mapLine(1, "2026-11-09T08:10:00+00:00", "Тестове -> Каштанова 7", "svitlobot_q1", 41, "Запорізька обл. — група 3.2"),
    mapLine(1, "2026-11-09T08:14:00+00:00", "Тестове -> Каштанова 9", "svitlobot_q2", 6, "Запорізька обл. — група 3.2"),
    mapLine(1, "2026-11-09T08:12:00+00:00", "Тестове -> Липова 1", "svitlobot_q3", 3, "Запорізька обл. — група 3,2"),
    mapLine(2, "2026-11-09T04:53:00+00:00", "Тестове -> Липова 5", "svitlobot_q4", 2, "Запорізька обл. — група 3.2"),
    mapLine(3, "2026-10-01T10:00:00+00:00", "Тестове -> Липова 9", "svitlobot_q5", 2, "Запорізька обл. — група 3.2"),
    mapLine(2, "2026-11-09T07:00:00+00:00", "Тестове -> Інша черга", "svitlobot_q6", 2, "Запорізька обл. — група 3.1"),
    mapLine(1, "2026-11-09T07:00:00+00:00", "Київ -> Тестова 1", "svitlobot_k1", 9, "Група 4.1"),
    mapLine(2, "2026-11-09T07:00:00+00:00", "Буча -> Тестова 1", "svitlobot_k2", 9, "Київська обл. — група 4.1"),
    mapLine(1, "2026-11-09T07:00:00+00:00", "Без розкладу", "svitlobot_none", 9, "-"),
]
private let MAP = MAP_LINES.joined(separator: "\n")

private func channel(_ status: FactStatus, _ iso: String) -> Channel {
    Channel(id: "svitlobot_test_kashtan7", name: "Тестове, Каштанова 7", status: status, since: ms(iso), users: 40, queue: nil)
}

private func factGlance(_ kind: FactStatus) -> FactGlance {
    FactGlance(kind: kind, full: "", line: "", short: "", timerFrom: nil, checked: nil)
}

final class FactTests: XCTestCase {
    // список каналів: стан, час зміни, назва зі стрілкою, кількість; зламані рядки пропущено
    func testСписокКаналівЗламаніРядкиПропущено() {
        let list = Logic.parseChannels(LIST)
        XCTAssertEqual(list.map { $0.id }, ["svitlobot_test_kashtan7", "svitlobot_test_kashtan9", "svitlobot_test_other", "svitlobot_test_notime"])
        guard list.count == 4 else { return }
        XCTAssertEqual(list[0], Channel(id: "svitlobot_test_kashtan7", name: "Тестове, Каштанова 7", status: .on,
                                        since: ms("2026-11-09T08:10:00Z"), users: 40, queue: nil))
        XCTAssertEqual(list[1].status, .off)
        XCTAssertEqual(list[2].status, .unknown)
        XCTAssertNil(list[3].since)
        XCTAssertEqual(Logic.parseChannels(line(1, "2026-11-09T08:10:00+00:00", "м. Тестове, -> Липова 3", "svitlobot_test_lyp", 2)).first?.name,
                       "м. Тестове, Липова 3")
    }

    // канал можна вставити посиланням, @назвою чи назвою; сміття не приймаємо
    func testКаналПосиланнямНазвоюСміттяНі() {
        for input in ["https://t.me/svitlobot_test", "t.me/s/svitlobot_test", "@svitlobot_test", " svitlobot_test ",
                      "https://telegram.me/svitlobot_test?start=1", "https://t.me/s/svitlobot_test/123"] {
            XCTAssertEqual(Logic.channelId(input), "svitlobot_test", input)
        }
        for input in ["", "Каштанова 7", "https://example.com/", "abc"] { XCTAssertEqual(Logic.channelId(input), "", input) }
    }

    // пошук за вулицею: усі слова, без огляду на регістр і апостроф; більші канали вище
    func testПошукЗаВулицеюУсіСлова() {
        let list = Logic.parseChannels(LIST)
        XCTAssertEqual(Logic.searchChannels(list, "каштанова").map { $0.id }, ["svitlobot_test_kashtan7", "svitlobot_test_kashtan9"])
        XCTAssertEqual(Logic.searchChannels(list, "КАШТАНОВА 9").map { $0.id }, ["svitlobot_test_kashtan9"])
        XCTAssertEqual(Logic.searchChannels(list, "завязана").map { $0.id }, ["svitlobot_test_other"])
        XCTAssertEqual(Logic.searchChannels(list, "https://t.me/svitlobot_test_kashtan9").map { $0.id }, ["svitlobot_test_kashtan9"])
        XCTAssertEqual(Logic.searchChannels(list, "каштанова", limit: 1).map { $0.id }, ["svitlobot_test_kashtan7"])
        XCTAssertEqual(Logic.searchChannels(list, "  "), [])
        XCTAssertEqual(Logic.searchChannels(list, "неіснуюча"), [])
    }

    // тривалість із допису: години, хвилини, дні
    func testТривалістьІзДопису() {
        XCTAssertEqual(Logic.durationMin("3год 17хв"), 197)
        XCTAssertEqual(Logic.durationMin("6хв"), 6)
        XCTAssertEqual(Logic.durationMin("2год"), 120)
        XCTAssertEqual(Logic.durationMin("1д 2год"), 1560)
        XCTAssertNil(Logic.durationMin("нічого"))
    }

    // дописи каналу: беремо лише «Світло з'явилося» з тривалістю та часом допису
    func testДописиКаналуЛишеСвітлоЗявилося() {
        let html = tgPage([
            ("2026-11-09T04:57:00+00:00", "06:53 Світло зникло 🕓 Воно було 17год 3хв 🗓️ Очікуємо за розкладом о 10:30"),
            ("2026-11-09T08:10:40+00:00",
             "10:10 Світло з&#39;явилося <i class=\"emoji\"><b>🕓</b></i> Його не було 3год 17хв <i class=\"emoji\"><b>🗓️</b></i> Наступне планове: 14:30 - 19:30"),
            ("2026-11-09T09:00:00+00:00", "Розклад на сьогодні: 14:30 - 19:30 (5 год.)"),
            ("2026-11-09T12:00:00+00:00", "14:00 Світло з&#39;явилося 🕓 Його не було 6хв"),
        ])
        XCTAssertEqual(Logic.parseComebacks(html), [
            Comeback(at: ms("2026-11-09T08:10:40Z"), offMin: 197),
            Comeback(at: ms("2026-11-09T12:00:00Z"), offMin: 6),
        ])
        XCTAssertEqual(Logic.parseComebacks("<html>інша сторінка</html>"), [])
    }

    // свій канал без модерації: стан і час зміни з дописів, час — із тексту, а не з допису
    func testСвійКаналСтанІЧасЗДописів() {
        let html = tgPage([
            ("2026-11-09T04:57:11+00:00", "06:53 Світло зникло 🕓 Воно було 17год 3хв 🗓️ Очікуємо за розкладом о 10:30"),
            ("2026-11-09T05:30:00+00:00", "Розклад на сьогодні: 14:30 - 19:30 (5 год.)"),
            ("2026-11-09T08:10:40+00:00", "10:10 Світло з&#39;явилося 🕓 Його не було 3год 17хв"),
            ("2026-11-09T22:01:00+00:00", "23:58 Світло зникло 🕓 Воно було 13год 48хв"),
        ])
        XCTAssertEqual(Logic.parseStatusPosts(html), [
            StatusPost(at: ms("2026-11-09T04:57:11Z"), status: .off, since: ms("2026-11-09T04:53:00Z"), offMin: nil),
            StatusPost(at: ms("2026-11-09T08:10:40Z"), status: .on, since: ms("2026-11-09T08:10:00Z"), offMin: 197),
            StatusPost(at: ms("2026-11-09T22:01:00Z"), status: .off, since: ms("2026-11-09T21:58:00Z"), offMin: nil),
        ])
    }

    // факт свого каналу з дописів: останній стан, «скільки не було» від бота або від попереднього «зникло»
    func testФактСвогоКаналуЗДописів() {
        let off = StatusPost(at: ms("2026-11-09T04:57:00Z"), status: .off, since: ms("2026-11-09T04:53:00Z"), offMin: nil)
        let onBot = StatusPost(at: ms("2026-11-09T08:11:00Z"), status: .on, since: ms("2026-11-09T08:10:00Z"), offMin: 197)
        var onBare = onBot
        onBare.offMin = nil
        let f = Logic.postsFact([onBot, off], "svitlobot_my", "Мій дім", ms("2026-11-09T08:20:00Z"))
        XCTAssertEqual(f?.status, .on)
        XCTAssertEqual(f?.since, ms("2026-11-09T08:10:00Z"))
        XCTAssertEqual(f?.lastOffMin, 197)
        XCTAssertEqual(Logic.postsFact([off, onBare], "svitlobot_my", "Мій дім", 0)?.lastOffMin, 197)
        XCTAssertNil(Logic.postsFact([onBare], "svitlobot_my", "Мій дім", 0)?.lastOffMin)
        XCTAssertEqual(Logic.postsFact([off], "svitlobot_my", "Мій дім", 0)?.status, .off)
        XCTAssertNil(Logic.postsFact([], "svitlobot_my", "Мій дім", 0))
    }

    // бачили початок відключення: «скільки не було» точне й тримається, доки світло є
    func testБачилиПочатокТривалістьТочна() {
        let id = "svitlobot_test_kashtan7"
        let off = Logic.mergeFact(nil, channel(.off, "2026-11-09T04:53:00Z"), id, ms("2026-11-09T05:00:00Z"))
        XCTAssertEqual(off.status, .off)
        XCTAssertNil(off.lastOffMin)
        let on = Logic.mergeFact(off, channel(.on, "2026-11-09T08:10:00Z"), id, ms("2026-11-09T08:15:00Z"))
        XCTAssertEqual(on.lastOffMin, 197)
        XCTAssertEqual(on.lastOffEnd, ms("2026-11-09T08:10:00Z"))
        let later = Logic.mergeFact(on, channel(.on, "2026-11-09T08:10:00Z"), id, ms("2026-11-09T09:00:00Z"))
        XCTAssertEqual(later.lastOffMin, 197)
        let offAgain = Logic.mergeFact(later, channel(.off, "2026-11-09T12:30:00Z"), id, ms("2026-11-09T12:40:00Z"))
        XCTAssertEqual(offAgain.status, .off)
        // Наступне ввімкнення без пропусків: рахуємо від нового вимкнення, а не від старого.
        let back = Logic.mergeFact(offAgain, channel(.on, "2026-11-09T14:00:00Z"), id, ms("2026-11-09T14:05:00Z"))
        XCTAssertEqual(back.lastOffMin, 90)
    }

    // початку відключення не бачили: тривалість невідома, шукаємо в дописах один раз
    func testПочаткуНеБачилиШукаємоВДописахОдинРаз() {
        let ch = channel(.on, "2026-11-09T08:10:00Z")
        let first = Logic.mergeFact(nil, ch, "svitlobot_test_kashtan7", ms("2026-11-09T08:20:00Z"))
        XCTAssertNil(first.lastOffMin)
        XCTAssertTrue(Logic.needsPosts(first))
        let far = Logic.withComeback(first, [Comeback(at: ms("2026-11-09T07:30:00Z"), offMin: 50)])
        XCTAssertNil(far.lastOffMin, "допис на 40 хв раніше належить іншому ввімкненню")
        XCTAssertFalse(Logic.needsPosts(far), "вдруге ту саму сторінку не тягнемо")
        let hit = Logic.withComeback(first, [Comeback(at: ms("2026-11-09T08:10:40Z"), offMin: 197)])
        XCTAssertEqual(hit.lastOffMin, 197)
        // Інший канал у сховищі не заважає.
        let other = Logic.mergeFact(fact(channel: "svitlobot_test_kashtan9", status: .off, since: ms("2026-11-09T04:00:00Z")), ch,
                                    "svitlobot_test_kashtan7", ms("2026-11-09T08:20:00Z"))
        XCTAssertNil(other.lastOffMin)
    }

    // каналу більше немає в списку: стан «missing», попередня тривалість не губиться
    func testКаналуНемаєMissingТривалістьНеГубиться() {
        let gone = Logic.mergeFact(fact(lastOffMin: 197, lastOffEnd: ms("2026-11-09T08:10:00Z")), nil, "svitlobot_test_kashtan7",
                                   ms("2026-11-09T09:00:00Z"))
        XCTAssertEqual(gone.status, .missing)
        XCTAssertEqual(gone.lastOffMin, 197)
    }

    // рядки для віджета й налаштувань
    func testРядкиДляВіджетаЙНалаштувань() {
        let n = kyivNow("2026-11-09T10:20:00+02:00")
        let t = ms("2026-11-09T10:20:00+02:00")
        let on = Logic.factView(fact(lastOffMin: 197, lastOffEnd: ms("2026-11-09T08:10:00Z")), n, t)
        XCTAssertEqual(on?.full, "Світло є з 10:10 · не було 3 год 17 хв")
        XCTAssertEqual(on?.line, "Світло є · не було 3 год 17 хв")
        XCTAssertEqual(on?.short, "не було 3 год 17 хв")
        XCTAssertNotNil(on)
        XCTAssertNil(on?.timerFrom)
        XCTAssertEqual(Logic.factView(fact(), n, t)?.line, "Світло є з 10:10")
        let off = Logic.factView(fact(status: .off, since: ms("2026-11-09T04:53:00Z")), n, t)
        XCTAssertEqual(off?.line, "Світла немає з 06:53")
        XCTAssertEqual(off?.short, "немає з 06:53")
        XCTAssertEqual(off?.timerFrom, ms("2026-11-09T04:53:00Z"))
        XCTAssertEqual(Logic.factView(fact(status: .off, since: ms("2026-11-08T20:15:00Z")), n, t)?.line, "Світла немає з 08.11 22:15")
        XCTAssertEqual(Logic.factView(fact(status: .unknown, since: ms("2026-11-09T07:00:00Z")), n, t)?.line, "Датчик мовчить з 09:00")
        XCTAssertEqual(Logic.factView(fact(status: .missing, since: nil), n, t)?.line, "Немає даних від датчика")
        XCTAssertNil(Logic.factView(nil, n, t))
    }

    // старі дані датчика: показуємо час перевірки, живий таймер не запускаємо
    func testСтаріДаніДатчикаЧасПеревіркиБезТаймера() {
        let n = kyivNow("2026-11-09T12:20:00+02:00")
        let v = Logic.factView(fact(status: .off, since: ms("2026-11-09T04:53:00Z"), checkedAt: ms("2026-11-09T08:09:00Z")), n,
                               ms("2026-11-09T12:20:00+02:00"))
        XCTAssertEqual(v?.checked, "дані 10:09")
        XCTAssertNotNil(v)
        XCTAssertNil(v?.timerFrom)
        let fresh = Logic.factView(fact(), n, ms("2026-11-09T10:30:00+02:00"))
        XCTAssertNotNil(fresh)
        XCTAssertNil(fresh?.checked)
    }

    // тривалість словами
    func testТривалістьСловами() {
        XCTAssertEqual(Logic.durationText(45), "45 хв")
        XCTAssertEqual(Logic.durationText(60), "1 год")
        XCTAssertEqual(Logic.durationText(197), "3 год 17 хв")
        XCTAssertEqual(Logic.durationText(1500), "1 дн 1 год")
        XCTAssertEqual(Logic.durationText(2880), "2 дн")
    }

    // список для мапи: черга з розкладу, «-» означає без черги
    func testСписокДляМапиЧергаЗРозкладу() {
        let list = Logic.parseChannels(MAP)
        XCTAssertEqual(list.count, 9)
        guard list.count == 9 else { return }
        XCTAssertEqual(list[0], Channel(id: "svitlobot_q1", name: "Тестове, Каштанова 7", status: .on, since: ms("2026-11-09T08:10:00Z"),
                                        users: 40, queue: "Запорізька обл. — група 3.2"))
        XCTAssertNil(list[8].queue)
    }

    // черга датчика: регіон і номер, у Києві без префікса
    func testЧергаДатчикаРегіонІНомер() {
        let list = Logic.parseChannels(MAP)
        func ids(_ region: String, _ group: String) -> [String] { list.filter { Logic.inQueue($0, region, group) }.map { $0.id } }
        XCTAssertEqual(ids("zaporizhzhia", "3.2"), ["svitlobot_q1", "svitlobot_q2", "svitlobot_q3", "svitlobot_q4", "svitlobot_q5"])
        XCTAssertEqual(ids("zaporizhzhia", "3.1"), ["svitlobot_q6"])
        XCTAssertEqual(ids("kyiv", "4.1"), ["svitlobot_k1"])
        XCTAssertEqual(ids("kyiv-oblast", "4.1"), ["svitlobot_k2"])
        XCTAssertEqual(ids("volyn", "3.2"), [])
    }

    // факт черги: що в більшості, медіанний час зміни; датчик, що мовчить, не рахується
    func testФактЧергиБільшістьІМедіана() {
        let list = Logic.parseChannels(MAP)
        let q = Logic.queueChannel(list, "zaporizhzhia", "3.2")
        XCTAssertEqual(q?.count, QueueCount(on: 3, off: 1, total: 4))
        XCTAssertEqual(q?.channel.status, .on)
        XCTAssertEqual(q?.channel.since, ms("2026-11-09T08:12:00Z"))
        XCTAssertEqual(q?.channel.id, "queue:zaporizhzhia:3.2")
        // Порівну: «по-різному».
        let half = Logic.parseChannels([MAP_LINES[0], MAP_LINES[3]].joined(separator: "\n"))
        XCTAssertEqual(Logic.queueChannel(half, "zaporizhzhia", "3.2")?.channel.status, .unknown)
        XCTAssertNil(Logic.queueChannel(list, "zaporizhzhia", "6.2"))
    }

    // факт черги памʼятає «скільки не було», хоч середній час зміни трохи гуляє
    func testФактЧергиПамятаєТривалість() throws {
        let offList = Logic.parseChannels([
            mapLine(2, "2026-11-09T04:53:00+00:00", "А", "svitlobot_a", 2, "Запорізька обл. — група 3.2"),
            mapLine(2, "2026-11-09T04:55:00+00:00", "Б", "svitlobot_b", 2, "Запорізька обл. — група 3.2"),
        ].joined(separator: "\n"))
        let off = try XCTUnwrap(Logic.queueFact(nil, offList, "zaporizhzhia", "3.2", ms("2026-11-09T06:00:00Z")))
        XCTAssertEqual(off.status, .off)
        func onAt(_ a: String, _ b: String) -> [Channel] {
            Logic.parseChannels([
                mapLine(1, a, "А", "svitlobot_a", 2, "Запорізька обл. — група 3.2"),
                mapLine(1, b, "Б", "svitlobot_b", 2, "Запорізька обл. — група 3.2"),
            ].joined(separator: "\n"))
        }
        let on = try XCTUnwrap(Logic.queueFact(off, onAt("2026-11-09T08:10:00+00:00", "2026-11-09T08:12:00+00:00"), "zaporizhzhia", "3.2",
                                               ms("2026-11-09T08:20:00Z")))
        XCTAssertEqual(on.status, .on)
        XCTAssertEqual(on.lastOffMin, 197)
        var later = try XCTUnwrap(Logic.queueFact(on, onAt("2026-11-09T08:10:00+00:00", "2026-11-09T08:16:00+00:00"), "zaporizhzhia", "3.2",
                                                  ms("2026-11-09T09:00:00Z")))
        XCTAssertEqual(later.lastOffMin, 197, "медіана зсунулася на 4 хв: те саме ввімкнення")
        later.lastOffMin = nil
        XCTAssertFalse(Logic.needsPosts(later), "для черги дописів не шукаємо")
    }

    // рядки факту черги: за скількома датчиками і «по-різному»
    func testРядкиФактуЧерги() {
        let n = kyivNow("2026-11-09T10:20:00+02:00")
        let t = ms("2026-11-09T10:20:00+02:00")
        let q = fact(channel: "queue:zaporizhzhia:3.2", name: "черга 3.2", lastOffMin: 197, count: QueueCount(on: 4, off: 1, total: 5))
        XCTAssertEqual(Logic.factView(q, n, t)?.full, "Світло є з 10:10 · не було 3 год 17 хв (за 5 датчиками черги)")
        XCTAssertEqual(Logic.factView(q, n, t)?.line, "Світло є · не було 3 год 17 хв")
        var many = q
        many.count = QueueCount(on: 1, off: 0, total: 21)
        XCTAssertEqual(Logic.factView(many, n, t)?.full.hasSuffix("(за 21 датчиком черги)"), true)
        var mixedFact = q
        mixedFact.status = .unknown
        mixedFact.count = QueueCount(on: 3, off: 4, total: 7)
        let mixed = Logic.factView(mixedFact, n, t)
        XCTAssertEqual(mixed?.full, "У черзі по-різному: світло є в 3 з 7")
        XCTAssertEqual(mixed?.short, "по-різному")
    }

    // екран блокування: замість батареї лампочка; лампочка вірить датчику більше, ніж графіку
    func testЛампочкаВіритьДатчикуБільшеЗаГрафік() {
        XCTAssertEqual(Logic.lockLookOf("battery"), "bulb")
        XCTAssertEqual(Logic.lockLookOf(nil), "bulb")
        XCTAssertEqual(Logic.lockLookOf("house"), "house")
        XCTAssertEqual(Logic.lockLookOf("щось"), "bulb")
        func view(_ kind: LightKind, _ fact: FactStatus?) -> Glance {
            var v = Glance()
            v.kind = kind
            v.fact = fact.map(factGlance)
            return v
        }
        XCTAssertEqual(Logic.bulbState(view(.off, .on)), .on)
        XCTAssertEqual(Logic.bulbState(view(.on, .off)), .off)
        XCTAssertEqual(Logic.bulbState(view(.on, .unknown)), .on)
        XCTAssertEqual(Logic.bulbState(view(.off, nil)), .off)
        XCTAssertEqual(Logic.bulbState(view(.maybe, nil)), .maybe)
    }

    // з датчиком віджет просить оновлення раз на 15 хв, без нього раз на 30
    func testЗДатчикомОновленняРазНа15Хв() {
        let cfg = Config(region: "zaporizhzhia", group: "3.2", svitlobot: "svitlobot_test_kashtan7")
        let date = Date(ms: ms("2026-11-09T10:20:00+02:00"))
        let n = Logic.kyivParts(date)
        let withFact = Logic.buildGlance(cfg, LightData(sched: nil, status: .fail, fact: fact()), n, nowMs: date.ms)
        XCTAssertEqual(withFact.fact?.kind, .on)
        XCTAssertEqual(Logic.refreshDate(withFact, n, date).ms - date.ms, 15 * MIN)
        let plain = Logic.buildGlance(cfg, LightData(sched: nil, status: .fail), n, nowMs: date.ms)
        XCTAssertNil(plain.fact)
        XCTAssertEqual(Logic.refreshDate(plain, n, date).ms - date.ms, 30 * MIN)
    }
}
