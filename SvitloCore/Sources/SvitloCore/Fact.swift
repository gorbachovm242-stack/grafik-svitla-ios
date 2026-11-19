// Фактичний стан: датчик СвітлоБота. Графік каже, коли світло мають вимкнути, а датчик — чи воно є насправді.
// Датчик це телефон на зарядці чи роутер, що щохвилини стукає до СвітлоБота (svitlobot.in.ua).
// Джерела: відкритий список каналів (стан і час останньої зміни кожного) і публічна сторінка каналу в Telegram,
// де бот сам пише «Світло з'явилося … Його не було 3год 17хв». Перенесено з logic.ts.
import Foundation

public enum SvitloBot {
    public static let list = "https://api.svitlobot.in.ua/website/getChannelsForMap"
    public static let howTo = "https://svitlobot.in.ua/instructions"
    public static func posts(_ channel: String) -> String { "https://t.me/s/\(channel)" }
}

public enum FactStatus: String, Codable, Sendable { case on, off, unknown, missing }

/// queue: як СвітлоБот підписує розклад датчика («Запорізька обл. — група 3.2», у Києві «Група 4.1»), nil якщо не обрано.
public struct Channel: Equatable, Sendable {
    public var id: String
    public var name: String
    public var status: FactStatus
    public var since: Millis?
    public var users: Int
    public var queue: String?
    public init(id: String, name: String, status: FactStatus, since: Millis?, users: Int, queue: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.since = since
        self.users = users
        self.queue = queue
    }
}

public struct QueueCount: Codable, Equatable, Sendable {
    public var on: Int
    public var off: Int
    public var total: Int
}

public struct Fact: Codable, Equatable, Sendable {
    public var channel: String
    public var name: String
    public var status: FactStatus // missing: каналу вже немає в списку
    public var since: Millis? // коли змінився стан
    public var lastOffMin: Int? // скільки не було світла минулого разу (коли воно вже є)
    public var lastOffEnd: Millis? // коли те відключення скінчилося
    public var postsFor: Millis? // для якої зміни вже шукали тривалість у дописах каналу
    public var checkedAt: Millis
    public var count: QueueCount? // лише для черги: скільки датчиків зі світлом і без

    public init(
        channel: String, name: String, status: FactStatus, since: Millis?, lastOffMin: Int?, lastOffEnd: Millis?,
        postsFor: Millis?, checkedAt: Millis, count: QueueCount? = nil
    ) {
        self.channel = channel
        self.name = name
        self.status = status
        self.since = since
        self.lastOffMin = lastOffMin
        self.lastOffEnd = lastOffEnd
        self.postsFor = postsFor
        self.checkedAt = checkedAt
        self.count = count
    }
}

public struct Comeback: Equatable {
    public var at: Millis
    public var offMin: Int
}

/// Допис бота про зміну стану: «🔴 06:53 Світло зникло …» чи «🟢 10:10 Світло з'явилося … Його не було 3год 17хв».
public struct StatusPost: Equatable {
    public var at: Millis
    public var status: FactStatus // .on або .off
    public var since: Millis
    public var offMin: Int?
}

/// Що показати про датчик: повний рядок для застосунку, рядок для віджета, коротко для тісних місць.
public struct FactGlance: Equatable, Sendable {
    public var kind: FactStatus
    public var full: String // «Світло є з 10:10 · не було 3 год 17 хв»
    public var line: String // «Світло є · не було 3 год 17 хв»
    public var short: String // «не було 3 год 17 хв»
    public var timerFrom: Millis? // від цього моменту рахує живий таймер, поки світла немає
    public var checked: String? // дані датчика старі: коли перевіряли востаннє
}

private let svitlobotRegions: [String: String] = [
    "zaporizhzhia": "Запорізька обл.", "kyiv": "", "kyiv-oblast": "Київська обл.", "dnipro-dnem": "Дніпро (ДТЕК)",
    "dnipro-cek": "Дніпро (ЦЕК)", "odesa": "Одеса та обл.", "vinnytsia": "Вінницька обл.", "cherkasy": "Черкаська обл.",
    "chernihiv": "Чернігівська обл.", "kharkiv": "Харківська обл.", "khmelnytskyi": "Хмельницька обл.", "lviv": "Львівська обл.",
    "poltava": "Полтавська обл.", "ivano-frankivsk": "Івано-Франківська обл.", "rivne": "Рівненська обл.",
    "ternopil": "Тернопільська обл.", "zakarpattia": "Закарпатська обл.", "zhytomyr": "Житомирська обл.",
]

private let reChannelId = Re("^[A-Za-z0-9_]+$")
private let reArrow = Re("\\s*,?\\s*->\\s*")
private let reQueueNumber = Re("([0-9]+)[.,]([0-9]+)")
private let reKyivQueue = Re("^Група\\s")
private let reUrlScheme = Re("^https?://", ignoreCase: true)
private let reTelegramHost = Re("^(www\\.)?(t|telegram)\\.me/(s/)?", ignoreCase: true)
private let reIdEnd = Re("[/?#\\s]")
private let reChannelName = Re("^[A-Za-z0-9_]{4,64}$")
private let reApostrophes = Re("[’'ʼ`]")
private let reNotWord = Re("[^0-9a-zа-яіїєґё_]+")
private let reDays = Re("([0-9]+)\\s*д")
private let reHours = Re("([0-9]+)\\s*год")
private let reMinutes = Re("([0-9]+)\\s*хв")
let reTelegramPost = Re("tgme_widget_message_text[^>]*>([\\s\\S]*?)</div>[\\s\\S]*?<time datetime=\"([^\"]+)\"")
private let reCameBack = Re("Світло з.явилося")
private let reGone = Re("не було\\s*([0-9\\sдгохв]+)")
private let reStatusLine = Re("([0-9]{1,2}):([0-9]{2})\\s*Світло (зникло|з.явилося)")
private let reBr = Re("<br\\s*/?>", ignoreCase: true)
private let reSpaces = Re("\\s+")

extension Logic {
    /// Список для мапи: -1;&&&;стан;&&&;час зміни (UTC);&&&;назва;&&&;канал;&&&;кількість;&&&;широта;&&&;довгота;&&&;…;&&&;розклад;&&&;…
    /// Короткий список: стан;&;час зміни;&;назва;&;канал;&;кількість. Стан 1: світло є, 2: світла немає, інше: датчик мовчить.
    public static func parseChannels(_ text: String) -> [Channel] {
        var out: [Channel] = []
        for line in text.parts("\n") {
            var f: [String]
            var queue: String? = nil
            if line.contains(";&&&;") {
                let m = line.parts(";&&&;")
                if m.count < 6 { continue }
                f = Array(m[1..<6])
                let q = m.count > 9 ? m[9].trimmed : ""
                queue = !q.isEmpty && q != "-" ? q : nil
            } else {
                f = line.parts(";&;")
                if f.count < 5 { continue }
            }
            let id = f[3].trimmed
            if !reChannelId.test(id) { continue }
            let code = parseIntPrefix(f[0].trimmed)
            out.append(Channel(
                id: id,
                name: reArrow.replaceLiteral(f[2].trimmed, ", "),
                status: code == 1 ? .on : code == 2 ? .off : .unknown,
                since: parseDate(f[1].trimmed),
                users: max(0, (parseIntPrefix(f[4].trimmed) ?? 0) - 1),
                queue: queue
            ))
        }
        return out
    }

    /// Чи датчик стоїть у цій черзі цього регіону.
    public static func inQueue(_ ch: Channel, _ region: String, _ group: String) -> Bool {
        guard let queue = ch.queue, let prefix = svitlobotRegions[region] else { return false }
        guard let m = reQueueNumber.first(queue), "\(m.s(1)).\(m.s(2))" == group else { return false }
        return prefix.isEmpty ? reKyivQueue.test(queue) : queue.hasPrefix(prefix)
    }

    public static func queueId(_ region: String, _ group: String) -> String { "queue:\(region):\(group)" }
    public static func isQueueFact(_ fact: Fact) -> Bool { fact.channel.hasPrefix("queue:") }

    /// Без власного датчика: усі датчики СвітлоБота з черги користувача. Стан той, що в більшості (від 60 %),
    /// час зміни медіанний серед них; інакше «по-різному». Датчиків немає: nil.
    public static func queueChannel(_ list: [Channel], _ region: String, _ group: String) -> (channel: Channel, count: QueueCount)? {
        let sensors = list.filter { inQueue($0, region, group) }
        let on = sensors.filter { $0.status == .on }
        let off = sensors.filter { $0.status == .off }
        let total = on.count + off.count
        if total == 0 { return nil }
        let status: FactStatus = Double(on.count) >= Double(total) * 0.6 ? .on : Double(off.count) >= Double(total) * 0.6 ? .off : .unknown
        let pool = status == .on ? on : status == .off ? off : []
        let times = pool.compactMap { $0.since }.sorted()
        let channel = Channel(
            id: queueId(region, group), name: "черга \(group)", status: status,
            since: times.isEmpty ? nil : times[times.count / 2], users: total, queue: nil
        )
        return (channel, QueueCount(on: on.count, off: off.count, total: total))
    }

    /// Посилання, «@назва» чи сама назва каналу: лишаємо назву.
    public static func channelId(_ input: String) -> String {
        var s = reUrlScheme.replaceLiteral(input.trimmed, "")
        s = reTelegramHost.replaceLiteral(s, "")
        if s.hasPrefix("@") { s.removeFirst() }
        let id = reIdEnd.first(s).map { (s as NSString).substring(to: $0.start) } ?? s
        return reChannelName.test(id) ? id : ""
    }

    public static func findChannel(_ list: [Channel], _ id: String) -> Channel? {
        let key = id.lowercased()
        return list.first { $0.id.lowercased() == key }
    }

    static func searchWords(_ text: String) -> String {
        let lower = reApostrophes.replaceLiteral(text.lowercased(), "")
        return reNotWord.replaceLiteral(lower, " ").trimmed
    }

    /// Пошук за вулицею, будинком чи назвою каналу: кожне слово запиту має знайтися. Більші канали вище.
    public static func searchChannels(_ list: [Channel], _ query: String, limit: Int = 8) -> [Channel] {
        let wanted = searchWords(query).parts(" ").filter { !$0.isEmpty }
        if wanted.isEmpty { return [] }
        let direct = channelId(query).lowercased()
        let found = list.enumerated().filter { _, c in
            if !direct.isEmpty && c.id.lowercased() == direct { return true }
            let words = searchWords("\(c.name) \(c.id)")
            return wanted.allSatisfy { words.contains($0) }
        }
        return found.sorted { a, b in a.element.users != b.element.users ? a.element.users > b.element.users : a.offset < b.offset }
            .prefix(limit).map { $0.element }
    }

    /// «3год 17хв», «6хв», «1д 2год» → хвилини.
    public static func durationMin(_ text: String) -> Int? {
        let d = reDays.first(text)
        let h = reHours.first(text)
        let m = reMinutes.first(text)
        if d == nil && h == nil && m == nil { return nil }
        return (Int(d?.s(1) ?? "") ?? 0) * 1440 + (Int(h?.s(1) ?? "") ?? 0) * 60 + (Int(m?.s(1) ?? "") ?? 0)
    }

    static func plainText(_ html: String) -> String {
        var s = reBr.replaceLiteral(html, " ")
        s = Re("<[^>]+>").replaceLiteral(s, " ")
        s = Re("&#39;|&apos;|&#x27;").replaceLiteral(s, "'")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        return reSpaces.replaceLiteral(s, " ").trimmed
    }

    /// Дописи бота на t.me/s/канал: «🟢 10:10 Світло з'явилося 🕓 Його не було 3год 17хв» і час допису.
    public static func parseComebacks(_ html: String) -> [Comeback] {
        var out: [Comeback] = []
        for m in reTelegramPost.all(html) {
            let text = plainText(m.s(1))
            if !reCameBack.test(text) { continue }
            let offMin = reGone.first(text).flatMap { durationMin($0.s(1)) }
            if let offMin = offMin, let at = parseDate(m.s(2)) { out.append(Comeback(at: at, offMin: offMin)) }
        }
        return out
    }

    /// Власний канал працює одразу, без модерації СвітлоБота: стан беремо з його дописів на t.me/s/канал.
    /// Час зміни — з тексту (за Києвом), бо бот пише допис на кілька хвилин пізніше; дата — з часу допису.
    public static func parseStatusPosts(_ html: String) -> [StatusPost] {
        var out: [StatusPost] = []
        for m in reTelegramPost.all(html) {
            let text = plainText(m.s(1))
            guard let s = reStatusLine.first(text), let at = parseDate(m.s(2)) else { continue }
            let on = s.s(3) != "зникло"
            var back = kyivParts(ms: at).min - ((Int(s.s(1)) ?? 0) * 60 + (Int(s.s(2)) ?? 0))
            if back < 0 { back += 1440 } // зміна до півночі, допис після
            let gone = on ? reGone.first(text) : nil
            out.append(StatusPost(
                at: at, status: on ? .on : .off,
                since: (at / 60000).rounded(.down) * 60000 - Double(back) * 60000,
                offMin: gone.flatMap { durationMin($0.s(1)) }
            ))
        }
        return out
    }

    /// Факт власного каналу з останнього допису про зміну стану. «Скільки не було» бот пише сам;
    /// якщо ні, рахуємо від попереднього допису «зникло». Дописів про світло немає: nil.
    public static func postsFact(_ posts: [StatusPost], _ id: String, _ name: String, _ nowMs: Millis) -> Fact? {
        if posts.isEmpty { return nil }
        let sorted = posts.enumerated().sorted { a, b in
            a.element.since != b.element.since ? a.element.since < b.element.since : a.offset < b.offset
        }.map { $0.element }
        let last = sorted[sorted.count - 1]
        var lastOffMin: Int? = nil
        if last.status == .on {
            let before = sorted.filter { $0.status == .off && $0.since < last.since }.last
            if let off = last.offMin {
                lastOffMin = off
            } else if let before = before {
                lastOffMin = Int(((last.since - before.since) / 60000).rounded())
            }
        }
        return Fact(
            channel: id, name: name, status: last.status, since: last.since, lastOffMin: lastOffMin,
            lastOffEnd: lastOffMin != nil ? last.since : nil, postsFor: last.since, checkedAt: nowMs
        )
    }

    /// Новий стан датчика разом із попереднім: якщо бачили початок відключення, тривалість точна.
    /// У черзі медіанний час зміни трохи гуляє між перевірками, тож те саме ввімкнення — у межах 30 хвилин.
    public static func mergeFact(_ prev: Fact?, _ ch: Channel?, _ id: String, _ nowMs: Millis) -> Fact {
        let same = prev.flatMap { $0.channel.lowercased() == id.lowercased() ? $0 : nil }
        var lastOffMin = same?.lastOffMin
        var lastOffEnd = same?.lastOffEnd
        let postsFor = same?.postsFor
        guard let ch = ch else {
            return Fact(
                channel: same?.channel ?? id, name: same?.name ?? id, status: .missing, since: nil,
                lastOffMin: lastOffMin, lastOffEnd: lastOffEnd, postsFor: postsFor, checkedAt: nowMs
            )
        }
        if ch.status == .on, let chSince = ch.since {
            if let same = same, same.status == .off, let sameSince = same.since, sameSince < chSince {
                lastOffMin = Int(((chSince - sameSince) / 60000).rounded())
                lastOffEnd = chSince
            } else if let same = same, same.status == .on, let sameSince = same.since, abs(chSince - sameSince) <= 30 * 60000 {
                // те саме ввімкнення: тривалість лишається
            } else if lastOffEnd != chSince {
                lastOffMin = nil
                lastOffEnd = nil
            }
        }
        return Fact(
            channel: ch.id, name: ch.name, status: ch.status, since: ch.since,
            lastOffMin: lastOffMin, lastOffEnd: lastOffEnd, postsFor: postsFor, checkedAt: nowMs
        )
    }

    /// Факт для черги, з тією самою памʼяттю про тривалість, що й для одного датчика.
    public static func queueFact(_ prev: Fact?, _ list: [Channel], _ region: String, _ group: String, _ nowMs: Millis) -> Fact? {
        guard let q = queueChannel(list, region, group) else { return nil }
        var fact = mergeFact(prev, q.channel, q.channel.id, nowMs)
        fact.count = q.count
        return fact
    }

    /// Світло повернулося, а початку відключення не бачили: тривалість шукаємо в дописах каналу, один раз на зміну.
    public static func needsPosts(_ fact: Fact) -> Bool {
        !isQueueFact(fact) && fact.status == .on && fact.since != nil && fact.lastOffMin == nil && fact.postsFor != fact.since
    }

    public static func withComeback(_ fact: Fact, _ comebacks: [Comeback]) -> Fact {
        var out = fact
        out.postsFor = fact.since
        guard fact.status == .on, let since = fact.since, fact.lastOffMin == nil else { return out }
        if let hit = comebacks.first(where: { abs($0.at - since) <= 10 * 60000 }) {
            out.lastOffMin = hit.offMin
            out.lastOffEnd = since
        }
        return out
    }

    /// «3 год 17 хв», «45 хв», «2 дн 3 год».
    public static func durationText(_ min: Int) -> String {
        if min < 60 { return "\(min) хв" }
        let d = min / 1440
        let h = (min % 1440) / 60
        let m = min % 60
        if d > 0 { return h > 0 ? "\(d) дн \(h) год" : "\(d) дн" }
        return m > 0 ? "\(h) год \(m) хв" : "\(h) год"
    }

    /// Момент за Києвом: сьогодні «06:53», інший день «08.11 06:53».
    public static func sinceText(_ ms: Millis, _ now: Now) -> String {
        let p = kyivParts(ms: ms)
        if p.ymd == now.ymd { return hm(p.min) }
        let parts = ymdParts(p.ymd)
        return "\(pad(parts.d)).\(pad(parts.m)) \(hm(p.min))"
    }

    public static func factView(_ fact: Fact?, _ now: Now, _ nowMs: Millis) -> FactGlance? {
        guard let fact = fact else { return nil }
        let old = nowMs - fact.checkedAt > Timing.factStaleMinutes * 60000
        let checked = old ? "дані \(sinceText(fact.checkedAt, now))" : nil
        if fact.status == .missing {
            return FactGlance(
                kind: .missing,
                full: "Немає даних від датчика: канал ще не писав про світло або назву введено з помилкою",
                line: "Немає даних від датчика", short: "датчик ?", timerFrom: nil, checked: checked
            )
        }
        let when = fact.since.map { sinceText($0, now) }
        // Для черги в застосунку видно, за скількома датчиками.
        let count = isQueueFact(fact) ? fact.count : nil
        let source = count.map { c in
            " (за \(c.total) \(c.total % 10 == 1 && c.total % 100 != 11 ? "датчиком" : "датчиками") черги)"
        } ?? ""
        if fact.status == .on {
            let gone = fact.lastOffMin.flatMap { $0 > 0 ? "не було \(durationText($0))" : nil }
            let since = when.map { "Світло є з \($0)" } ?? "Світло є"
            return FactGlance(
                kind: .on,
                full: (gone.map { "\(since) · \($0)" } ?? since) + source,
                line: gone.map { "Світло є · \($0)" } ?? since,
                short: gone ?? (when.map { "є з \($0)" } ?? "світло є"),
                timerFrom: nil, checked: checked
            )
        }
        if fact.status == .off {
            let line = when.map { "Світла немає з \($0)" } ?? "Світла немає"
            return FactGlance(
                kind: .off, full: line + source, line: line, short: when.map { "немає з \($0)" } ?? "світла немає",
                timerFrom: old ? nil : fact.since, checked: checked
            )
        }
        if let c = count {
            return FactGlance(
                kind: .unknown,
                full: "У черзі по-різному: світло є в \(c.on) з \(c.total)",
                line: "У черзі по-різному: \(c.on) з \(c.total)",
                short: "по-різному", timerFrom: nil, checked: checked
            )
        }
        let line = when.map { "Датчик мовчить з \($0)" } ?? "Датчик мовчить"
        return FactGlance(kind: .unknown, full: line, line: line, short: "датчик мовчить", timerFrom: nil, checked: checked)
    }
}
