// «Графік світла»: уся логіка графіка без звертань до iOS, щоб її можна було перевірити тестами.
// Перенесено з scripting/scripts/Графік світла/logic.ts (2.1.0) і android/.../Logic.java; назви ті самі,
// крім двох: View → Glance (у SwiftUI вже є View) і Data → LightData (у Foundation вже є Data).
// Години подаються за київським часом. Дані: офіційний сайт Запоріжжяобленерго та спільні дані обленерго.
import Foundation

public enum Timing {
    public static let cacheMinutes: Double = 10 // не перевіряти джерело частіше
    // Між змінами просимо iOS оновлювати віджет раз на 30 хвилин: частіші запити вичерпують її денний ліміт.
    // У нативному віджеті кожна зміна графіка — окремий запис таймлайну, тож сама зміна не чекає оновлення.
    public static let refreshMinutes: Double = 30
    public static let staleMinutes: Double = 180 // після цього показувати, що дані застарілі
    public static let noticeMinutes = 10 // за скільки хвилин попереджати про вимкнення й увімкнення
    public static let timeoutSeconds: Double = 8 // очікування одного джерела
    // Спільний крайній строк для всіх запитів одного запуску: без інтернету запит буває висить,
    // а iOS тим часом зупиняє віджет. Після строку малюємо збережене.
    public static let widgetBudgetMs: Double = 8000
    public static let widgetRequestMs: Double = 5000
    public static let buttonBudgetMs: Double = 10000 // кнопка «↻»
    public static let pageBudgetMs: Double = 4000 // дотик до значка тривоги
    public static let appBudgetMs: Double = 25000 // застосунок
    public static let offlineRetryMinutes: Double = 5 // після невдалої спроби віджет стільки не йде в мережу
    public static let factCacheMinutes: Double = 4 // датчик СвітлоБота не перепитувати частіше
    public static let factRefreshMinutes: Double = 15 // з датчиком віджет просить оновлення частіше
    public static let factStaleMinutes: Double = 60 // старіші дані датчика позначаємо часом перевірки
}

public enum URLs {
    public static let zoe = "https://www.zoe.com.ua/outage/"
    public static let zoeQueue =
        "https://script.google.com/macros/s/AKfycbwFgBo9W8JL_7FqghJ1hDiE-Fyxzs4GZJAq2xhTseOiv5ZnkusMKj0_g9R0DJKko19r/exec"
    public static let feedNew = "https://dtek-api.svitlo-proxy.workers.dev/"
    public static let feedGithub = "https://raw.githubusercontent.com/chaichuk/UA-power-outages-monitor/main/artifacts/last-message.json"
    public static let feedOld = "https://svitlo-proxy.svitlo-proxy.workers.dev"
}

/// Як браузер на iPhone: деякі джерела не відповідають запитам без цього заголовка.
public let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

public let zoeGroups = ["1.1", "1.2", "2.1", "2.2", "3.1", "3.2", "4.1", "4.2", "5.1", "5.2", "6.1", "6.2"]

/// ids: назви регіону в спільних даних (у двох джерелах вони різні). oldOnly: регіон є лише в старому джерелі.
public struct Region: Equatable, Hashable {
    public let id: String
    public let name: String
    public let ids: [String]
    public var official = false
    public var oldOnly = false
}

public let regions: [Region] = [
    Region(id: "zaporizhzhia", name: "м. Запоріжжя та область", ids: ["zaporizka-oblast"], official: true),
    Region(id: "kyiv", name: "м. Київ", ids: ["kyiv"]),
    Region(id: "dnipro-dnem", name: "м. Дніпро (ДнЕМ)", ids: ["dnipro-dnem"]),
    Region(id: "dnipro-cek", name: "м. Дніпро (ЦЕК)", ids: ["dnipro-cek"]),
    Region(id: "vinnytsia", name: "Вінницька", ids: ["vinnitska-oblast"], oldOnly: true),
    Region(id: "volyn", name: "Волинська", ids: ["volinska-oblast"], oldOnly: true),
    Region(id: "dnipropetrovsk", name: "Дніпропетровська", ids: ["dnipropetrovska-oblast"]),
    Region(id: "donetsk", name: "Донецька", ids: ["donetska-oblast"], oldOnly: true),
    Region(id: "zhytomyr", name: "Житомирська", ids: ["zhytomyrska-oblast", "jitomirska-oblast"]),
    Region(id: "zakarpattia", name: "Закарпатська", ids: ["zakarpatska-oblast"]),
    Region(id: "ivano-frankivsk", name: "Івано-Франківська", ids: ["ivano-frankivska-oblast"]),
    Region(id: "kyiv-oblast", name: "Київська", ids: ["kiivska-oblast"]),
    Region(id: "kirovohrad", name: "Кіровоградська", ids: ["kirovogradska-oblast"], oldOnly: true),
    Region(id: "lviv", name: "Львівська", ids: ["lvivska-oblast"]),
    Region(id: "mykolaiv", name: "Миколаївська", ids: ["mikolaivska-oblast"], oldOnly: true),
    Region(id: "odesa", name: "Одеська", ids: ["odeska-oblast"]),
    Region(id: "poltava", name: "Полтавська", ids: ["poltavska-oblast"]),
    Region(id: "rivne", name: "Рівненська", ids: ["rivnenska-oblast"]),
    Region(id: "sumy", name: "Сумська", ids: ["sumska-oblast"], oldOnly: true),
    Region(id: "ternopil", name: "Тернопільська", ids: ["ternopilska-oblast"]),
    Region(id: "kharkiv", name: "Харківська", ids: ["kharkivska-oblast", "harkivska-oblast"]),
    Region(id: "khmelnytskyi", name: "Хмельницька", ids: ["khmelnytska-oblast", "hmelnitska-oblast"]),
    Region(id: "cherkasy", name: "Черкаська", ids: ["cherkaska-oblast"]),
    Region(id: "chernivtsi", name: "Чернівецька", ids: ["chernivetska-oblast"]),
    Region(id: "chernihiv", name: "Чернігівська", ids: ["chernihivska-oblast", "chernigivska-oblast"]),
]

let monthIndex: [String: Int] = [
    "січня": 1, "лютого": 2, "березня": 3, "квітня": 4, "травня": 5, "червня": 6,
    "липня": 7, "серпня": 8, "вересня": 9, "жовтня": 10, "листопада": 11, "грудня": 12,
]

// MARK: - Типи

public enum Status: String, Codable, Sendable { case on, off, maybe, unknown }

/// Відрізок дня: s і e у хвилинах від півночі (на спільній осі двох діб — до 2880).
public struct Run: Codable, Equatable, Hashable, Sendable {
    public var s: Int
    public var e: Int
    public var st: Status
    public init(s: Int, e: Int, st: Status) {
        self.s = s
        self.e = e
        self.st = st
    }
}

public enum DayStatus: String, Codable, Sendable { case ok, check, none }

public struct Day: Codable, Equatable, Sendable {
    public var status: DayStatus
    public var runs: [Run]
    public init(status: DayStatus, runs: [Run]) {
        self.status = status
        self.runs = runs
    }
}

public struct Sched: Codable, Equatable, Sendable {
    public var days: [String: Day]
    public var emergency: Bool
    public var warn: Bool?
    public var key: String?
    public var fetchedAt: Millis?
    public init(days: [String: Day], emergency: Bool = false, warn: Bool? = nil, key: String? = nil, fetchedAt: Millis? = nil) {
        self.days = days
        self.emergency = emergency
        self.warn = warn
        self.key = key
        self.fetchedAt = fetchedAt
    }
}

/// Друга адреса: своя область і черга, а сповіщення, вигляд і фон спільні з першою.
public struct Address: Codable, Equatable, Sendable {
    public var name: String?
    public var region: String
    public var group: String
    public init(name: String? = nil, region: String, group: String) {
        self.name = name
        self.region = region
        self.group = group
    }
}

/// Налаштування. Три сповіщення, кожне можна вимкнути; не задано — увімкнено.
public struct Config: Codable, Equatable, Sendable {
    public var region: String
    public var group: String
    public var notifyChange: Bool? // графік черги змінився або зʼявився новий
    public var notifyOff: Bool? // за 10 хвилин до відключення
    public var notifyOn: Bool? // за 10 хвилин до ввімкнення
    public var style: String?
    public var look: String?
    public var lockLook: String?
    public var svitlobot: String? // канал датчика СвітлоБота: чи є світло насправді
    public var svitlobotName: String? // його назва-адреса для налаштувань
    public var name: String? // назва першої адреси, коли адрес дві («Дім»)
    public var second: Address? // друга адреса: батьки, робота, дача
    // Лише в памʼяті, не зберігаються: яка це адреса (0 перша, 1 друга) і її назва, коли адрес дві.
    public var slot: Int?
    public var place: String?

    enum CodingKeys: String, CodingKey {
        case region, group, notifyChange, notifyOff, notifyOn, style, look, lockLook, svitlobot, svitlobotName, name, second
    }

    public init(
        region: String, group: String, notifyChange: Bool? = nil, notifyOff: Bool? = nil, notifyOn: Bool? = nil,
        style: String? = nil, look: String? = nil, lockLook: String? = nil, svitlobot: String? = nil, svitlobotName: String? = nil,
        name: String? = nil, second: Address? = nil, slot: Int? = nil, place: String? = nil
    ) {
        self.region = region
        self.group = group
        self.notifyChange = notifyChange
        self.notifyOff = notifyOff
        self.notifyOn = notifyOn
        self.style = style
        self.look = look
        self.lockLook = lockLook
        self.svitlobot = svitlobot
        self.svitlobotName = svitlobotName
        self.name = name
        self.second = second
        self.slot = slot
        self.place = place
    }
}

public let firstName = "Дім"
public let secondName = "Друга адреса"

public struct NotifyPrefs: Equatable, Sendable {
    public var change: Bool
    public var off: Bool
    public var on: Bool
    public init(change: Bool = true, off: Bool = true, on: Bool = true) {
        self.change = change
        self.off = off
        self.on = on
    }
}

public enum FetchStatus: String, Codable, Sendable { case ok, nogroup, fail }

/// Дані однієї адреси: графік, чи вдалося його дістати, і стан датчика.
public struct LightData: Equatable, Sendable {
    public var sched: Sched?
    public var status: FetchStatus
    public var fact: Fact?
    public init(sched: Sched?, status: FetchStatus, fact: Fact? = nil) {
        self.sched = sched
        self.status = status
        self.fact = fact
    }
}

/// Момент за Києвом: дата «2026-11-06» і хвилина доби.
public struct Now: Equatable, Hashable, Sendable {
    public var ymd: String
    public var min: Int
    public init(ymd: String, min: Int) {
        self.ymd = ymd
        self.min = min
    }
}

public enum LightKind: String, Codable, Sendable { case setup, nogroup, nodata, on, off, maybe, check, none }

/// Що показати: заголовок, подробиці, години відключень, коли наступна зміна. У logic.ts це View.
public struct Glance: Equatable, Sendable {
    public var kind: LightKind = .setup
    public var title = "Оберіть чергу"
    public var sub = "Відкрийте «Графік світла»"
    public var group: String?
    public var style: String?
    public var look: String?
    public var lockLook: String?
    public var nowMin = 0
    public var todayRuns: [Run] = []
    public var todayWindows: [Run] = []
    public var windowsLeft: [Run] = []
    public var tomorrowRuns: [Run]?
    public var tomorrowWindows: [Run]?
    public var runFrom: Int?
    public var changeMin: Int?
    public var short = "—"
    public var notice: String?
    public var noticeShort: String?
    public var stale = false
    public var checked: Int?
    public var fact: FactGlance? // що каже датчик СвітлоБота, якщо його обрано
    public var place: String? // назва адреси («Дім», «Батьки»), коли адрес дві
    public init() {}
}

public enum Logic {}

// MARK: - Адреси

extension Logic {
    public static func hasSecond(_ cfg: Config?) -> Bool {
        guard let second = cfg?.second else { return false }
        return !second.region.isEmpty && !second.group.isEmpty
    }

    /// Адреси з налаштувань: перша завжди, друга, якщо задана. Кожна стає окремим Config зі своєю чергою.
    /// Власний датчик СвітлоБота буває лише в першої адреси, друга бере факт за датчиками своєї черги.
    public static func addressesOf(_ cfg: Config?) -> [Config] {
        guard var first = cfg else { return [] }
        guard hasSecond(first), let second = first.second else {
            first.slot = 0
            return [first]
        }
        var two = first
        two.region = second.region
        two.group = second.group
        two.slot = 1
        two.place = (second.name?.isEmpty == false ? second.name : nil) ?? secondName
        two.svitlobot = nil
        two.svitlobotName = nil
        first.slot = 0
        first.place = (first.name?.isEmpty == false ? first.name : nil) ?? firstName
        return [first, two]
    }

    /// Яку адресу показує віджет: «2», «друга» чи назва другої адреси — другу.
    public static func slotFromParameter(_ parameter: String?, _ cfg: Config?) -> Int {
        guard let cfg = cfg, hasSecond(cfg) else { return 0 }
        let p = (parameter ?? "").trimmed.lowercased()
        if p.isEmpty { return 0 }
        let name = (cfg.second?.name ?? "").trimmed.lowercased()
        return p == "2" || p.hasPrefix("друг") || (!name.isEmpty && p == name) ? 1 : 0
    }

    public static func notifyPrefs(_ cfg: Config) -> NotifyPrefs {
        NotifyPrefs(change: cfg.notifyChange != false, off: cfg.notifyOff != false, on: cfg.notifyOn != false)
    }
}

// MARK: - Час

extension Logic {
    /// Київський пояс; якщо його нема в базі поясів — стара назва, а далі пояс телефона.
    public static let kyiv: TimeZone = TimeZone(identifier: "Europe/Kyiv") ?? TimeZone(identifier: "Europe/Kiev") ?? .current

    static let kyivCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = kyiv
        return cal
    }()

    /// Години подаються за київським часом, навіть якщо телефон за кордоном.
    public static func kyivParts(_ date: Date) -> Now {
        let c = kyivCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let ymd = "\(c.year ?? 1970)-\(pad(c.month ?? 1))-\(pad(c.day ?? 1))"
        return Now(ymd: ymd, min: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    public static func kyivParts(ms: Millis) -> Now { kyivParts(Date(ms: ms)) }

    static func ymdParts(_ ymd: String) -> (y: Int, m: Int, d: Int) {
        let p = ymd.parts("-").map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 1970, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    public static func addDays(_ ymd: String, _ days: Int) -> String {
        let p = ymdParts(ymd)
        let c = civilFromDays(daysFromCivil(p.y, p.m, p.d) + days)
        return "\(c.y)-\(pad(c.m))-\(pad(c.d))"
    }

    public static func hm(_ min: Int) -> String {
        "\(pad(floorDiv(min, 60))):\(pad(jsMod(min, 60)))"
    }

    /// «о 13:30», але «об 11:30».
    public static func at(_ min: Int) -> String {
        "\(floorDiv(min, 60) == 11 ? "об" : "о") \(hm(min))"
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }
    /// Остача зі знаком діленого, як `%` у JavaScript.
    static func jsMod(_ a: Int, _ b: Int) -> Int { a % b }
}

// MARK: - Графік: спільна форма даних

extension Logic {
    public static func mergeRuns(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for r in runs {
            if r.e <= r.s { continue }
            if let last = out.last, last.st == r.st, last.e == r.s {
                out[out.count - 1].e = r.e
            } else {
                out.append(Run(s: r.s, e: r.e, st: r.st))
            }
        }
        return out
    }

    public static func runsFromOff(_ ranges: [(Int, Int)]) -> [Run] {
        var runs: [Run] = []
        var pos = 0
        for (s, e) in ranges.sorted(by: { $0.0 < $1.0 }) {
            if s > pos { runs.append(Run(s: pos, e: s, st: .on)) }
            runs.append(Run(s: max(s, pos), e: e, st: .off))
            pos = max(pos, e)
        }
        if pos < 1440 { runs.append(Run(s: pos, e: 1440, st: .on)) }
        return mergeRuns(runs)
    }
}

// MARK: - Офіційний сайт Запоріжжяобленерго

/// Допис на сайті обленерго: заголовок, дата з нього, години відключень кожної черги.
public struct Post: Equatable {
    public var title: String
    public var day: Int?
    public var month: Int?
    public var groups: [String: [[Int]]]
    public var exact: Bool
}

private let reBreaks = Re("<br\\s*/?>|</p>|</div>|</li>", ignoreCase: true)
private let reTags = Re("<[^>]+>")
private let reDashes = Re("&#8211;|&#8212;|&ndash;|&mdash;")
private let reNbsp = Re("&nbsp;|&#160;")
private let reDate = Re("([0-9]{1,2})\\s+(січня|лютого|березня|квітня|травня|червня|липня|серпня|вересня|жовтня|листопада|грудня)")
private let reRange = Re("([0-9]{1,2})[:.]([0-9]{2})\\s*[–—-]\\s*([0-9]{1,2})[:.]([0-9]{2})")
private let reTime = Re("[0-9]{1,2}[:.][0-9]{2}")
private let reArticle = Re("<article[^>]*>([\\s\\S]*?)</article>", ignoreCase: true)
private let reHeading = Re("<h2[^>]*>([\\s\\S]*?)</h2>", ignoreCase: true)
private let reGroupLine = Re("^([0-9]\\.[0-9])\\s*[:.–—-]\\s*(.+)$")
private let reSchedTitle = Re("ГПВ|ГРАФІК", ignoreCase: true)

extension Logic {
    static func stripHtml(_ html: String) -> String {
        var s = reBreaks.replaceLiteral(html, "\n")
        s = reTags.replaceLiteral(s, " ")
        s = reDashes.replaceLiteral(s, "–")
        return reNbsp.replaceLiteral(s, " ")
    }

    static func findDate(_ text: String) -> (day: Int, month: Int)? {
        guard let m = reDate.first(text.lowercased()), let day = Int(m.s(1)), let month = monthIndex[m.s(2)] else { return nil }
        return (day, month)
    }

    public static func parseRanges(_ text: String) -> (ranges: [(Int, Int)], exact: Bool) {
        var ranges: [(Int, Int)] = []
        for m in reRange.all(text) {
            let s = (Int(m.s(1)) ?? 0) * 60 + (Int(m.s(2)) ?? 0)
            let e = (Int(m.s(3)) ?? 0) * 60 + (Int(m.s(4)) ?? 0)
            if s < e && e <= 1440 { ranges.append((s, e)) }
        }
        // Кожен час має належати до розібраного проміжку, інакше рядок прочитано неточно.
        let times = reTime.count(text)
        return (ranges, times == ranges.count * 2)
    }

    /// Дописи йдуть від найновішого до найстарішого.
    public static func parsePosts(_ html: String) -> [Post] {
        var posts: [Post] = []
        for article in reArticle.all(html) {
            let body = article.s(1)
            guard let heading = reHeading.first(body) else { continue }
            let title = stripHtml(heading.s(1)).trimmed
            if title.isEmpty { continue }
            let lines = stripHtml(body.utf16Suffix(from: heading.end))
                .parts("\n")
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
            var groups: [String: [[Int]]] = [:]
            var exact = true
            for line in lines {
                guard let g = reGroupLine.first(line) else { continue }
                let parsed = parseRanges(g.s(2))
                if !parsed.exact || parsed.ranges.isEmpty { exact = false }
                groups[g.s(1)] = parsed.ranges.map { [$0.0, $0.1] }
            }
            let date = findDate(title) ?? findDate(lines.first ?? "")
            posts.append(Post(title: title, day: date?.day, month: date?.month, groups: groups, exact: exact))
        }
        return posts
    }

    public static func dayFromPosts(_ posts: [Post], _ ymd: String, _ group: String) -> Day? {
        let p = ymdParts(ymd)
        guard let post = posts.first(where: { $0.month == p.m && $0.day == p.d && reSchedTitle.test($0.title) }) else { return nil }
        if !post.exact || post.groups.isEmpty { return Day(status: .check, runs: []) }
        // Обленерго перелічує лише черги з відключеннями. Немає черги в дописі: цього дня без відключень.
        let ranges = (post.groups[group] ?? []).map { ($0[0], $0[1]) }
        return Day(status: .ok, runs: runsFromOff(ranges))
    }
}

// MARK: - Спільні дані обленерго

/// Регіон у спільних даних: назва, аварійні відключення, графік черг за датами (48 півгодинних клітинок).
public struct FeedRegion {
    public var cpu: String
    public var emergency: Bool
    public var schedule: [String: [String: [String: Any]]]?
}

public struct Feed {
    public var regions: [FeedRegion]
}

public enum SvitloError: Error, Equatable {
    case format(String)
    case http(Int)
    case timeout
    case expired
    case offline
}

extension Logic {
    public static func dayFromFeed(_ slots: [String: Any]) -> Day {
        var runs: [Run] = []
        for i in 0..<48 {
            let key = "\(pad(i / 2)):\(i % 2 == 1 ? "30" : "00")"
            let code = jsonNumber(slots[key]) ?? .nan
            let st: Status = code == 1 ? .on : code == 2 ? .off : code == 3 ? .maybe : .unknown
            runs.append(Run(s: i * 30, e: i * 30 + 30, st: st))
        }
        if runs.allSatisfy({ $0.st == .unknown }) { return Day(status: .none, runs: []) }
        return Day(status: .ok, runs: mergeRuns(runs))
    }

    public static func parseFeed(_ text: String) throws -> Feed {
        var root = jsonObject(text) as? [String: Any]
        if let body = root?["body"] as? String { root = jsonObject(body) as? [String: Any] }
        guard let json = root, let list = json["regions"] as? [Any] else { throw SvitloError.format("Невідомий формат даних") }
        var out: [FeedRegion] = []
        for item in list {
            guard let r = item as? [String: Any] else { continue }
            var schedule: [String: [String: [String: Any]]]? = nil
            if let groups = r["schedule"] as? [String: Any] {
                var s: [String: [String: [String: Any]]] = [:]
                for (group, byDate) in groups {
                    guard let dates = byDate as? [String: Any] else { continue }
                    var d: [String: [String: Any]] = [:]
                    for (date, slots) in dates { d[date] = (slots as? [String: Any]) ?? [:] }
                    s[group] = d
                }
                schedule = s
            }
            let emergency = (r["emergency"] as? Bool) ?? ((jsonNumeric(r["emergency"]) ?? 0) != 0)
            out.append(FeedRegion(cpu: jsonString(r["cpu"]), emergency: emergency, schedule: schedule))
        }
        return Feed(regions: out)
    }

    public static func feedRegion(_ json: Feed, _ region: Region) -> FeedRegion? {
        json.regions.first { region.ids.contains($0.cpu) }
    }

    public static func scheduleFromFeed(_ json: Feed, _ region: Region, _ group: String) -> Sched? {
        guard let item = feedRegion(json, region), let byDate = item.schedule?[group] else { return nil }
        var days: [String: Day] = [:]
        for (date, slots) in byDate { days[date] = dayFromFeed(slots) }
        return Sched(days: days, emergency: item.emergency)
    }
}

// MARK: - Джерела

/// Завантажувач сторінки за адресою: на телефоні це мережа, у тестах підставні дані.
public typealias Load = (String) async throws -> String

public enum FetchResult: Equatable {
    case ok(Sched)
    case nogroup
    case fail

    public var status: FetchStatus {
        switch self {
        case .ok: return .ok
        case .nogroup: return .nogroup
        case .fail: return .fail
        }
    }
}

extension Logic {
    public static func regionById(_ id: String) -> Region? { regions.first { $0.id == id } }

    public static func sourcesFor(_ region: Region) -> [String] {
        let feeds = region.oldOnly ? [URLs.feedOld] : [URLs.feedNew, URLs.feedGithub, URLs.feedOld]
        return region.official ? ["official"] + feeds : feeds
    }

    static func usableDay(_ sched: Sched, _ ymd: String) -> Bool {
        guard let day = sched.days[ymd] else { return false }
        return !day.runs.isEmpty
    }

    public static func loadOfficial(_ load: Load, _ group: String, _ today: String) async throws -> Sched {
        let posts = parsePosts(try await load(URLs.zoe))
        if posts.isEmpty { throw SvitloError.format("На сторінці не знайдено дописів") }
        var days: [String: Day] = [:]
        for ymd in [today, addDays(today, 1)] {
            if let day = dayFromPosts(posts, ymd, group) { days[ymd] = day }
        }
        return Sched(days: days, emergency: false)
    }

    /// Перше джерело з графіком на сьогодні перемагає. Дані за інші дати сьогоднішні не замінюють.
    public static func fetchSchedule(
        _ cfg: Config, _ today: String, _ load: Load, budgetMs: Double = .infinity,
        clock: () -> Millis = { Date().ms }, log: (String) -> Void = { _ in }
    ) async -> FetchResult {
        guard let region = regionById(cfg.region) else { return .fail }
        let started = clock()
        var fallback: Sched? = nil
        var reached = false
        var mainFeedWorks = false
        var warn = false
        for source in sourcesFor(region) {
            if source == URLs.feedGithub && mainFeedWorks { continue } // там ті самі дані
            if clock() - started > budgetMs { break }
            do {
                let sched: Sched?
                if source == "official" {
                    sched = try await loadOfficial(load, cfg.group, today)
                } else {
                    sched = scheduleFromFeed(try parseFeed(try await load(source)), region, cfg.group)
                }
                reached = true
                if source == URLs.feedNew { mainFeedWorks = true }
                guard var found = sched else { continue }
                if found.days[today]?.status == .check { warn = true }
                if usableDay(found, today) {
                    found.warn = warn
                    return .ok(found)
                }
                if fallback == nil { fallback = found }
            } catch {
                log("\(source): \(error)")
            }
        }
        if var found = fallback {
            found.warn = warn
            return .ok(found)
        }
        return reached ? .nogroup : .fail
    }

    public static func sortGroups(_ groups: [String]) -> [String] {
        groups.sorted { a, b in
            if let fa = parseFloatPrefix(a), let fb = parseFloatPrefix(b), fa != fb { return fa < fb }
            return a < b
        }
    }

    public static func groupsFor(_ region: Region, _ load: Load) async throws -> [String] {
        if region.official { return zoeGroups }
        let json = try parseFeed(try await load(region.oldOnly ? URLs.feedOld : URLs.feedNew))
        return sortGroups(Array((feedRegion(json, region)?.schedule ?? [:]).keys))
    }
}

// MARK: - Стан на зараз

public struct LightState {
    public var kind: LightKind
    public var index: Int?
    public var line: [Run]
    public var current: Run? { index.map { line[$0] } }
    public var next: Run? {
        guard let i = index, i + 1 < line.count else { return nil }
        return line[i + 1]
    }
}

extension Logic {
    /// Дві доби на одній осі: сьогоднішні хвилини 0..1440, завтрашні 1440..2880.
    public static func timeline(_ sched: Sched, _ today: String) -> [Run] {
        var line: [Run] = []
        for (i, ymd) in [today, addDays(today, 1)].enumerated() {
            guard let day = sched.days[ymd] else { continue }
            for r in day.runs { line.append(Run(s: r.s + i * 1440, e: r.e + i * 1440, st: r.st)) }
        }
        return mergeRuns(line)
    }

    static func windowsOf(_ day: Day?) -> [Run] {
        (day?.runs ?? []).filter { $0.st == .off || $0.st == .maybe }
    }

    public static func getState(_ sched: Sched, _ now: Now) -> LightState {
        guard let day = sched.days[now.ymd], !day.runs.isEmpty else {
            return LightState(kind: sched.days[now.ymd]?.status == .check ? .check : .none, index: nil, line: [])
        }
        let line = timeline(sched, now.ymd)
        guard let index = line.firstIndex(where: { $0.s <= now.min && now.min < $0.e }), line[index].st != .unknown else {
            return LightState(kind: .none, index: nil, line: line)
        }
        let kind: LightKind = line[index].st == .on ? .on : line[index].st == .off ? .off : .maybe
        return LightState(kind: kind, index: index, line: line)
    }

    public static func whenText(_ min: Int) -> String {
        min >= 1440 ? "завтра \(at(min - 1440))" : at(min)
    }

    /// Межа проміжку: «23:30», «24:00» (північ сьогодні), «06:00 завтра».
    public static func untilText(_ min: Int) -> String {
        min > 1440 ? "\(hm(min - 1440)) завтра" : hm(min)
    }

    public static func windowText(_ w: Run) -> String {
        "\(hm(w.s))–\(hm(w.e))\(w.st == .maybe ? "?" : "")"
    }

    public static func buildGlance(_ cfg: Config?, _ data: LightData, _ now: Now, nowMs: Millis = Date().ms) -> Glance {
        var view = Glance()
        view.group = cfg?.group
        view.style = cfg?.style
        view.look = cfg?.look
        view.lockLook = cfg?.lockLook
        view.nowMin = now.min
        view.fact = cfg != nil ? factView(data.fact, now, nowMs) : nil
        view.place = cfg?.place
        guard let cfg = cfg else { return view }

        guard let sched = data.sched else {
            view.kind = data.status == .nogroup ? .nogroup : .nodata
            view.title = data.status == .nogroup ? "Черги немає" : "Немає даних"
            view.sub = data.status == .nogroup ? "Черга \(cfg.group) зникла з графіка" : "Не вдалося завантажити"
            return view
        }

        let state = getState(sched, now)
        let today = sched.days[now.ymd]
        let tomorrow = sched.days[addDays(now.ymd, 1)]
        view.kind = state.kind
        view.runFrom = state.current?.s
        view.todayRuns = today?.runs ?? []
        view.todayWindows = windowsOf(today)
        view.windowsLeft = view.todayWindows.filter { $0.e > now.min }
        if let tomorrow = tomorrow, !tomorrow.runs.isEmpty {
            view.tomorrowRuns = tomorrow.runs
            view.tomorrowWindows = windowsOf(tomorrow)
        }
        let fetchedAt = sched.fetchedAt ?? nowMs
        let checked = kyivParts(ms: fetchedAt).min
        view.checked = checked
        view.stale = (nowMs - fetchedAt) / 60000 > Timing.staleMinutes
        if sched.emergency {
            view.notice = "Аварійні відключення"
            view.noticeShort = "аварійні"
        } else if sched.warn == true {
            view.notice = "Графік міг змінитися"
            view.noticeShort = "перевірте сайт"
        } else if view.stale {
            view.notice = "Дані від \(hm(checked))"
            view.noticeShort = "дані \(hm(checked))"
        }

        // Написи кажуть «до коли», а не «що зараз»: iOS перемальовує віджет із запізненням,
        // і «Світло до 23:30» о 23:33 лишається правдою, а «Світло є» вже ні.
        let next = state.next
        let afterNext: Run? = state.index.flatMap { $0 + 2 < state.line.count ? state.line[$0 + 2] : nil }
        switch state.kind {
        case .on:
            if let next = next, next.st == .off || next.st == .maybe {
                view.title = "Світло до \(untilText(next.s))"
                let known = afterNext != nil && afterNext!.st != .unknown
                if next.st == .off {
                    view.sub = known ? "Потім без світла до \(untilText(next.e))" : "Потім відключення"
                } else {
                    view.sub = known ? "Потім можливе відключення до \(untilText(next.e))" : "Потім можливе відключення"
                }
                view.changeMin = next.s
            } else {
                view.title = "Світло є"
                view.sub = "Більше без відключень"
            }
        case .off, .maybe:
            view.title = state.kind == .off ? "Світла немає" : "Можливе відключення"
            if let next = next, next.st != .unknown {
                if state.kind == .off { view.title = "Без світла до \(untilText(next.s))" }
                let known = afterNext != nil && afterNext!.st != .unknown
                if next.st == .on {
                    view.sub = known ? "Потім світло до \(untilText(next.e))" : "Потім світло"
                } else {
                    view.sub = "Потім можливе відключення до \(untilText(next.e))"
                }
                if state.kind == .maybe { view.sub = "До \(untilText(next.s))\(next.st == .on ? ", потім світло" : "")" }
                view.changeMin = next.s
            } else if (state.current?.e ?? 0) <= 1440 {
                view.sub = "До кінця доби"
            } else {
                view.sub = "До кінця завтрашнього дня"
            }
        case .check:
            view.title = "Графік змінився"
            view.sub = "Перевірте сайт обленерго"
        default:
            view.title = "Графіка немає"
            view.sub = "На сьогодні не опубліковано"
        }
        if let change = view.changeMin { view.short = hm(change % 1440) }
        return view
    }

    /// Момент зміни стану: хвилини доби від «зараз» до зміни, від початку поточної хвилини.
    public static func changeDate(_ view: Glance, _ now: Now, _ date: Date) -> Date {
        let base = (date.timeIntervalSince1970 / 60).rounded(.down) * 60
        return Date(timeIntervalSince1970: base + Double((view.changeMin ?? now.min) - now.min) * 60)
    }

    /// Таймер показуємо, лише коли зміна менш ніж за добу.
    public static func hasTimer(_ view: Glance, _ now: Now) -> Bool {
        guard let change = view.changeMin else { return false }
        return change - now.min < 1440
    }

    /// Другий рядок на екрані блокування, коли таймера немає.
    public static func lockLine(_ view: Glance) -> String {
        if view.kind == .on { return view.tomorrowRuns != nil ? "Сьогодні й завтра без відключень" : "Сьогодні більше без відключень" }
        return view.sub
    }

    /// Підпис над великим часом: «світло до» 23:30.
    public static func changeVerb(_ view: Glance) -> String {
        let verb: String
        switch view.kind {
        case .on: verb = "світло до"
        case .off: verb = "без світла до"
        case .maybe: verb = "можливо до"
        default: verb = ""
        }
        if let change = view.changeMin, change >= 1440 { return "\(verb) завтра" }
        return verb
    }

    public static func lockVerb(_ view: Glance) -> String {
        switch view.kind {
        case .on: return "Світло до"
        case .off: return "Без світла до"
        case .maybe: return "Можливо до"
        default: return ""
        }
    }

    public static func lockTitle(_ view: Glance) -> String {
        guard let change = view.changeMin else { return view.title }
        return "\(lockVerb(view)) \(view.short)\(change >= 1440 ? " завтра" : "")"
    }

    public static func isCharging(_ view: Glance) -> Bool { view.kind == .off || view.kind == .maybe }

    /// Що писати замість часу, коли наступної зміни немає.
    public static func quietWords(_ view: Glance) -> String {
        if view.kind == .on { return "Без\nвідключень" }
        return isCharging(view) ? "До кінця\nдоби" : view.title
    }

    /// Частка поточного відрізка: зі світлом батарея розряджається до вимкнення, без нього заряджається до ввімкнення.
    public static func batteryLevel(_ view: Glance) -> Double {
        guard let change = view.changeMin, let from = view.runFrom else { return view.kind == .on ? 1 : 0 }
        let left = Double(change - view.nowMin) / Double(change - from)
        return isCharging(view) ? 1 - left : left
    }

    public static func captionText(_ view: Glance) -> String {
        let group: String
        if let g = view.group {
            group = view.place.map { "\($0) · черга \(g)" } ?? "Черга \(g)"
        } else {
            group = "Графік світла"
        }
        return view.kind == .on || view.kind == .off || view.kind == .maybe ? "\(group) · за графіком" : group
    }

    /// Хто це: «Черга 3.2», а коли адрес дві, «Батьки, черга 3.2». Для сповіщень.
    public static func queueLabel(_ group: String, _ place: String?) -> String {
        if let place = place, !place.isEmpty { return "\(place), черга \(group)" }
        return "Черга \(group)"
    }
}

// MARK: - Завтра

private let reTogether = Re("([0-9]{1,2}:[0-9]{2}) завтра")
private let monthNames = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]

extension Logic {
    /// Графік на завтра вже опубліковано.
    public static func hasTomorrow(_ view: Glance) -> Bool { view.tomorrowRuns != nil }

    /// Коротко для вузької колонки: «12–14, 18–20:30» (рівні години без «:00»).
    public static func compactWindowText(_ w: Run) -> String {
        func short(_ min: Int) -> String { min % 60 != 0 ? hm(min) : pad(min / 60) }
        return "\(short(w.s))–\(short(w.e))\(w.st == .maybe ? "?" : "")"
    }

    static func joinWindows(_ windows: [Run], _ compact: Bool) -> String {
        windows.prefix(4).map { compact ? compactWindowText($0) : windowText($0) }.joined(separator: ", ")
    }

    /// Що лишилося сьогодні: «12:00–14:00, 18:00–20:30», «більше немає» чи «без відключень».
    public static func todayRow(_ view: Glance, compact: Bool = false) -> String {
        if view.windowsLeft.isEmpty { return view.todayWindows.isEmpty ? "без відключень" : "більше немає" }
        return joinWindows(view.windowsLeft, compact)
    }

    public static func tomorrowRow(_ view: Glance, compact: Bool = false) -> String {
        guard let windows = view.tomorrowWindows, !windows.isEmpty else { return "без відключень" }
        return joinWindows(windows, compact)
    }

    /// Коротко про завтра для малого віджета: «06:00–09:00 +1» або «без відключень».
    public static func tomorrowFirst(_ view: Glance) -> String? {
        if !hasTomorrow(view) { return nil }
        let windows = view.tomorrowWindows ?? []
        guard let first = windows.first else { return "без відключень" }
        return windowText(first) + (windows.count > 1 ? " +\(windows.count - 1)" : "")
    }

    /// «19:30 завтра» — одне ціле: нерозривний пробіл, щоб «завтра» не перенеслося на рядок саме.
    public static func keepTogether(_ text: String) -> String {
        reTogether.replace(text, "$1\u{00A0}завтра")
    }

    /// «1 відключення», «3 відключення», «5 відключень».
    public static func outagesWord(_ n: Int) -> String {
        let one = n % 10 == 1 && n % 100 != 11
        let few = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)
        return one || few ? "відключення" : "відключень"
    }

    /// «3 відключення · 9 год», «Без відключень».
    public static func tomorrowSummary(_ view: Glance) -> String {
        guard view.tomorrowRuns != nil else { return "Графіка ще немає" }
        let windows = view.tomorrowWindows ?? []
        if windows.isEmpty { return "Без відключень" }
        let total = windows.reduce(0) { $0 + ($1.e - $1.s) }
        return "\(windows.count) \(outagesWord(windows.count)) · \(durationText(total))"
    }

    /// «12 листопада».
    public static func dateWords(_ ymd: String) -> String {
        let p = ymdParts(ymd)
        return "\(p.d) \(monthNames[max(0, min(11, p.m - 1))])"
    }

    /// Коли iOS варто знову спитати віджет: між змінами раз на 30 хвилин (з датчиком раз на 15,
    /// з тривогами ще частіше). Самі зміни графіка вже стоять у таймлайні окремими записами.
    public static func refreshDate(_ view: Glance, _ now: Now, _ date: Date, alertMinutes: Double? = nil) -> Date {
        var minutes = view.fact != nil ? Timing.factRefreshMinutes : Timing.refreshMinutes
        if let a = alertMinutes { minutes = min(minutes, a) }
        let latest = date.addingTimeInterval(minutes * 60)
        guard view.changeMin != nil else { return latest }
        return min(latest, changeDate(view, now, date).addingTimeInterval(10))
    }
}

// MARK: - Години для малюнків
// Кожна клітинка, вікно чи лампочка це одна година. Частину години зафарбовано точно за графіком.

public struct Part: Equatable {
    public var from: Int
    public var to: Int
    public var st: Status
}

extension Logic {
    /// Години from..to, поділені за станом. Те, чого немає в графіку, вважаємо невідомим.
    public static func partsOf(_ runs: [Run], _ from: Int, _ to: Int) -> [Part] {
        var parts: [Part] = []
        var cursor = from
        for run in runs {
            let s = max(run.s, from)
            let e = min(run.e, to)
            if e <= s { continue }
            if s > cursor { parts.append(Part(from: cursor, to: s, st: .unknown)) }
            parts.append(Part(from: s, to: e, st: run.st))
            cursor = e
        }
        if cursor < to { parts.append(Part(from: cursor, to: to, st: .unknown)) }
        return parts
    }

    public static func hourParts(_ runs: [Run], _ hour: Int) -> [Part] { partsOf(runs, hour * 60, (hour + 1) * 60) }

    public static func currentHour(_ nowMin: Int?) -> Int { nowMin.map { $0 / 60 } ?? -1 }
}

// MARK: - Вигляди

public struct LookInfo: Equatable {
    public let id: String
    public let name: String
}

extension Logic {
    public static let looks: [LookInfo] = [
        LookInfo(id: "house", name: "Будинок"), LookInfo(id: "tiles", name: "Плитки"), LookInfo(id: "garland", name: "Гірлянда"),
        LookInfo(id: "battery", name: "Батарея"), LookInfo(id: "ring", name: "Кільце"),
    ]
    public static let defaultLook = "house"
    // Екран блокування: замість батареї лампочка. Повний графік там зайвий.
    public static let lockLooks: [LookInfo] = [
        LookInfo(id: "bulb", name: "Лампочка"), LookInfo(id: "house", name: "Будинок"), LookInfo(id: "tiles", name: "Плитки"),
        LookInfo(id: "garland", name: "Гірлянда"), LookInfo(id: "ring", name: "Кільце"),
    ]
    public static let defaultLockLook = "bulb"

    public static func lockLookOf(_ id: String?) -> String {
        if id == "battery" { return "bulb" }
        if let id = id, lockLooks.contains(where: { $0.id == id }) { return id }
        return defaultLockLook
    }

    /// Лампочка світиться, коли світло є: за датчиком, а без нього за графіком. Без світла перекреслена.
    public static func bulbState(_ view: Glance) -> Status {
        if let fact = view.fact, fact.kind == .on || fact.kind == .off { return fact.kind == .on ? .on : .off }
        if view.kind == .on { return .on }
        if view.kind == .off { return .off }
        return .maybe
    }

    public static func lookOf(_ id: String?, _ fallback: String) -> String {
        if let id = id, looks.contains(where: { $0.id == id }) { return id }
        return fallback
    }
}

// MARK: - Сповіщення
// Лише три види: графік змінився, за 10 хвилин до відключення, за 10 хвилин до ввімкнення.

public struct Planned: Equatable {
    public var id: String
    public var kind: Status // .off або .on
    public var triggerMin: Int
    public var title: String
    public var body: String
}

struct Outage {
    var s: Int
    var e: Int
    var maybe: Bool
    var endKnown: Bool
}

/// Відомі вікна відключень за датами: [s, e, стан].
public struct KnownWindow: Codable, Equatable, Sendable {
    public var s: Int
    public var e: Int
    public var st: Status
    public init(s: Int, e: Int, st: Status) {
        self.s = s
        self.e = e
        self.st = st
    }
}

public typealias Known = [String: [KnownWindow]]

public struct Change: Equatable {
    public var ymd: String
    public var windows: [Run]
    public var isNew: Bool
}

public struct Message: Equatable, Sendable {
    public var title: String
    public var body: String
    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

extension Logic {
    /// Відключення й можливі відключення поспіль — одне знеструмлення. Кінець відомий, лише якщо після нього є світло.
    static func outagesOf(_ sched: Sched, _ now: Now) -> [Outage] {
        let line = timeline(sched, now.ymd)
        var out: [Outage] = []
        for run in line where run.st == .off || run.st == .maybe {
            if let last = out.last, last.e == run.s {
                // Однакові стани timeline уже злила, тож поруч лише відключення й можливе: разом це відключення.
                out[out.count - 1].e = run.e
                out[out.count - 1].maybe = false
            } else {
                out.append(Outage(s: run.s, e: run.e, maybe: run.st == .maybe, endKnown: false))
            }
        }
        for i in out.indices {
            let after = line.first { $0.s == out[i].e }
            out[i].endKnown = after?.st == .on
        }
        return out
    }

    static func dayOfMinute(_ now: Now, _ min: Int) -> String { min >= 1440 ? addDays(now.ymd, 1) : now.ymd }

    /// Коли станеться подія, словами від моменту, коли сповіщення ПОКАЖЕТЬСЯ (triggerMin), а не від моменту планування.
    public static func noticeWhen(_ min: Int, _ triggerMin: Int) -> String {
        let days = floorDiv(min, 1440) - floorDiv(triggerMin, 1440)
        let t = min % 1440
        if days <= 0 { return at(t) }
        return t == 0 ? "опівночі" : "завтра \(at(t))"
    }

    /// place: назва адреси, коли їх дві; тоді текст починається з «Батьки, черга 3.2».
    public static func plannedNotifications(_ sched: Sched, _ now: Now, _ group: String, _ prefs: NotifyPrefs, place: String? = nil) -> [Planned] {
        let lead = Timing.noticeMinutes
        let who = queueLabel(group, place)
        var items: [Planned] = []
        for outage in outagesOf(sched, now) {
            let startAt = outage.s - lead
            if prefs.off && startAt > now.min {
                let until = outage.endKnown ? ", увімкнуть \(noticeWhen(outage.e, startAt))" : ""
                items.append(Planned(
                    id: "off-\(dayOfMinute(now, outage.s))-\(outage.s % 1440)",
                    kind: .off,
                    triggerMin: startAt,
                    title: outage.maybe ? "Через \(lead) хв можливе відключення" : "Через \(lead) хв вимкнуть світло",
                    body: "\(who): \(outage.maybe ? "можливе відключення" : "відключення") \(noticeWhen(outage.s, startAt))\(until)"
                ))
            }
            let endAt = outage.e - lead
            if prefs.on && outage.endKnown && endAt > now.min {
                items.append(Planned(
                    id: "on-\(dayOfMinute(now, outage.e))-\(outage.e % 1440)",
                    kind: .on,
                    triggerMin: endAt,
                    title: "Через \(lead) хв увімкнуть світло",
                    body: "\(who): світло \(noticeWhen(outage.e, endAt))"
                ))
            }
        }
        // Стабільне сортування, як Array.prototype.sort.
        return items.enumerated().sorted { a, b in
            a.element.triggerMin != b.element.triggerMin ? a.element.triggerMin < b.element.triggerMin : a.offset < b.offset
        }.map { $0.element }
    }

    /// Дата, що зникла з даних, лишається такою, як була: інакше перемикання між джерелами давало б хибне «графік змінився».
    public static func knownWindows(_ prev: Known?, _ sched: Sched, _ now: Now) -> Known {
        var out: Known = [:]
        for ymd in [now.ymd, addDays(now.ymd, 1)] {
            if let day = sched.days[ymd], day.status == .ok, !day.runs.isEmpty {
                out[ymd] = windowsOf(day).map { KnownWindow(s: $0.s, e: $0.e, st: $0.st) }
            } else if let before = prev?[ymd] {
                out[ymd] = before
            }
        }
        return out
    }

    /// Перше завантаження нічого не повідомляє. Минулі години сьогодні не рахуються.
    public static func scheduleChanges(_ prev: Known?, _ next: Known, _ now: Now) -> [Change] {
        guard let prev = prev else { return [] }
        var changes: [Change] = []
        for ymd in next.keys.sorted() {
            let cut = ymd == now.ymd ? now.min : -1
            let after = (next[ymd] ?? []).filter { $0.e > cut }
            let runs = after.map { Run(s: $0.s, e: $0.e, st: $0.st) }
            guard let before = prev[ymd] else {
                changes.append(Change(ymd: ymd, windows: runs, isNew: true))
                continue
            }
            let was = before.filter { $0.e > cut }
            if was != after { changes.append(Change(ymd: ymd, windows: runs, isNew: false)) }
        }
        return changes
    }

    public static func changeMessage(_ changes: [Change], _ now: Now, _ group: String, place: String? = nil) -> Message? {
        if changes.isEmpty { return nil }
        let onlyNew = changes.allSatisfy { $0.isNew }
        let parts = changes.map { c -> String in
            let day = c.ymd == now.ymd ? "сьогодні" : "завтра"
            let list = c.windows.isEmpty ? "без відключень" : c.windows.map(windowText).joined(separator: ", ")
            return "\(day): \(list)"
        }
        return Message(
            title: onlyNew ? "Новий графік відключень" : "Графік відключень змінився",
            body: "\(queueLabel(group, place)), \(parts.joined(separator: "; "))"
        )
    }
}
