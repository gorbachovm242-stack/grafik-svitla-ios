// Порт tools/scripting-alerts.test.mjs: повітряна тривога (Alerts.swift) — розбір відповідей посередника, стан для обраного
// місця, канал моніторингу, сторінки віджета, кеш і мережа (Store.swift). Палітра — у ThemeTests. Дані синтетичні.
// Над кожним тестом — назва оригіналу.
import XCTest
@testable import SvitloCore

private let NOW = ms("2026-11-06T12:00:00+02:00")

// Синтетичні місця: область 12, район 99 («Тестовий район»), громада 564, місто цієї громади 5564.
private let OBLAST = Place(oblast: "12", oblastTitle: "Запорізька область")
private let RAION = Place(oblast: "12", oblastTitle: "Запорізька область", raion: "99", raionTitle: "Тестовий район")
private let HROMADA = Place(oblast: "12", oblastTitle: "Запорізька область", raion: "99", raionTitle: "Тестовий район",
                            hromada: "564", hromadaTitle: "м. Тестове та Тестова територіальна громада")
private let KYIV = Place(oblast: "31", oblastTitle: "м. Київ")

private func alert(
    uid: String = "12", title: String = "Запорізька область", kind: String = "oblast", parent: String = "", oblast: String = "12",
    raion: String = "", type: String = "air_raid", level: String = "red", since: Millis = NOW - 80 * MIN, threats: [String] = []
) -> AirAlert {
    AirAlert(uid: uid, title: title, kind: kind, parent: parent, oblast: oblast, raion: raion, type: type, level: level, since: since, threats: threats)
}

private func alertFeed(_ alerts: [AirAlert], ok: Bool = true, stale: Bool = false, fetchedAt: Millis = NOW - MIN) -> AlertFeed {
    AlertFeed(ok: ok, stale: stale, fetchedAt: fetchedAt, alerts: alerts)
}

/// Тривога так, як її віддає посередник: час початку рядком ISO.
private func alertJSON(_ a: AirAlert, since: String) -> [String: Any] {
    ["uid": a.uid, "title": a.title, "kind": a.kind, "parent": a.parent, "oblast": a.oblast, "raion": a.raion, "type": a.type,
     "level": a.level, "since": since, "threats": a.threats]
}

/// Сторінка t.me/s/канал: синтетичні дописи (старіші першими); nil — допис лише з фото.
private func channelPage(_ posts: [(String, String?)]) -> String {
    let items = posts.map { iso, text -> String in
        let body = text.map { "<div class=\"tgme_widget_message_text js-message_text\" dir=\"auto\">\($0)</div>" } ?? ""
        return "<div class=\"tgme_widget_message_wrap\"><div class=\"tgme_widget_message\">\(body)"
            + "<a class=\"tgme_widget_message_date\"><time datetime=\"\(iso)\" class=\"time\">00:00</time></a></div></div>"
    }
    return "<html><head><meta property=\"og:title\" content=\"Тестовий моніторинг &amp; Ко\"></head><body><div class=\"tgme_channel_info\"></div>"
        + items.joined() + "</body></html>"
}

final class AlertsTests: XCTestCase {
    // MARK: - Розбір

    // parseAlertFeed: відповідь посередника, зламана відповідь і відповідь без списку
    func testParseAlertFeedЗламанаЙБезСписку() {
        let city: [String: Any] = [
            "uid": "5564", "title": "м. Тестове", "kind": "city", "parent": "564", "raion": "Тестовий район", "type": "air_raid", "level": "red",
            "since": "2026-11-06T08:40:00.000Z", "threats": ["drones"], "oblast": "12",
        ]
        let text = toJSON(["ok": true, "stale": false, "fetchedAt": Int(NOW), "alerts": [city]] as [String: Any])
        let f = AlertLogic.parseAlertFeed(text)
        XCTAssertTrue(f.ok)
        XCTAssertEqual(f.fetchedAt, NOW)
        XCTAssertEqual(f.alerts.count, 1)
        XCTAssertEqual(f.alerts.first?.parent, "564")
        XCTAssertEqual(f.alerts.first?.since, ms("2026-11-06T08:40:00.000Z"))
        XCTAssertEqual(f.alerts.first?.threats, ["drones"])
        XCTAssertFalse(AlertLogic.parseAlertFeed("<html>").ok)
        XCTAssertFalse(AlertLogic.parseAlertFeed("{\"ok\":true}").ok)
        // Невідомий час початку: 0, а не NaN.
        let bare = AlertLogic.parseAlertFeed(toJSON(["ok": true, "fetchedAt": 1, "alerts": [["uid": "1"]]] as [String: Any]))
        XCTAssertEqual(bare.alerts.first?.since, 0)
    }

    // parseLocations: область → райони → громади
    func testParseLocationsОбластьРайониГромади() {
        let hromadas: [[String: Any]] = [["uid": "564", "title": "Тестова ТГ"]]
        let raions: [[String: Any]] = [["uid": "99", "title": "Тестовий район", "hromadas": hromadas]]
        let oblasts: [[String: Any]] = [
            ["uid": "31", "title": "м. Київ", "raions": [Any]()],
            ["uid": "12", "title": "Запорізька область", "raions": raions],
        ]
        let list = AlertLogic.parseLocations(toJSON(["ok": true, "oblasts": oblasts] as [String: Any]))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.last?.children.first?.children.first?.uid, "564")
        XCTAssertEqual(AlertLogic.parseLocations("зламано"), [])
        XCTAssertEqual(AlertLogic.defaultOblasts().count, 27)
    }

    // MARK: - Стан

    // стан: місця не обрано, немає даних, старі дані
    func testСтанМісцяНеОбраноНемаєДанихСтаріДані() {
        XCTAssertEqual(AlertLogic.alertStatus(nil, alertFeed([]), NOW).kind, .setup)
        XCTAssertEqual(AlertLogic.alertStatus(nil, alertFeed([]), NOW).sub, "Відкрийте «Графік світла»")
        XCTAssertEqual(AlertLogic.alertStatus(OBLAST, nil, NOW).kind, .nodata)
        XCTAssertEqual(AlertLogic.alertStatus(OBLAST, alertFeed([], ok: false), NOW).kind, .nodata)
        let old = AlertLogic.alertStatus(OBLAST, alertFeed([], fetchedAt: NOW - 200 * MIN), NOW)
        XCTAssertEqual(old.kind, .nodata)
        XCTAssertEqual(old.title, "Немає свіжих даних")
        // Пів години без підтвердження: стан ще показуємо, але позначаємо часом перевірки.
        let stale = AlertLogic.alertStatus(OBLAST, alertFeed([], fetchedAt: NOW - 40 * MIN), NOW)
        XCTAssertEqual(stale.kind, .quiet)
        XCTAssertTrue(stale.stale)
        XCTAssertEqual(stale.checked, "11:20")
        XCTAssertTrue(AlertLogic.alertStatus(OBLAST, alertFeed([], stale: true), NOW).stale)
    }

    // стан: тривога в місті громади (окремий UID міста) і де її оголошено
    func testСтанТривогаВМістіГромадиІДеОголошено() {
        let city = alert(uid: "5564", title: "м. Тестове", kind: "city", parent: "564", raion: "Тестовий район", threats: ["drones", "ballistic_missiles"])
        let s = AlertLogic.alertStatus(HROMADA, alertFeed([city]), NOW)
        XCTAssertEqual(s.kind, .alert)
        XCTAssertEqual(s.title, "Повітряна тривога")
        XCTAssertEqual(s.subShort, "з 10:40")
        XCTAssertEqual(s.sub, "з 10:40 · БпЛА, балістика")
        XCTAssertTrue(s.timer)
        XCTAssertEqual(s.place, "м. Тестове та Тестова ТГ")
        XCTAssertEqual(s.where_, "м. Тестове")
        // Тривога на всю область для громади: «уся область».
        XCTAssertEqual(AlertLogic.alertStatus(HROMADA, alertFeed([alert()]), NOW).where_, "уся область")
        // Місто з окремими тривогами (Київ) обрано як область: «уся область» не пишемо.
        XCTAssertEqual(AlertLogic.alertStatus(KYIV, alertFeed([alert(uid: "31", title: "м. Київ", oblast: "31")]), NOW).where_, "")
    }

    // стан: попередня загроза, і тривога важливіша за неї
    func testСтанПопередняЗагрозаТривогаВажливіша() {
        let yellow = alert(level: "yellow")
        let threat = AlertLogic.alertStatus(OBLAST, alertFeed([yellow]), NOW)
        XCTAssertEqual(threat.kind, .threat)
        XCTAssertEqual(threat.title, "Попередня загроза")
        let both = AlertLogic.alertStatus(RAION, alertFeed([yellow, alert(uid: "99", title: "Тестовий район", kind: "raion", since: NOW - 5 * MIN)]), NOW)
        XCTAssertEqual(both.kind, .alert)
        XCTAssertEqual(both.subShort, "з 11:55")
        // Інші типи тривог мають свою назву.
        XCTAssertEqual(AlertLogic.alertStatus(OBLAST, alertFeed([alert(type: "artillery_shelling")]), NOW).title, "Загроза обстрілу")
    }

    // стан: тривога поруч — свій район першим, назва залежить від того, наскільки точно обрано місце
    func testСтанТривогаПоручСвійРайонПершим() {
        let own = alert(uid: "777", title: "Сусідня територіальна громада", kind: "hromada", raion: "Тестовий район")
        let far = alert(uid: "888", title: "Далекий район", kind: "raion", raion: "Далекий район")
        let s = AlertLogic.alertStatus(HROMADA, alertFeed([far, own]), NOW)
        XCTAssertEqual(s.kind, .nearby)
        XCTAssertEqual(s.title, "Тут тихо")
        XCTAssertEqual(s.sub, "поруч: Сусідня ТГ і ще 1")
        XCTAssertEqual(s.others, ["Сусідня ТГ", "Далекий район"])
        XCTAssertEqual(AlertLogic.alertStatus(RAION, alertFeed([own]), NOW).title, "Тривога в частині району")
        XCTAssertEqual(AlertLogic.alertStatus(OBLAST, alertFeed([far]), NOW).title, "Тривога в частині області")
        XCTAssertEqual(AlertLogic.alertStatus(HROMADA, alertFeed([far]), NOW).sub, "в області: Далекий район")
        // Попередні загрози інших громад «поруч» не роблять.
        var farYellow = far
        farYellow.level = "yellow"
        XCTAssertEqual(AlertLogic.alertStatus(HROMADA, alertFeed([farYellow]), NOW).kind, .quiet)
    }

    // стан: тихо, і довга тривога без таймера
    func testСтанТихоІДовгаТривогаБезТаймера() {
        XCTAssertEqual(AlertLogic.alertStatus(OBLAST, alertFeed([]), NOW).sub, "тихо в усій області")
        XCTAssertEqual(AlertLogic.alertStatus(KYIV, alertFeed([]), NOW).sub, "тихо в усьому місті")
        let years = AlertLogic.alertStatus(OBLAST, alertFeed([alert(since: ms("2022-04-04T16:45:39Z"))]), NOW)
        XCTAssertEqual(years.kind, .alert)
        XCTAssertFalse(years.timer)
        XCTAssertEqual(years.subShort, "з 04.04.2022")
        XCTAssertEqual(AlertLogic.alertSince(ms("2026-11-05T20:10:00Z"), NOW), "з 05.11, 22:10")
        XCTAssertEqual(AlertLogic.alertSince(0, NOW), "триває")
        XCTAssertEqual(AlertLogic.checkedText(ms("2026-11-05T08:42:00Z"), NOW), "05.11, 10:42")
    }

    // загрози: не більше двох, без повторів, невідомі пропускаємо
    func testЗагрозиНеБільшеДвохБезПовторів() {
        XCTAssertEqual(AlertLogic.threatText(["drones", "drones", "cruise_missiles", "guided_aerial_bombs"]), "БпЛА, крилаті ракети")
        XCTAssertNil(AlertLogic.threatText(["something_new"]))
        XCTAssertNil(AlertLogic.threatText([]))
    }

    // напис біля значка тривоги: довгий і короткий; у тиші жодного
    func testНаписБіляЗначкаДовгийІКороткий() {
        let s = AlertLogic.alertStatus(HROMADA, alertFeed([alert(uid: "564", title: "Тестова ТГ", kind: "hromada")]), NOW)
        XCTAssertEqual(AlertLogic.alertPill(s, short: false), "Тривога з 10:40")
        XCTAssertEqual(AlertLogic.alertPill(s, short: true), "з 10:40")
        let years = AlertLogic.alertStatus(OBLAST, alertFeed([alert(since: ms("2022-04-04T16:45:39Z"))]), NOW)
        XCTAssertEqual(AlertLogic.alertPill(years, short: false), "Повітряна тривога")
        XCTAssertEqual(AlertLogic.alertPill(years, short: true), "Тривога")
        XCTAssertEqual(AlertLogic.alertPill(AlertLogic.alertStatus(OBLAST, alertFeed([alert(level: "yellow")]), NOW), short: true), "Загроза")
        XCTAssertNil(AlertLogic.alertPill(AlertLogic.alertStatus(OBLAST, alertFeed([]), NOW), short: false))
        XCTAssertEqual(AlertLogic.alertPill(AlertLogic.alertStatus(nil, nil, NOW), short: false), "Оберіть місце")
        XCTAssertEqual(AlertLogic.alertShortTitle(s), "Тривога")
    }

    // коротка назва місця для малого віджета
    func testКороткаНазваМісця() {
        XCTAssertEqual(AlertLogic.compactPlace("м. Запоріжжя та Запорізька територіальна громада"), "м. Запоріжжя")
        XCTAssertEqual(AlertLogic.compactPlace("м. Кривий Ріг та Криворізька ТГ"), "м. Кривий Ріг")
        XCTAssertEqual(AlertLogic.compactPlace("Запорізька область"), "Запорізька обл.")
        XCTAssertEqual(AlertLogic.compactPlace("Запорізький район"), "Запорізький р-н")
        XCTAssertEqual(AlertLogic.compactPlace("Біленьківська територіальна громада"), "Біленьківська ТГ")
        XCTAssertEqual(AlertLogic.compactPlace("м. Київ"), "м. Київ")
        XCTAssertEqual(AlertLogic.compactPlace(""), "")
    }

    // місце: зламаний запис чиститься, громада без району відкидається
    func testМісцеЗламанийЗаписЧиститься() {
        XCTAssertNil(AlertLogic.cleanPlace(nil))
        XCTAssertNil(AlertLogic.cleanPlace(Place(oblast: ""))) // у JS це {}: області немає
        XCTAssertEqual(AlertLogic.cleanPlace(Place(oblast: "12", hromada: "564")), Place(oblast: "12", oblastTitle: nil))
        XCTAssertEqual(AlertLogic.oblastForRegion("zaporizhzhia"), "12")
        XCTAssertEqual(AlertLogic.oblastForRegion("kyiv"), "31")
        XCTAssertNil(AlertLogic.oblastForRegion(""))
    }

    // MARK: - Канал моніторингу

    // канал: дописи, назва, свіжі й «щось відбувається»
    func testКаналДописиНазваСвіжіЙБусі() {
        let html = channelPage([
            ("2026-11-06T08:00:00+00:00", "Давній допис"),
            ("2026-11-06T09:40:00+00:00", "2 <b>БпЛА</b> курсом на<br/>тестове місто"),
            ("2026-11-06T09:45:00+00:00", nil),
            ("2026-11-06T09:50:00+00:00", "Чисто&nbsp;&quot;поки що&quot;"),
        ])
        let posts = AlertLogic.parseChannelPosts(html)
        XCTAssertEqual(posts.count, 3)
        guard posts.count == 3 else { return }
        XCTAssertEqual(posts[1].text, "2 БпЛА курсом на тестове місто")
        XCTAssertEqual(posts[2].text, "Чисто \"поки що\"")
        XCTAssertEqual(AlertLogic.parseChannelTitle(html), "Тестовий моніторинг & Ко")
        let fresh = AlertLogic.freshPosts(posts, NOW, 3)
        XCTAssertEqual(fresh.map { $0.text }, ["Чисто \"поки що\"", "2 БпЛА курсом на тестове місто"])
        XCTAssertEqual(fresh.first.map(AlertLogic.postLine), "11:50 · Чисто \"поки що\"")
        let quiet = AlertLogic.alertStatus(OBLAST, alertFeed([]), NOW)
        XCTAssertEqual(AlertLogic.withPosts(quiet, posts, "Моніторинг", NOW).posts,
                       ["11:50 · Чисто \"поки що\"", "11:40 · 2 БпЛА курсом на тестове місто"])
        XCTAssertEqual(AlertLogic.withPosts(AlertLogic.alertStatus(nil, nil, NOW), posts, "Моніторинг", NOW).posts, [])
        // Допис 10 хвилин тому — щось відбувається; годину тому — ні.
        XCTAssertTrue(AlertLogic.busy(quiet, posts, NOW))
        XCTAssertFalse(AlertLogic.busy(quiet, posts, NOW + 30 * MIN))
        XCTAssertTrue(AlertLogic.busy(AlertLogic.alertStatus(OBLAST, alertFeed([alert()]), NOW), [], NOW))
        XCTAssertEqual(AlertLogic.alertRefreshMinutes(quiet, [], NOW), AlertConfig.quietRefreshMinutes)
        XCTAssertEqual(AlertLogic.alertRefreshMinutes(quiet, posts, NOW), AlertConfig.busyRefreshMinutes)
    }

    // назва каналу з посилання, @назви чи самої назви
    func testНазваКаналуЗПосилання() {
        XCTAssertEqual(AlertLogic.channelName("https://t.me/test_monitor"), "test_monitor")
        XCTAssertEqual(AlertLogic.channelName("t.me/s/test_monitor?before=5"), "test_monitor")
        XCTAssertEqual(AlertLogic.channelName("@test_monitor"), "test_monitor")
        XCTAssertEqual(AlertLogic.channelName("test_monitor"), "test_monitor")
        XCTAssertEqual(AlertLogic.channelName("t.me/+AbCdEfGh"), "")
        XCTAssertEqual(AlertLogic.channelName("абв"), "")
    }

    // MARK: - Сторінки віджета

    // сторінка: світло за замовчуванням, обрана тримається 15 хвилин, одразу після дотику — без мережі
    func testСторінкаСвітлоЗаЗамовчуваннямОбранаТримається15Хв() {
        let pages = AlertLogic.pagesOf(true)
        XCTAssertEqual(pages, ["light", "alert"])
        XCTAssertEqual(AlertLogic.pagesOf(false), ["light"])
        let t0 = NOW
        XCTAssertEqual(AlertLogic.pageMode(nil, pages, t0), PageMode(page: "light", until: nil, quick: false))
        let choice = PageChoice(page: "alert", at: t0)
        XCTAssertEqual(AlertLogic.pageMode(choice, pages, t0 + 1000), PageMode(page: "alert", until: t0 + 15 * MIN, quick: true))
        XCTAssertEqual(AlertLogic.pageMode(choice, pages, t0 + 60000), PageMode(page: "alert", until: t0 + 15 * MIN, quick: false))
        XCTAssertEqual(AlertLogic.pageMode(choice, pages, t0 + 15 * MIN), PageMode(page: "light", until: nil, quick: false))
        // Тривогу вимкнули: її сторінки вже немає.
        XCTAssertEqual(AlertLogic.pageMode(choice, ["light"], t0 + 1000).page, "light")
        // Повернулися на світло дотиком: швидко й без строку.
        XCTAssertEqual(AlertLogic.pageMode(PageChoice(page: "light", at: t0), pages, t0 + 1000), PageMode(page: "light", until: nil, quick: true))
        // Годинник перевели назад.
        XCTAssertEqual(AlertLogic.pageMode(choice, pages, t0 - MIN).page, "light")
        // Зламаний запис ({ page: 'alert' } без часу): у Swift такий запис не читається зі сховища, тож теж світло.
        let env = Env()
        env.kv.set(Data(#"{"systemSmall|":{"page":"alert"}}"#.utf8), forKey: "page")
        XCTAssertNil(env.store.readPage("systemSmall|"))
        XCTAssertEqual(AlertLogic.pageMode(env.store.readPage("systemSmall|"), pages, t0).page, "light")
        XCTAssertEqual(AlertLogic.pageKey("systemSmall", " Друга "), "systemSmall|друга")
    }

    // оновлення віджета: з тривогами частіше, але не пізніше за зміну стану світла
    func testОновленняЗТривогамиЧастішеАлеНеПізнішеЗаЗміну() {
        let nowParts = Logic.kyivParts(ms: NOW)
        var view = Glance()
        view.changeMin = nowParts.min + 120
        let date = Date(ms: NOW)
        XCTAssertEqual((Logic.refreshDate(view, nowParts, date).ms - NOW) / MIN, 30)
        XCTAssertEqual((Logic.refreshDate(view, nowParts, date, alertMinutes: 15).ms - NOW) / MIN, 15)
        XCTAssertEqual((Logic.refreshDate(view, nowParts, date, alertMinutes: 5).ms - NOW) / MIN, 5)
        var soon = Glance()
        soon.changeMin = nowParts.min + 3
        XCTAssertEqual(Logic.refreshDate(soon, nowParts, date, alertMinutes: 15).ms, Logic.changeDate(soon, nowParts, date).ms + 10000)
    }

    // MARK: - Сховище й мережа

    // тривоги: вимкнено — нічого не вантажимо; місця немає — «Оберіть місце» без мережі
    func testТривогиВимкненоНічогоМісцяНемаєБезМережі() async {
        let env = Env()
        env.at("2026-11-06T12:00:00+02:00")
        let off = await env.store.freshAlerts(AlertSettings(), force: false, budgetMs: 1000, requestMs: 500)
        XCTAssertNil(off)
        let setup = await env.store.freshAlerts(AlertSettings(enabled: true), force: false, budgetMs: 1000, requestMs: 500)
        XCTAssertEqual(setup?.status.kind, .setup)
        XCTAssertEqual(env.http.requests, [])
    }

    // тривоги: стан і канал з мережі, повтор протягом 50 с зі збереженого, «↻» завжди йде в мережу
    func testТривогиЗМережіПовторЗіЗбереженогоОновитиЗавжди() async {
        let env = Env()
        let t = env.at("2026-11-06T12:00:00+02:00").ms
        let here = alertJSON(alert(uid: "564", title: "Тестова ТГ", kind: "hromada"), since: "2026-11-06T08:40:00.000Z")
        env.http.routes = [
            FEED_URL: .json(["ok": true, "stale": false, "fetchedAt": Int(t - 30000), "alerts": [here]]),
            CHANNEL_URL: .text(channelPage([("2026-11-06T09:55:00+00:00", "Тестовий допис")])),
        ]
        let settings = AlertSettings(enabled: true, place: HROMADA, channel: "test_monitor")
        let first = await env.store.freshAlerts(settings, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(first?.status.kind, .alert)
        XCTAssertEqual(first?.status.posts, ["11:55 · Тестовий допис"])
        XCTAssertEqual(first?.status.channel, "Тестовий моніторинг & Ко")
        XCTAssertEqual(env.http.requests, [FEED_URL, CHANNEL_URL])

        env.http.clearRequests()
        env.clock.advance(20000)
        let again = await env.store.freshAlerts(settings, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(again?.status.kind, .alert)
        XCTAssertEqual(env.http.requests, [], "за 20 с і тривоги, і канал зі збереженого")

        env.clock.advance(40000) // тривоги вже старші за 50 с, канал (щось відбувається) — за 45 с
        _ = await env.store.freshAlerts(settings, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(env.http.requests, [FEED_URL, CHANNEL_URL])

        env.http.clearRequests()
        _ = await env.store.freshAlerts(settings, force: true, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(env.http.requests, [FEED_URL, CHANNEL_URL], "«↻»")
    }

    // тривоги без інтернету: збережений стан; запит, що висить, не тримає віджет довше за строк
    func testТривогиБезІнтернетуЗбереженийСтанЗавислийЗапитНеТримає() async {
        let env = Env()
        let t = env.at("2026-11-06T12:00:00+02:00").ms
        env.http.routes = [FEED_URL: .json(["ok": true, "fetchedAt": Int(t), "alerts": [Any]()])]
        let settings = AlertSettings(enabled: true, place: OBLAST)
        let online = await env.store.freshAlerts(settings, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(online?.status.kind, .quiet)
        env.clock.advance(5 * MIN)
        env.http.routes = [:]
        let offline = await env.store.freshAlerts(settings, force: false, budgetMs: 2000, requestMs: 1000)
        XCTAssertEqual(offline?.status.kind, .quiet)
        XCTAssertEqual(offline?.status.checked, "12:00")
        env.http.offline = .deaf
        let (hung, elapsed) = await timed { await env.store.freshAlerts(settings, force: true, budgetMs: 300, requestMs: 200) }
        XCTAssertEqual(hung?.status.kind, .quiet)
        XCTAssertLessThan(elapsed, 2500, "не довше за строк і запас")
    }

    // сторінка віджета зберігається окремо для кожного віджета
    func testСторінкаВіджетаЗберігаєтьсяОкремо() {
        let env = Env()
        let t = env.at("2026-11-06T12:00:00+02:00").ms
        env.store.writePage("systemSmall|", "alert")
        env.store.writePage("systemMedium|", "light")
        XCTAssertEqual(env.store.readPage("systemSmall|"), PageChoice(page: "alert", at: t))
        XCTAssertEqual(env.store.readPage("systemMedium|")?.page, "light")
        XCTAssertNil(env.store.readPage("systemLarge|"))
    }

    // Новий (Swift): зламаний запис одного віджета не скидає вибір інших, а наступний запис його прибирає.
    func testЗламанийЗаписСторінкиНеЧіпаєІнших() {
        let env = Env()
        let t = env.at("2026-11-06T12:00:00+02:00").ms
        let raw = #"{"systemSmall|":{"page":"alert"},"systemMedium|":{"page":"alert","at":\#(t)}}"#
        env.kv.set(Data(raw.utf8), forKey: "page")
        XCTAssertNil(env.store.readPage("systemSmall|"))
        XCTAssertEqual(env.store.readPage("systemMedium|"), PageChoice(page: "alert", at: t))
        env.store.writePage("systemLarge|", "alert")
        XCTAssertEqual(env.store.readPage("systemMedium|"), PageChoice(page: "alert", at: t))
        XCTAssertEqual(env.store.readPage("systemLarge|")?.page, "alert")
        XCTAssertNil(env.store.readPage("systemSmall|"))
    }

    // місця: з мережі раз на тиждень; без мережі — збережені, без них — лише області
    func testМісцяРазНаТижденьБезМережіЗбережені() async {
        let env = Env()
        env.at("2026-11-06T12:00:00+02:00")
        let oblasts: [[String: Any]] = [["uid": "12", "title": "Запорізька область", "raions": [Any]()]]
        env.http.routes = [LOCATIONS_URL: .json(["ok": true, "oblasts": oblasts])]
        let first = await env.store.loadLocations()
        XCTAssertEqual(first.count, 1)
        env.http.clearRequests()
        env.clock.advance(86_400_000)
        let cached = await env.store.loadLocations()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(env.http.requests, [])
        env.reset()
        let fallback = await env.store.loadLocations()
        XCTAssertEqual(fallback.count, 27)
    }

    // канал у налаштуваннях: публічний канал — так, сторінка без каналу — ні
    func testКаналУНалаштуванняхПублічнийТакБезКаналуНі() async throws {
        let env = Env()
        env.at("2026-11-06T12:00:00+02:00")
        env.http.routes = [
            CHANNEL_URL: .text(channelPage([("2026-11-06T09:55:00+00:00", "Тестовий допис")])),
            "https://t.me/s/nothing_here": .text("<html><head><meta property=\"og:title\" content=\"Telegram\"></head></html>"),
        ]
        let found = try await env.store.checkChannel("test_monitor")
        XCTAssertEqual(found?.title, "Тестовий моніторинг & Ко")
        let none = try await env.store.checkChannel("nothing_here")
        XCTAssertNil(none)
    }
}
