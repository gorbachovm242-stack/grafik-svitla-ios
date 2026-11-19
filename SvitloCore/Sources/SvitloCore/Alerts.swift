// Повітряна тривога: другий модуль віджета. Дані alerts.in.ua приходять через наш посередник на Cloudflare Workers
// (worker/maiak-alerts.mjs), бо alerts.in.ua не дозволяє вшивати свій токен у застосунок: у застосунку токенів немає.
// Телефон бере всі активні тривоги й сам обирає свої: обране місце нікуди не надсилається.
// Перенесено з scripting/scripts/Графік світла/alerts.ts і android/.../Alerts.java. Alert → AirAlert (у SwiftUI є Alert).
import Foundation

public enum AlertConfig {
    public static let feed = "https://maiak-alerts.maiak.workers.dev/v1/alerts"
    public static let locations = "https://maiak-alerts.maiak.workers.dev/v1/locations"
    public static let source = "https://alerts.in.ua"
    public static let officialApp = "https://apps.apple.com/ua/app/id1611955391" // офіційний застосунок «Повітряна тривога»
    public static let cacheSeconds: Double = 50 // тривоги не перепитувати частіше
    public static let staleMinutes: Double = 30 // старіші дані віджет позначає часом перевірки
    public static let oldMinutes: Double = 180 // такі старі дані вже не показуємо як стан
    public static let timerHours: Double = 24 // довші тривоги (окуповані території, роками) без живого таймера
    public static let locationsDays: Double = 7 // список місць оновлюємо раз на тиждень
    public static let postFreshMinutes: Double = 60 // старіші дописи каналу моніторингу не показуємо
    public static let busyPostMinutes: Double = 20 // свіжий допис каналу: щось відбувається
    public static let channelBusySeconds: Double = 45 // канал не перепитувати частіше, коли щось відбувається
    public static let channelQuietSeconds: Double = 150 // у тиші канал раз на 2,5 хвилини
    // Як часто просити iOS оновити віджет із тривогами: найкоротший проміжок, а не обіцянка.
    public static let quietRefreshMinutes: Double = 15
    public static let busyRefreshMinutes: Double = 5
}

// MARK: - Типи

public struct AirAlert: Codable, Equatable, Sendable {
    public var uid: String
    public var title: String
    public var kind: String // oblast, raion, hromada, city
    public var parent: String // для міста: UID громади, до якої воно належить
    public var oblast: String // UID області (визначає посередник за таблицею місць)
    public var raion: String // назва району
    public var type: String
    public var level: String // red: повітряна тривога, yellow: попередня загроза
    public var since: Millis // 0, якщо невідомо
    public var threats: [String]

    public init(
        uid: String, title: String = "", kind: String = "unknown", parent: String = "", oblast: String = "", raion: String = "",
        type: String = "air_raid", level: String = "", since: Millis = 0, threats: [String] = []
    ) {
        self.uid = uid
        self.title = title
        self.kind = kind
        self.parent = parent
        self.oblast = oblast
        self.raion = raion
        self.type = type
        self.level = level
        self.since = since
        self.threats = threats
    }
}

public struct AlertFeed: Codable, Equatable, Sendable {
    public var ok: Bool
    public var stale: Bool // посередник не дістав alerts.in.ua і віддав збережене
    public var fetchedAt: Millis // коли alerts.in.ua востаннє підтвердив цей стан
    public var alerts: [AirAlert]
    public init(ok: Bool = false, stale: Bool = false, fetchedAt: Millis = 0, alerts: [AirAlert] = []) {
        self.ok = ok
        self.stale = stale
        self.fetchedAt = fetchedAt
        self.alerts = alerts
    }
}

/// Що обрав користувач: область (або Київ, Севастополь), за бажанням район і громада. UID з alerts.in.ua.
public struct Place: Codable, Equatable, Sendable {
    public var oblast: String
    public var oblastTitle: String?
    public var raion: String?
    public var raionTitle: String?
    public var hromada: String?
    public var hromadaTitle: String?
    public init(
        oblast: String, oblastTitle: String? = nil, raion: String? = nil, raionTitle: String? = nil,
        hromada: String? = nil, hromadaTitle: String? = nil
    ) {
        self.oblast = oblast
        self.oblastTitle = oblastTitle
        self.raion = raion
        self.raionTitle = raionTitle
        self.hromada = hromada
        self.hromadaTitle = hromadaTitle
    }
}

/// Місце в списку: область → райони → громади.
public struct Location: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var title: String
    public var children: [Location]
    public var id: String { uid }
    public init(uid: String, title: String, children: [Location] = []) {
        self.uid = uid
        self.title = title
        self.children = children
    }
}

/// Налаштування модуля: чи показувати тривогу у віджеті, місце й канал моніторингу.
public struct AlertSettings: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var place: Place?
    public var channel: String? // назва публічного каналу Telegram
    public var channelTitle: String?
    public init(enabled: Bool? = nil, place: Place? = nil, channel: String? = nil, channelTitle: String? = nil) {
        self.enabled = enabled
        self.place = place
        self.channel = channel
        self.channelTitle = channelTitle
    }
    public var isOn: Bool { enabled == true }
}

public enum AlertKind: String, Codable, Sendable { case alert, threat, nearby, quiet, nodata, setup }

public struct AlertStatus: Codable, Equatable, Sendable {
    public var kind: AlertKind = .setup
    public var title = "Оберіть місце"
    public var sub = "Відкрийте «Графік світла»"
    public var subShort: String? // коротші подробиці для вузького віджета: «з 10:40» без загроз
    public var place = "" // обране місце, коротко
    public var where_ = "" // де оголошено тривогу: «уся область», район чи громада
    public var others: [String] = [] // інші тривоги в області, свій район першим
    public var since: Millis = 0 // початок тривоги
    public var timer = false // живий таймер від початку: лише для тривог, коротших за timerHours
    public var stale = false
    public var checked: String? // коли alerts.in.ua востаннє підтвердив стан: «10:42» або «13.11, 10:42»
    public var posts: [String] = [] // свіжі дописи каналу моніторингу: «16:45 · 2 шахеди на місто»
    public var channel: String? // назва каналу моніторингу
    public init() {}
}

public struct ChannelPost: Codable, Equatable, Sendable {
    public var at: Millis
    public var text: String
    public init(at: Millis, text: String) {
        self.at = at
        self.text = text
    }
}

public enum AlertLogic {}

// MARK: - Області

extension AlertLogic {
    /// Області й міста з окремими тривогами, поки повний список місць не завантажено.
    public static let oblasts: [(String, String)] = [
        ("31", "м. Київ"), ("4", "Вінницька область"), ("8", "Волинська область"), ("9", "Дніпропетровська область"),
        ("28", "Донецька область"), ("10", "Житомирська область"), ("11", "Закарпатська область"), ("12", "Запорізька область"),
        ("13", "Івано-Франківська область"), ("14", "Київська область"), ("15", "Кіровоградська область"), ("16", "Луганська область"),
        ("27", "Львівська область"), ("17", "Миколаївська область"), ("18", "Одеська область"), ("19", "Полтавська область"),
        ("5", "Рівненська область"), ("20", "Сумська область"), ("21", "Тернопільська область"), ("22", "Харківська область"),
        ("23", "Херсонська область"), ("3", "Хмельницька область"), ("24", "Черкаська область"), ("26", "Чернівецька область"),
        ("25", "Чернігівська область"), ("29", "Автономна Республіка Крим"), ("30", "м. Севастополь"),
    ]

    public static func defaultOblasts() -> [Location] { oblasts.map { Location(uid: $0.0, title: $0.1) } }

    /// Область графіка світла → область тривог: щоб перший вибір уже стояв на своїй області.
    static let regionOblast: [String: String] = [
        "zaporizhzhia": "12", "kyiv": "31", "dnipro-dnem": "9", "dnipro-cek": "9", "dnipropetrovsk": "9", "vinnytsia": "4", "volyn": "8",
        "donetsk": "28", "zhytomyr": "10", "zakarpattia": "11", "ivano-frankivsk": "13", "kyiv-oblast": "14", "kirovohrad": "15", "lviv": "27",
        "mykolaiv": "17", "odesa": "18", "poltava": "19", "rivne": "5", "sumy": "20", "ternopil": "21", "kharkiv": "22", "khmelnytskyi": "3",
        "cherkasy": "24", "chernivtsi": "26", "chernihiv": "25",
    ]

    public static func oblastForRegion(_ region: String?) -> String? {
        guard let region = region else { return nil }
        return regionOblast[region]
    }
}

// MARK: - Розбір відповідей посередника

extension AlertLogic {
    public static func parseAlertFeed(_ text: String) -> AlertFeed {
        var feed = AlertFeed()
        guard let root = jsonObject(text) as? [String: Any], let list = root["alerts"] as? [Any] else { return feed }
        feed.ok = (root["ok"] as? Bool) == true
        feed.stale = (root["stale"] as? Bool) == true
        feed.fetchedAt = jsonNumeric(root["fetchedAt"]) ?? 0
        for item in list {
            guard let m = item as? [String: Any] else { continue }
            let kind = jsonString(m["kind"])
            let type = jsonString(m["type"])
            feed.alerts.append(AirAlert(
                uid: jsonString(m["uid"]),
                title: jsonString(m["title"]),
                kind: kind.isEmpty ? "unknown" : kind,
                parent: jsonString(m["parent"]),
                oblast: jsonString(m["oblast"]),
                raion: jsonString(m["raion"]),
                type: type.isEmpty ? "air_raid" : type,
                level: jsonString(m["level"]),
                since: parseDate(jsonString(m["since"])) ?? 0,
                threats: (m["threats"] as? [Any] ?? []).map { jsonString($0) }
            ))
        }
        return feed
    }

    public static func parseLocations(_ text: String) -> [Location] {
        guard let root = jsonObject(text) as? [String: Any], let list = root["oblasts"] as? [Any] else { return [] }
        func node(_ m: [String: Any], _ kids: [Location] = []) -> Location {
            Location(uid: jsonString(m["uid"]), title: jsonString(m["title"]), children: kids)
        }
        func items(_ value: Any?) -> [[String: Any]] {
            (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }.filter { jsonTruthy($0["uid"]) }
        }
        return items(list).map { o in
            node(o, items(o["raions"]).map { r in node(r, items(r["hromadas"]).map { h in node(h) }) })
        }
    }
}

// MARK: - Місце

private let reCityPrefix = Re("^(м\\. [^ ]+(?: [^ ]+)?) та ")
private let reOblastEnd = Re(" область$")
private let reRaionEnd = Re(" район$")

extension AlertLogic {
    public static func placeTitle(_ p: Place) -> String {
        for t in [p.hromadaTitle, p.raionTitle, p.oblastTitle] { if let t = t, !t.isEmpty { return t } }
        return ""
    }

    /// «м. Запоріжжя та Запорізька територіальна громада» не влазить у віджет: «… ТГ».
    public static func shortTitle(_ title: String?) -> String {
        guard let title = title, !title.isEmpty else { return "" }
        return replaceFirst(replaceFirst(title, " територіальна громада", " ТГ"), "Автономна Республіка Крим", "АР Крим")
    }

    /// Ще коротше для малого віджета: «м. Запоріжжя та Запорізька ТГ» → «м. Запоріжжя», «Запорізька область» → «Запорізька обл.».
    public static func compactPlace(_ title: String?) -> String {
        let t = shortTitle(title)
        if let city = reCityPrefix.first(t) { return city.s(1) }
        return reRaionEnd.replaceLiteral(reOblastEnd.replaceLiteral(t, " обл."), " р-н")
    }

    /// Як `String.replace` у JavaScript з рядком: лише перший збіг.
    static func replaceFirst(_ text: String, _ what: String, _ with: String) -> String {
        guard let r = text.range(of: what) else { return text }
        return text.replacingCharacters(in: r, with: with)
    }

    /// Зламаний чи неповний запис місця: громада без району не має сенсу.
    public static func cleanPlace(_ p: Place?) -> Place? {
        guard let p = p, !p.oblast.isEmpty else { return nil }
        var out = Place(oblast: p.oblast, oblastTitle: p.oblastTitle)
        if let raion = p.raion, !raion.isEmpty {
            out.raion = raion
            out.raionTitle = p.raionTitle
            if let hromada = p.hromada, !hromada.isEmpty {
                out.hromada = hromada
                out.hromadaTitle = p.hromadaTitle
            }
        }
        return out
    }
}

// MARK: - Стан для обраного місця

extension AlertLogic {
    /// Тривога стосується місця, якщо оголошена в його області, районі чи громаді, або в місті цієї громади
    /// (у великих містах тривогу оголошують окремо: «м. Запоріжжя» 5564 належить громаді 564).
    public static func matches(_ a: AirAlert, _ p: Place) -> Bool {
        if a.uid == p.oblast { return true }
        if let raion = p.raion, !raion.isEmpty, a.uid == raion { return true }
        if let hromada = p.hromada, !hromada.isEmpty, a.uid == hromada || (a.kind == "city" && a.parent == hromada) { return true }
        return false
    }

    /// Жовтий рівень alerts.in.ua: попередня загроза, ще не повітряна тривога.
    static func yellow(_ a: AirAlert) -> Bool { a.level == "yellow" }

    public static func active(_ s: AlertStatus?) -> Bool {
        guard let s = s else { return false }
        return s.kind == .alert || s.kind == .threat
    }

    static func rank(_ a: AirAlert) -> Int {
        if a.kind == "hromada" || a.kind == "city" { return 3 }
        if a.kind == "raion" { return 2 }
        return 1
    }

    public static func typeText(_ type: String) -> String {
        switch type {
        case "artillery_shelling": return "Загроза обстрілу"
        case "urban_fights": return "Вуличні бої"
        case "chemical": return "Хімічна загроза"
        case "nuclear": return "Радіаційна загроза"
        default: return "Повітряна тривога"
        }
    }

    static let threatWords: [String: String] = [
        "drones": "БпЛА", "ballistic_missiles": "балістика", "cruise_missiles": "крилаті ракети", "unspecified_missiles": "ракети",
        "guided_aerial_bombs": "КАБи", "tactic_aircraft_activity": "тактична авіація", "strategic_aircraft_activity": "стратегічна авіація",
        "mig31k_departure": "МіГ-31К", "air_defense": "робота ППО",
    ]

    /// «БпЛА, балістика»: не більше двох, без повторів.
    public static func threatText(_ threats: [String]) -> String? {
        var words: [String] = []
        for t in threats {
            if let w = threatWords[t], !words.contains(w) { words.append(w) }
        }
        return words.isEmpty ? nil : words.prefix(2).joined(separator: ", ")
    }

    static func isCity(_ p: Place) -> Bool { p.oblastTitle?.hasPrefix("м. ") == true }

    /// З якого часу: сьогодні «з 10:40», цього року «з 13.11, 22:10», давніше «з 04.04.2022».
    public static func alertSince(_ since: Millis, _ nowMs: Millis) -> String {
        if since <= 0 { return "триває" }
        let at = Logic.kyivParts(ms: since)
        let now = Logic.kyivParts(ms: nowMs)
        let time = Logic.hm(at.min)
        if at.ymd == now.ymd { return "з \(time)" }
        let p = Logic.ymdParts(at.ymd)
        let day = "\(pad(p.d)).\(pad(p.m))"
        if p.y == Logic.ymdParts(now.ymd).y { return "з \(day), \(time)" }
        return "з \(day).\(p.y)"
    }

    /// Коли alerts.in.ua востаннє підтвердив стан: сьогодні лише час, інакше ще й дата.
    public static func checkedText(_ fetchedAt: Millis, _ nowMs: Millis) -> String {
        let at = Logic.kyivParts(ms: fetchedAt)
        let now = Logic.kyivParts(ms: nowMs)
        let time = Logic.hm(at.min)
        if at.ymd == now.ymd { return time }
        let p = Logic.ymdParts(at.ymd)
        return "\(pad(p.d)).\(pad(p.m)), \(time)"
    }

    /// Найточніша тривога для місця: громада чи місто, далі район, далі область.
    static func pick(_ feed: AlertFeed, _ place: Place, _ wantYellow: Bool) -> AirAlert? {
        var best: AirAlert? = nil
        for a in feed.alerts where matches(a, place) && yellow(a) == wantYellow {
            if best == nil || rank(a) > rank(best!) { best = a }
        }
        return best
    }

    public static func alertStatus(_ placeIn: Place?, _ feed: AlertFeed?, _ nowMs: Millis) -> AlertStatus {
        var s = AlertStatus()
        guard let place = cleanPlace(placeIn) else { return s }
        s.place = shortTitle(placeTitle(place))
        guard let feed = feed, feed.ok, feed.fetchedAt > 0 else {
            s.kind = .nodata
            s.title = "Немає даних"
            s.sub = "Перевірте інтернет і оновіть"
            return s
        }
        let age = nowMs - feed.fetchedAt
        let checked = checkedText(feed.fetchedAt, nowMs)
        s.checked = checked
        s.stale = feed.stale || age > AlertConfig.staleMinutes * 60000
        if age > AlertConfig.oldMinutes * 60000 {
            s.kind = .nodata
            s.title = "Немає свіжих даних"
            s.sub = "Остання перевірка: \(checked)"
            return s
        }
        // Тривога (червоний рівень) важливіша за попередню загрозу (жовтий): спершу шукаємо її.
        var threatOnly = false
        var here = pick(feed, place, false)
        if here == nil {
            here = pick(feed, place, true)
            threatOnly = here != nil
        }
        var since = Double.infinity
        var threats: [String] = []
        for a in feed.alerts where matches(a, place) && yellow(a) == threatOnly {
            if a.since > 0 { since = min(since, a.since) }
            threats.append(contentsOf: a.threats)
        }
        // Інші повітряні тривоги в області (без попередніх загроз): свій район першим.
        var own: [String] = []
        for a in feed.alerts {
            if matches(a, place) || place.oblast != a.oblast || a.type != "air_raid" || yellow(a) { continue }
            if let raionTitle = place.raionTitle, !raionTitle.isEmpty, raionTitle == a.raion {
                own.append(shortTitle(a.title))
            } else {
                s.others.append(shortTitle(a.title))
            }
        }
        let inOwnRaion = !own.isEmpty
        s.others.insert(contentsOf: own, at: 0)
        if let here = here {
            s.kind = threatOnly ? .threat : .alert
            s.title = threatOnly && here.type == "air_raid" ? "Попередня загроза" : typeText(here.type)
            s.since = since == .infinity ? 0 : since
            s.timer = s.since > 0 && nowMs - s.since >= 0 && nowMs - s.since < AlertConfig.timerHours * 3_600_000
            let threat = threatText(threats)
            let short = alertSince(s.since, nowMs)
            s.subShort = short
            s.sub = short + (threat.map { " · \($0)" } ?? "")
            // Де саме оголошено, якщо це не те саме, що обране місце: «уся область», район.
            let whereText = here.kind == "oblast" ? (isCity(place) ? "" : "уся область") : shortTitle(here.title)
            s.where_ = whereText == s.place ? "" : whereText
            return s
        }
        if !s.others.isEmpty {
            s.kind = .nearby
            let list = s.others.count > 1 ? "\(s.others[0]) і ще \(s.others.count - 1)" : s.others[0]
            if place.raion == nil {
                s.title = "Тривога в частині області"
                s.sub = list
            } else if place.hromada == nil && inOwnRaion {
                s.title = "Тривога в частині району"
                s.sub = list
            } else {
                s.title = "Тут тихо"
                s.sub = "\(inOwnRaion ? "поруч: " : "в області: ")\(list)"
            }
            return s
        }
        s.kind = .quiet
        s.title = "Тривоги немає"
        s.sub = isCity(place) ? "тихо в усьому місті" : "тихо в усій області"
        return s
    }

    /// Коротка назва стану (застосунок, екран блокування).
    public static func alertShortTitle(_ s: AlertStatus) -> String {
        switch s.kind {
        case .alert: return s.title == "Повітряна тривога" ? "Тривога" : s.title
        case .threat: return s.title == "Попередня загроза" ? "Загроза" : s.title
        case .nearby: return s.title == "Тривога в частині області" ? "Частина області" : "Тривога поруч"
        case .quiet: return "Тихо"
        case .nodata: return "Немає даних"
        case .setup: return "Оберіть місце"
        }
    }

    /// Напис біля значка тривоги на сторінці світла, коли щось не так; у тиші жодного.
    /// Короткий варіант для тісного місця: поруч стоїть значок сирени, тож «з 10:40» читається як «тривога з 10:40».
    public static func alertPill(_ s: AlertStatus, short shortForm: Bool) -> String? {
        let sub = s.subShort ?? ""
        let since = !sub.isEmpty && sub.hasPrefix("з ") && sub.count <= 7
        switch s.kind {
        case .alert:
            if shortForm { return since ? sub : "Тривога" }
            return since ? "Тривога \(sub)" : "Повітряна тривога"
        case .threat: return shortForm ? "Загроза" : "Попередня загроза"
        case .nearby: return shortForm ? "Поруч" : "Тривога поруч"
        case .nodata: return "Немає даних"
        case .setup: return "Оберіть місце"
        case .quiet: return nil
        }
    }
}

// MARK: - Канал моніторингу
// Користувач може підключити публічний Telegram-канал, де пишуть, що летить і куди. Формати в каналів різні,
// тож нічого не розбираємо: віджет показує останні свіжі дописи дослівно, з часом.

private let reOgTitle = Re("<meta property=\"og:title\" content=\"([^\"]*)\"")

extension AlertLogic {
    public static func channelUrl(_ id: String) -> String { "https://t.me/s/\(id)" }

    static func plain(_ html: String) -> String {
        var s = Re("<br\\s*/?>", ignoreCase: true).replaceLiteral(html, " ")
        s = Re("<[^>]+>").replaceLiteral(s, " ")
        s = Re("&#39;|&apos;|&#x27;").replaceLiteral(s, "'")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        return Re("\\s+").replaceLiteral(s, " ").trimmed
    }

    /// Будь-який публічний канал на t.me/s/канал: текст і час кожного допису, старіші першими. Дописи без тексту пропускаємо.
    public static func parseChannelPosts(_ html: String) -> [ChannelPost] {
        var out: [ChannelPost] = []
        for m in reTelegramPost.all(html) {
            let text = plain(m.s(1))
            if !text.isEmpty, let at = parseDate(m.s(2)) { out.append(ChannelPost(at: at, text: text)) }
        }
        return out
    }

    /// Назва каналу зі сторінки t.me/s: «Моніторинг Запоріжжя».
    public static func parseChannelTitle(_ html: String) -> String? {
        let title = reOgTitle.first(html).map { plain($0.s(1)) } ?? ""
        return title.isEmpty ? nil : title
    }

    /// Свіжі дописи (не старші за postFreshMinutes), найновіші першими.
    public static func freshPosts(_ posts: [ChannelPost]?, _ nowMs: Millis, _ limit: Int) -> [ChannelPost] {
        var out: [ChannelPost] = []
        for p in (posts ?? []).reversed() {
            if out.count >= limit { break }
            let age = nowMs - p.at
            if age >= -5 * 60000 && age <= AlertConfig.postFreshMinutes * 60000 { out.append(p) }
        }
        return out
    }

    public static func postLine(_ p: ChannelPost) -> String { "\(Logic.hm(Logic.kyivParts(ms: p.at).min)) · \(p.text)" }

    /// Додає до стану свіжі дописи каналу (до трьох). Без місця нічого не додаємо.
    public static func withPosts(_ s: AlertStatus, _ posts: [ChannelPost]?, _ title: String?, _ nowMs: Millis) -> AlertStatus {
        if s.kind == .setup { return s }
        var out = s
        out.posts = freshPosts(posts, nowMs, 3).map(postLine)
        out.channel = title
        return out
    }

    /// «Щось відбувається»: тривога чи загроза тут, тривога поруч або свіжий допис каналу моніторингу
    /// (канали часто пишуть раніше, ніж оголошують тривогу). Тоді й канал, і віджет перевіряємо частіше.
    public static func busy(_ s: AlertStatus?, _ posts: [ChannelPost]?, _ nowMs: Millis) -> Bool {
        if let s = s, active(s) || s.kind == .nearby { return true }
        return (posts ?? []).contains { p in
            let age = nowMs - p.at
            return age >= -5 * 60000 && age <= AlertConfig.busyPostMinutes * 60000
        }
    }

    /// Посилання, «@назва» чи сама назва каналу: лишаємо назву (як Logic.channelId).
    public static func channelName(_ input: String) -> String { Logic.channelId(input) }
}

// MARK: - Сторінки віджета
// Модуль світла є завжди, тривога — якщо її ввімкнено. Тоді праворуч у віджеті стовпчик значків:
// дотик до значка показує сторінку модуля. Обрана сторінка тримається pageHoldMinutes, потім знову світло.

public struct PageChoice: Codable, Equatable, Sendable {
    public var page: String
    public var at: Millis
    public init(page: String, at: Millis) {
        self.page = page
        self.at = at
    }
}

public struct PageMode: Equatable, Sendable {
    public var page: String
    public var until: Millis?
    public var quick: Bool
}

extension AlertLogic {
    public static let light = "light"
    public static let alert = "alert"
    public static let pageHoldMinutes: Double = 15
    public static let pageQuickSeconds: Double = 20 // одразу після дотику віджет малює збережене, без мережі

    public static func pagesOf(_ alertsOn: Bool) -> [String] { alertsOn ? [light, alert] : [light] }

    /// Вибір сторінки для кожного віджета окремо: ключ — розмір і адреса.
    public static func pageKey(_ family: String, _ parameter: String?) -> String {
        "\(family)|\((parameter ?? "").trimmed.lowercased())"
    }

    public static func pageMode(_ choice: PageChoice?, _ pages: [String], _ nowMs: Millis) -> PageMode {
        guard let choice = choice else { return PageMode(page: light, until: nil, quick: false) }
        let age = nowMs - choice.at
        let quick = age >= 0 && age < pageQuickSeconds * 1000
        let until = choice.at + pageHoldMinutes * 60000
        let held = age >= 0 && nowMs < until && pages.contains(choice.page)
        let page = held ? choice.page : light
        return PageMode(page: page, until: held && page != light ? until : nil, quick: quick)
    }

    /// Коли наступного разу оновити віджет з увімкненими тривогами: частіше, коли щось відбувається.
    public static func alertRefreshMinutes(_ s: AlertStatus?, _ posts: [ChannelPost]?, _ nowMs: Millis) -> Double {
        busy(s, posts, nowMs) ? AlertConfig.busyRefreshMinutes : AlertConfig.quietRefreshMinutes
    }
}
