// Порт tools/scripting-logic.test.mjs: логіка графіка (logic.ts → Logic.swift). Усі дані синтетичні.
// Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

private let PREFS = NotifyPrefs(change: true, off: true, on: true)

/// «off 12:50»: вид і час кожного попередження.
private func kinds(_ items: [Planned]) -> [String] { items.map { "\($0.kind.rawValue) \(Logic.hm($0.triggerMin))" } }

/// Як known() у JS: завантажити графік і порахувати відомі вікна.
private func known(_ prev: Known?, _ now: String, _ lines: [String], _ extraPosts: [String] = [],
                   file: StaticString = #filePath, line: UInt = #line) async throws -> (known: Known, now: Now) {
    let s = await scenario(now: now, routes: [ZOE: .text(pageOf(extraPosts + [today(lines)]))])
    let sched = try XCTUnwrap(s.sched, "графік не завантажено", file: file, line: line)
    return (Logic.knownWindows(prev, sched, s.now), s.now)
}

private func glance(_ kind: LightKind, change: Int?, from: Int?, nowMin: Int) -> Glance {
    var view = Glance()
    view.kind = kind
    view.changeMin = change
    view.runFrom = from
    view.nowMin = nowMin
    return view
}

final class LogicTests: XCTestCase {
    // MARK: - Читання сайту обленерго

    // розбирає час, зокрема кінець доби 24:00
    func testРозбираєЧасЗокремаКінецьДоби() {
        let r = Logic.parseRanges("00:00 – 02:00, 06:00 – 11:00, 22:30 – 24:00")
        XCTAssertTrue(r.exact)
        XCTAssertEqual(r.ranges.map { [$0.0, $0.1] }, [[0, 120], [360, 660], [1350, 1440]])
    }

    // час, який не вдалося прочитати, не зникає мовчки
    func testНепрочитанийЧасНеЗникаєМовчки() {
        XCTAssertFalse(Logic.parseRanges("22:00 – 02:00").exact)
        XCTAssertFalse(Logic.parseRanges("06:00 – 11:00, 15:00").exact)
    }

    // для дати береться найновіший допис
    func testДляДатиБеретьсяНайновішийДопис() {
        let posts = Logic.parsePosts(page(
            post("ОНОВЛЕНО ГПВ НА 6 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ (оновлено 21:25)", ["3.2: 12:00 - 14:00"]),
            today(["3.2: 04:30 - 09:30"])
        ))
        let day = Logic.dayFromPosts(posts, "2026-11-06", "3.2")
        XCTAssertEqual(day?.runs.filter { $0.st == .off }.map { [$0.s, $0.e] }, [[720, 840]])
    }

    // черга, якої немає в дописі, цього дня без відключень
    func testЧергаЯкоїНемаєВДописіБезВідключень() {
        let day = Logic.dayFromPosts(Logic.parsePosts(page(today(["1.1: 12:00 - 16:00"]))), "2026-11-06", "3.2")
        XCTAssertEqual(day?.runs.map { $0.st }, [.on])
    }

    // допис для бізнесу не вважається графіком для населення
    func testДописДляБізнесуНеГрафік() {
        let posts = Logic.parsePosts(page(post("ДО УВАГИ ПРОМИСЛОВОСТІ ТА БІЗНЕСУ 6 ЛИСТОПАДА", ["Обмеження не стосуються населення"])))
        XCTAssertNil(Logic.dayFromPosts(posts, "2026-11-06", "3.2"))
    }

    // допис про ГПВ без рядків із чергами потребує перевірки, а не означає «світло є»
    func testДописБезРядківЧергПотребуєПеревірки() {
        let posts = Logic.parsePosts(page(post("ОНОВЛЕНО ГПВ НА 6 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ", ["Деталі буде повідомлено згодом"])))
        XCTAssertEqual(Logic.dayFromPosts(posts, "2026-11-06", "3.2")?.status, .check)
    }

    // MARK: - Вибір джерела

    // офіційний сайт працює: запасні джерела не чіпаємо
    func testОфіційнийСайтПрацюєЗапасніНеЧіпаємо() async {
        let s = await scenario(routes: ok(["3.2: 12:00 - 14:00"]))
        XCTAssertEqual(s.requests, [ZOE])
        XCTAssertEqual(s.view.title, "Світло до 12:00")
        XCTAssertEqual(s.view.sub, "Потім без світла до 14:00")
    }

    // сайт недоступний: графік береться зі спільних даних
    func testСайтНедоступнийГрафікЗіСпільнихДаних() async {
        let data = feed("zaporizka-oblast", "3.2", ["2026-11-06": cells([(720, 840)])])
        let s = await scenario(routes: [ZOE: .down, NEW: .json(["body": toJSON(data)])])
        XCTAssertEqual(s.view.title, "Світло до 12:00")
    }

    // незрозумілий допис: беремо запасне джерело й попереджаємо
    func testНезрозумілийДописЗапаснеДжерелоЙПопередження() async {
        let routes: [String: Route] = [
            ZOE: .text(page(post("ОНОВЛЕНО ГПВ НА 6 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ", ["Уточнюється"]))),
            NEW: .json(feed("zaporizka-oblast", "3.2", ["2026-11-06": cells([(720, 840)])])),
        ]
        let s = await scenario(routes: routes)
        XCTAssertEqual(s.view.notice, "Графік міг змінитися")
        XCTAssertEqual(s.view.title, "Світло до 12:00")
    }

    // на сьогодні графіка немає ніде: ніякого «Світло є»
    func testНаСьогодніГрафікаНемаєНіде() async {
        let stale = feed("zaporizka-oblast", "3.2", ["2026-10-17": cells([(0, 120)])])
        let routes: [String: Route] = [
            ZOE: .text(page(post("5 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ ДІЯТИМУТЬ ГПВ", ["3.2: 12:00 - 14:00"]))),
            NEW: .json(stale), OLD: .json(stale),
        ]
        let s = await scenario(routes: routes)
        XCTAssertEqual(s.view.title, "Графіка немає")
    }

    // усі нулі у спільних даних означають відсутність графіка
    func testУсіНуліОзначаютьВідсутністьГрафіка() async {
        let zero = feed("lvivska-oblast", "1.1", ["2026-11-06": cells([], code: 2, fill: 0)])
        let s = await scenario(cfg: Config(region: "lviv", group: "1.1"), routes: [NEW: .json(zero), OLD: .json(zero)])
        XCTAssertEqual(s.view.title, "Графіка немає")
    }

    // усе недоступне й кешу немає: чесно пише, що даних немає
    func testУсеНедоступнеДанихНемає() async {
        let s = await scenario(routes: [ZOE: .down, NEW: .down, GH: .down, OLD: .down])
        XCTAssertEqual(s.view.title, "Немає даних")
    }

    // різні назви регіону в джерелах: Харків знаходиться в обох
    func testХарківЗнаходитьсяВОбохДжерелах() async {
        let days: [String: Any] = ["2026-11-06": cells([(720, 840)])]
        let s = await scenario(cfg: Config(region: "kharkiv", group: "1.1"),
                               routes: [NEW: .json(feed("nothing", "1.1", [:])), OLD: .json(feed("harkivska-oblast", "1.1", days))])
        XCTAssertEqual(s.view.title, "Світло до 12:00")
    }

    // робоче основне джерело: дзеркало на GitHub не запитуємо
    func testРобочеОсновнеДжерелоДзеркалоНеЗапитуємо() async {
        let empty = feed("zaporizka-oblast", "3.2", ["2026-10-17": cells([(0, 120)])])
        let s = await scenario(routes: [ZOE: .down, NEW: .json(empty), OLD: .json(empty)])
        XCTAssertEqual(s.requests, [ZOE, NEW, OLD])
    }

    // MARK: - Написи

    // граматика: «об 11:30», «о 13:30»
    func testГраматикаОбОбо() {
        XCTAssertEqual(Logic.at(690), "об 11:30")
        XCTAssertEqual(Logic.at(810), "о 13:30")
    }

    // відключення через північ: без світла до 02:00 завтра
    func testВідключенняЧерезПівнічДо0200Завтра() async {
        let routes: [String: Route] = [ZOE: .text(page(tomorrowPost(["3.2: 00:00 - 02:00, 06:00 - 11:00"]), today(["3.2: 21:00 - 24:00"])))]
        let s = await scenario(now: "2026-11-06T22:00:00+02:00", routes: routes)
        XCTAssertEqual(s.view.title, "Без світла до 02:00 завтра")
        XCTAssertEqual(s.view.sub, "Потім світло до 06:00 завтра")
        XCTAssertEqual(Logic.changeVerb(s.view), "без світла до завтра")
        XCTAssertEqual(Logic.lockTitle(s.view), "Без світла до 02:00 завтра")
    }

    // відключення до кінця доби, а завтрашнього графіка ще немає
    func testВідключенняДоКінцяДобиБезЗавтра() async {
        let s = await scenario(now: "2026-11-06T22:00:00+02:00", routes: ok(["3.2: 21:00 - 24:00"]))
        XCTAssertEqual(s.view.title, "Світла немає")
        XCTAssertEqual(s.view.sub, "До кінця доби")
        XCTAssertNil(s.view.changeMin)
    }

    // сьогодні вже все минуло: показує завтрашнє відключення
    func testСьогодніВсеМинулоПоказуєЗавтрашнє() async {
        let routes: [String: Route] = [ZOE: .text(page(tomorrowPost(["3.2: 06:00 - 11:00"]), today(["3.2: 04:00 - 09:00"])))]
        let s = await scenario(now: "2026-11-06T22:00:00+02:00", routes: routes)
        XCTAssertEqual(s.view.title, "Світло до 06:00 завтра")
        XCTAssertEqual(s.view.sub, "Потім без світла до 11:00 завтра")
        XCTAssertEqual(s.view.windowsLeft, [])
        XCTAssertEqual(s.view.tomorrowWindows?.map(Logic.windowText), ["06:00–11:00"])
    }

    // без налаштування просить обрати чергу
    func testБезНалаштуванняПроситьОбратиЧергу() {
        let view = Logic.buildGlance(nil, LightData(sched: nil, status: .ok), kyivNow(LOGIC_NOW))
        XCTAssertEqual(view.title, "Оберіть чергу")
        XCTAssertFalse(Logic.captionText(view).contains("за графіком"))
        // На iPhone без Scripting: напис веде у власний застосунок.
        XCTAssertEqual(view.sub, "Відкрийте «Графік світла»")
    }

    // екран блокування без подальших відключень: «Сьогодні більше без відключень»
    func testЕкранБлокуванняСьогодніБільшеБезВідключень() async {
        let s = await scenario(now: "2026-11-06T22:00:00+02:00", routes: ok(["3.2: 12:00 - 14:00"]))
        XCTAssertEqual(Logic.lockLine(s.view), "Сьогодні більше без відключень")
        XCTAssertFalse(Logic.hasTimer(s.view, s.now))
    }

    // код 3 у спільних даних показується як можливе відключення
    func testКод3ЦеМожливеВідключення() async {
        let data = feed("mikolaivska-oblast", "1.1", ["2026-11-06": cells([(540, 720)], code: 3)])
        let s = await scenario(cfg: Config(region: "mykolaiv", group: "1.1"), routes: [OLD: .json(data)])
        XCTAssertEqual(s.view.title, "Можливе відключення")
        XCTAssertEqual(s.view.sub, "До 12:00, потім світло")
        XCTAssertEqual(Logic.lockTitle(s.view), "Можливо до 12:00")
    }

    // аварійний режим видно на віджеті
    func testАварійнийРежимВидноНаВіджеті() async {
        let data = feed("kiivska-oblast", "1.1", ["2026-11-06": cells([(720, 840)])], extra: ["emergency": true])
        let s = await scenario(cfg: Config(region: "kyiv-oblast", group: "1.1"), routes: [NEW: .json(data)])
        XCTAssertEqual(s.view.notice, "Аварійні відключення")
    }

    // дані старші за 3 години позначені часом перевірки
    func testДаніСтаршіЗа3ГодиниПозначеніЧасомПеревірки() async {
        let fresh = await scenario(routes: ok(["3.2: 12:00 - 14:00"]), fetchedAgoMin: 60)
        XCTAssertNil(fresh.view.notice)
        let old = await scenario(routes: ok(["3.2: 12:00 - 14:00"]), fetchedAgoMin: 210)
        XCTAssertEqual(old.view.notice, "Дані від 06:30")
        XCTAssertEqual(old.view.noticeShort, "дані 06:30")
    }

    // час поза графіком не називається «до кінця доби»
    func testЧасПозаГрафікомНеДоКінцяДоби() async {
        var day = cells([(540, 720)], code: 2, fill: 1)
        for min in stride(from: 660, to: 1440, by: 30) { day["\(pad(min / 60)):\(min % 60 != 0 ? "30" : "00")"] = 0 }
        let data = feed("mikolaivska-oblast", "1.1", ["2026-11-06": day])
        let s = await scenario(now: "2026-11-06T15:00:00+02:00", cfg: Config(region: "mykolaiv", group: "1.1"), routes: [OLD: .json(data)])
        XCTAssertEqual(s.view.title, "Графіка немає")
        XCTAssertNotEqual(Logic.quietWords(s.view), "До кінця\nдоби")
    }

    // написи «до коли» лишаються правдою, навіть якщо віджет не перемалювали вчасно
    func testНаписиДоКолиЛишаютьсяПравдою() async {
        let s = await scenario(now: "2026-11-06T23:20:00+02:00", routes: ok(["3.2: 23:30 - 24:00"]))
        XCTAssertEqual(s.view.title, "Світло до 23:30")
        XCTAssertEqual(s.view.sub, "Потім відключення")
        XCTAssertEqual(Logic.changeVerb(s.view), "світло до")
        XCTAssertEqual(Logic.lockTitle(s.view), "Світло до 23:30")
        let known = await scenario(
            now: "2026-11-06T23:20:00+02:00",
            routes: [ZOE: .text(page(tomorrowPost(["3.2: 05:30 - 10:30"]), today(["3.2: 23:30 - 24:00"])))]
        )
        XCTAssertEqual(known.view.sub, "Потім без світла до 24:00")
    }

    // запуск за кордоном: час іде за Києвом
    func testЗапускЗаКордономЧасЗаКиєвом() {
        XCTAssertEqual(Logic.kyivParts(ms: ms("2026-11-06T22:30:00Z")), Now(ymd: "2026-11-07", min: 30))
        XCTAssertEqual(Logic.kyivParts(ms: ms("2026-07-06T21:30:00Z")).min, 30)
    }

    // віджет просить оновлення за 10 секунд після зміни стану, а між змінами раз на 30 хвилин
    func testОновленняЗа10СекундПісляЗміниАбоЧерез30Хвилин() async {
        let soon = await scenario(now: "2026-11-06T11:50:00+02:00", routes: ok(["3.2: 12:00 - 14:00"]))
        let wait = (Logic.refreshDate(soon.view, soon.now, Date(ms: soon.nowMs)).ms - soon.nowMs) / 60000
        XCTAssertEqual((wait * 60).rounded(), 610)
        let later = await scenario(routes: ok(["3.2: 12:00 - 14:00"]))
        XCTAssertEqual((Logic.refreshDate(later.view, later.now, Date(ms: later.nowMs)).ms - later.nowMs) / 60000, 30)
    }

    // MARK: - Батарея й години для малюнків

    // батарея: розряджається до вимкнення, заряджається до ввімкнення
    func testБатареяРозряджаєтьсяІЗаряджається() {
        XCTAssertEqual(Logic.batteryLevel(glance(.on, change: 720, from: 0, nowMin: 540)), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Logic.batteryLevel(glance(.off, change: 840, from: 720, nowMin: 780)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Logic.batteryLevel(glance(.maybe, change: 840, from: 720, nowMin: 750)), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Logic.batteryLevel(glance(.on, change: nil, from: 0, nowMin: 540)), 1)
        XCTAssertEqual(Logic.batteryLevel(glance(.off, change: nil, from: 1200, nowMin: 1300)), 0)
        XCTAssertEqual(Logic.batteryLevel(glance(.none, change: nil, from: nil, nowMin: 540)), 0)
    }

    // частина години без даних вважається невідомою й стоїть на своєму місці
    func testЧастинаГодиниБезДанихНевідома() {
        let runs = [Run(s: 0, e: 610, st: .on), Run(s: 630, e: 1440, st: .off)]
        XCTAssertEqual(Logic.hourParts(runs, 10), [
            Part(from: 600, to: 610, st: .on),
            Part(from: 610, to: 630, st: .unknown),
            Part(from: 630, to: 660, st: .off),
        ])
        XCTAssertEqual(Logic.currentHour(nil), -1)
        XCTAssertEqual(Logic.currentHour(659), 10)
    }

    // невідомий вигляд у налаштуванні дає типовий
    func testНевідомийВиглядДаєТиповий() {
        XCTAssertEqual(Logic.lookOf("pyramid", Logic.defaultLook), "house")
        XCTAssertEqual(Logic.lockLookOf(nil), "bulb") // на екрані блокування батарею замінила лампочка
        XCTAssertEqual(Logic.lookOf("garland", Logic.defaultLook), "garland")
    }

    // MARK: - Черги

    // Запоріжжя: черги з офіційного переліку; інші регіони: з даних, за номером
    func testЧергиЗапоріжжяЗПерелікуІншіЗаНомером() async throws {
        let zp = try await Logic.groupsFor(try XCTUnwrap(Logic.regionById("zaporizhzhia")), { url in
            throw TestNetError.unexpected("не мало запитувати \(url)")
        })
        XCTAssertEqual(zp, zoeGroups)
        let empty: [String: Any] = [:]
        let region: [String: Any] = ["cpu": "chernivetska-oblast", "schedule": ["10": empty, "2": empty, "1": empty]]
        let loader = Loader([NEW: .json(["regions": [region]])])
        let groups = try await Logic.groupsFor(try XCTUnwrap(Logic.regionById("chernivtsi")), loader.load)
        XCTAssertEqual(groups, ["1", "2", "10"])
    }

    // MARK: - Сповіщення: за 10 хвилин

    // попередження за 10 хвилин до вимкнення й до ввімкнення, лише майбутні
    func testПопередженняЗа10ХвилинЛишеМайбутні() async throws {
        let s = await scenario(now: "2026-11-06T12:40:00+02:00", routes: ok(["3.2: 13:00 - 14:00, 15:00 - 16:00, 20:00 - 21:00"]))
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)
        XCTAssertEqual(kinds(items), ["off 12:50", "on 13:50", "off 14:50", "on 15:50", "off 19:50", "on 20:50"])
        guard items.count >= 2 else { return XCTFail("замало попереджень: \(items.count)") }
        XCTAssertEqual(items[0].title, "Через 10 хв вимкнуть світло")
        XCTAssertEqual(items[0].body, "Черга 3.2: відключення о 13:00, увімкнуть о 14:00")
        XCTAssertEqual(items[1].title, "Через 10 хв увімкнуть світло")
        XCTAssertEqual(items[1].body, "Черга 3.2: світло о 14:00")
    }

    // кожне попередження вимикається окремо
    func testКожнеПопередженняВимикаєтьсяОкремо() async throws {
        let s = await scenario(routes: ok(["3.2: 13:00 - 14:00"]))
        let sched = try XCTUnwrap(s.sched)
        XCTAssertEqual(Logic.plannedNotifications(sched, s.now, "3.2", NotifyPrefs(off: true, on: false)).map { $0.kind }, [.off])
        XCTAssertEqual(Logic.plannedNotifications(sched, s.now, "3.2", NotifyPrefs(off: false, on: true)).map { $0.kind }, [.on])
        XCTAssertEqual(Logic.plannedNotifications(sched, s.now, "3.2", NotifyPrefs(off: false, on: false)), [])
    }

    // відключення вже триває: лишається тільки попередження про ввімкнення
    func testВідключенняТриваєЛишеПроВвімкнення() async throws {
        let s = await scenario(now: "2026-11-06T13:00:00+02:00", routes: ok(["3.2: 12:00 - 14:00"]))
        XCTAssertEqual(kinds(Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)), ["on 13:50"])
    }

    // відключення через північ: одне попередження про вимкнення й одне про ввімкнення завтра
    func testЧерезПівнічОднеПроВимкненняОднеПроВвімкнення() async throws {
        let routes: [String: Route] = [ZOE: .text(page(tomorrowPost(["3.2: 00:00 - 02:00"]), today(["3.2: 21:00 - 24:00"])))]
        let s = await scenario(routes: routes)
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)
        XCTAssertEqual(items.map { $0.kind }, [.off, .on])
        guard items.count == 2 else { return }
        XCTAssertEqual(items[0].body, "Черга 3.2: відключення о 21:00, увімкнуть завтра о 02:00")
        // Попередження про ввімкнення прийде о 01:50 уже завтрашнього дня: для того моменту це «о 02:00», без «завтра».
        XCTAssertEqual(items[1].body, "Черга 3.2: світло о 02:00")
        XCTAssertEqual(items[1].triggerMin, 1440 + 110)
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    // Баг 12.11.2026: попередження, заплановане звечора на завтра, прийшло завтра з текстом «відключення завтра о 14:30».
    // попередження на завтра, заплановане звечора, не каже «завтра»: воно прийде вже того дня
    func testПопередженняНаЗавтраЗвечораНеКажеЗавтра() async throws {
        let routes: [String: Route] = [ZOE: .text(page(tomorrowPost(["3.2: 14:30 - 19:30"]), today(["3.2: 08:00 - 10:00"])))]
        let s = await scenario(now: "2026-11-06T20:00:00+02:00", routes: routes)
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)
        XCTAssertEqual(items.map { "\($0.kind.rawValue) \($0.triggerMin)" }, ["off \(1440 + 860)", "on \(1440 + 1160)"])
        guard items.count == 2 else { return }
        XCTAssertEqual(items[0].body, "Черга 3.2: відключення о 14:30, увімкнуть о 19:30")
        XCTAssertEqual(items[1].body, "Черга 3.2: світло о 19:30")
        for item in items { XCTAssertFalse(item.body.contains("завтра"), item.body) }
    }

    // відключення до кінця доби: «увімкнуть опівночі», а не «завтра о 00:00»
    func testДоКінцяДобиУвімкнутьОпівночі() async throws {
        let routes: [String: Route] = [ZOE: .text(page(tomorrowPost(["3.2: 06:00 - 08:00"]), today(["3.2: 21:00 - 24:00"])))]
        let s = await scenario(routes: routes)
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)
        guard items.count >= 2 else { return XCTFail("замало попереджень: \(kinds(items))") }
        XCTAssertEqual(items[0].body, "Черга 3.2: відключення о 21:00, увімкнуть опівночі")
        XCTAssertEqual(items[1].body, "Черга 3.2: світло опівночі")
    }

    // noticeWhen: день рахується від моменту показу
    func testNoticeWhenДеньВідМоментуПоказу() {
        XCTAssertEqual(Logic.noticeWhen(870, 860), "о 14:30")
        XCTAssertEqual(Logic.noticeWhen(1440 + 870, 1440 + 860), "о 14:30")
        XCTAssertEqual(Logic.noticeWhen(1440 + 120, 1250), "завтра о 02:00")
        XCTAssertEqual(Logic.noticeWhen(1440 + 690, 1440 + 680), "об 11:30")
        XCTAssertEqual(Logic.noticeWhen(1440, 1430), "опівночі")
    }

    // кінець відключення невідомий: про ввімкнення не попереджаємо
    func testКінецьНевідомийПроВвімкненняНеПопереджаємо() async throws {
        let s = await scenario(routes: ok(["3.2: 21:00 - 24:00"]))
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "3.2", PREFS)
        XCTAssertEqual(items.map { $0.kind }, [.off])
        XCTAssertEqual(items.first?.body, "Черга 3.2: відключення о 21:00")
    }

    // можливе відключення названо можливим
    func testМожливеВідключенняНазваноМожливим() async throws {
        let data = feed("mikolaivska-oblast", "1.1", ["2026-11-06": cells([(720, 840)], code: 3)])
        let s = await scenario(cfg: Config(region: "mykolaiv", group: "1.1"), routes: [OLD: .json(data)])
        let items = Logic.plannedNotifications(try XCTUnwrap(s.sched), s.now, "1.1", PREFS)
        XCTAssertEqual(items.first?.title, "Через 10 хв можливе відключення")
        XCTAssertEqual(items.first?.body, "Черга 1.1: можливе відключення о 12:00, увімкнуть о 14:00")
    }

    // MARK: - Сповіщення: графік змінився

    // перше завантаження нічого не повідомляє
    func testПершеЗавантаженняНічогоНеПовідомляє() async throws {
        let first = try await known(nil, LOGIC_NOW, ["3.2: 12:00 - 14:00"])
        XCTAssertEqual(Logic.scheduleChanges(nil, first.known, first.now), [])
    }

    // той самий графік пізніше не дає сповіщення, хоч вікна й минають
    func testТойСамийГрафікПізнішеБезСповіщення() async throws {
        let first = try await known(nil, "2026-11-06T08:00:00+02:00", ["3.2: 09:00 - 10:00, 12:00 - 14:00"])
        let later = try await known(first.known, "2026-11-06T11:00:00+02:00", ["3.2: 09:00 - 10:00, 12:00 - 14:00"])
        XCTAssertEqual(Logic.scheduleChanges(first.known, later.known, later.now), [])
    }

    // зсунули відключення: «Графік відключень змінився» з новими годинами
    func testЗсунулиВідключенняГрафікЗмінився() async throws {
        let first = try await known(nil, LOGIC_NOW, ["3.2: 12:00 - 14:00"])
        let next = try await known(first.known, "2026-11-06T10:20:00+02:00", ["3.2: 13:00 - 15:00"])
        let changes = Logic.scheduleChanges(first.known, next.known, next.now)
        XCTAssertEqual(Logic.changeMessage(changes, next.now, "3.2"),
                       Message(title: "Графік відключень змінився", body: "Черга 3.2, сьогодні: 13:00–15:00"))
    }

    // відключення скасували: «без відключень»
    func testВідключенняСкасувалиБезВідключень() async throws {
        let first = try await known(nil, LOGIC_NOW, ["3.2: 12:00 - 14:00"])
        let next = try await known(first.known, "2026-11-06T10:20:00+02:00", ["1.1: 12:00 - 14:00"])
        let message = Logic.changeMessage(Logic.scheduleChanges(first.known, next.known, next.now), next.now, "3.2")
        XCTAssertEqual(message?.body, "Черга 3.2, сьогодні: без відключень")
    }

    // зʼявився графік на завтра: «Новий графік відключень»
    func testЗявивсяГрафікНаЗавтраНовийГрафік() async throws {
        let first = try await known(nil, "2026-11-06T18:00:00+02:00", ["3.2: 12:00 - 14:00"])
        let next = try await known(first.known, "2026-11-06T19:00:00+02:00", ["3.2: 12:00 - 14:00"], [tomorrowPost(["3.2: 06:00 - 11:00"])])
        let message = Logic.changeMessage(Logic.scheduleChanges(first.known, next.known, next.now), next.now, "3.2")
        XCTAssertEqual(message, Message(title: "Новий графік відключень", body: "Черга 3.2, завтра: 06:00–11:00"))
    }

    // зміна в годинах, що вже минули, не повідомляється
    func testЗмінаВМинулихГодинахНеПовідомляється() async throws {
        let first = try await known(nil, "2026-11-06T08:00:00+02:00", ["3.2: 09:00 - 10:00, 16:00 - 18:00"])
        let next = try await known(first.known, "2026-11-06T12:00:00+02:00", ["3.2: 08:30 - 10:30, 16:00 - 18:00"])
        XCTAssertEqual(Logic.scheduleChanges(first.known, next.known, next.now), [])
    }

    // джерело на мить загубило завтрашній графік: повернення не дає хибного сповіщення
    func testЗагубленийНаМитьЗавтрашнійГрафікБезХибногоСповіщення() async throws {
        let both = [tomorrowPost(["3.2: 06:00 - 11:00"])]
        let first = try await known(nil, "2026-11-06T18:00:00+02:00", ["3.2: 12:00 - 14:00"], both)
        let lost = try await known(first.known, "2026-11-06T18:20:00+02:00", ["3.2: 12:00 - 14:00"])
        XCTAssertEqual(Logic.scheduleChanges(first.known, lost.known, lost.now), [])
        let back = try await known(lost.known, "2026-11-06T18:40:00+02:00", ["3.2: 12:00 - 14:00"], both)
        XCTAssertEqual(Logic.scheduleChanges(lost.known, back.known, back.now), [])
    }

    // після півночі вчорашнє «завтра» стало «сьогодні» без хибного сповіщення
    func testПісляПівночіЗавтраСталоСьогодніБезХибногоСповіщення() async throws {
        let evening = try await known(nil, "2026-11-06T23:50:00+02:00", ["3.2: 12:00 - 14:00"], [tomorrowPost(["3.2: 06:00 - 11:00"])])
        let s = await scenario(now: "2026-11-07T00:10:00+02:00", routes: [ZOE: .text(page(tomorrowPost(["3.2: 06:00 - 11:00"])))])
        let night = Logic.knownWindows(evening.known, try XCTUnwrap(s.sched), s.now)
        XCTAssertEqual(Logic.scheduleChanges(evening.known, night, s.now), [])
    }
}
