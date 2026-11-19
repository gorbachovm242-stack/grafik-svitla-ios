// Дрібні помічники для перенесення з TypeScript: регулярні вирази як у JavaScript, розбір дат ISO,
// числа з JSON. Лише Foundation, тож працює однаково на iPhone, macOS, Windows і Linux.
import Foundation

// MARK: - Регулярні вирази

/// Обгортка над NSRegularExpression з поведінкою, звичною з JavaScript: перший збіг, усі збіги, заміна з `$1`.
/// Замість `\d` у шаблонах пишемо `[0-9]`: у ICU `\d` ловить будь-які цифри Юнікоду, а в JavaScript лише ASCII.
public struct Re {
    let rx: NSRegularExpression

    public init(_ pattern: String, ignoreCase: Bool = false) {
        do {
            rx = try NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
        } catch {
            fatalError("Неправильний регулярний вираз: \(pattern)")
        }
    }

    /// Перший збіг або nil.
    public func first(_ text: String) -> ReMatch? {
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ReMatch(m, ns)
    }

    /// Усі збіги по черзі, як `while ((m = re.exec(text)))` з прапорцем g.
    public func all(_ text: String) -> [ReMatch] {
        let ns = text as NSString
        return rx.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { ReMatch($0, ns) }
    }

    public func test(_ text: String) -> Bool {
        let ns = text as NSString
        return rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    public func count(_ text: String) -> Int {
        let ns = text as NSString
        return rx.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
    }

    /// Заміна всіх збігів; у шаблоні `$1` — перша група, як у JavaScript.
    public func replace(_ text: String, _ template: String) -> String {
        let ns = text as NSString
        return rx.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    /// Заміна всіх збігів на сталий рядок (без `$` і `\` у ньому).
    public func replaceLiteral(_ text: String, _ value: String) -> String {
        replace(text, NSRegularExpression.escapedTemplate(for: value))
    }
}

public struct ReMatch {
    /// [0] — увесь збіг, далі групи; nil, якщо група не спрацювала.
    public let groups: [String?]
    /// Де закінчується збіг у вихідному рядку (у кодових одиницях UTF-16, як у NSString).
    public let end: Int
    public let start: Int

    init(_ m: NSTextCheckingResult, _ source: NSString) {
        var out: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? nil : source.substring(with: r))
        }
        groups = out
        start = m.range.location
        end = m.range.location + m.range.length
    }

    public subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    /// Група як рядок; порожній, якщо не спрацювала.
    public func s(_ i: Int) -> String { self[i] ?? "" }
}

// MARK: - Рядки

extension String {
    /// Як `trim()` у JavaScript: пробіли (зокрема нерозривний) і переноси з обох боків.
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Частина рядка за зсувом у UTF-16 (як індекси NSString).
    func utf16Suffix(from offset: Int) -> String {
        let ns = self as NSString
        return offset >= ns.length ? "" : ns.substring(from: offset)
    }

    /// Розбиття, як `split` у JavaScript: порожні частини лишаються.
    func parts(_ separator: String) -> [String] { components(separatedBy: separator) }
}

/// Як `parseInt(text, 10)`: ціле число на початку рядка (зі знаком), інакше nil (NaN).
func parseIntPrefix(_ text: String) -> Int? {
    guard let m = Re("^\\s*([+-]?[0-9]+)").first(text) else { return nil }
    return Int(m.s(1))
}

/// Як `parseFloat`: число на початку рядка, інакше nil (NaN).
func parseFloatPrefix(_ text: String) -> Double? {
    guard let m = Re("^\\s*([+-]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+))").first(text) else { return nil }
    return Double(m.s(1))
}

/// Як `pad` у logic.ts: два знаки з нулем попереду.
public func pad(_ n: Int) -> String { n < 10 && n >= 0 ? "0\(n)" : "\(n)" }

// MARK: - Час

/// Мілісекунди від 1970 року, як `Date.now()` у JavaScript.
public typealias Millis = Double

extension Date {
    public var ms: Millis { (timeIntervalSince1970 * 1000).rounded() }
    public init(ms: Millis) { self.init(timeIntervalSince1970: ms / 1000) }
}

/// Номер дня від 1970-01-01 для дати григоріанського календаря (алгоритм Говарда Хіннанта).
func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
    let y = m <= 2 ? y0 - 1 : y0
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (m + 9) % 12
    let doy = (153 * mp + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/// Дата з номера дня від 1970-01-01.
func civilFromDays(_ z0: Int) -> (y: Int, m: Int, d: Int) {
    let z = z0 + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    return (m <= 2 ? y + 1 : y, m, d)
}

private let isoRe = Re(
    "^\\s*([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[Tt ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:[.,]([0-9]+))?)?)?\\s*(Z|z|[+-][0-9]{2}(?::?[0-9]{2})?)?\\s*$"
)

/// Як `Date.parse` для дат ISO 8601: «2026-11-09T04:53:00+00:00», «2026-11-18T08:40:12.000Z».
/// Дата й час без поясу — місцевий час телефона (так робить JavaScript), сама дата — UTC. Інше: nil (NaN).
public func parseDate(_ text: String) -> Millis? {
    guard let m = isoRe.first(text), let y = Int(m.s(1)), let mo = Int(m.s(2)), let d = Int(m.s(3)) else { return nil }
    guard (1...12).contains(mo), (1...31).contains(d) else { return nil }
    let hasTime = m[4] != nil
    let h = Int(m.s(4)) ?? 0
    let mi = Int(m.s(5)) ?? 0
    let s = Int(m.s(6)) ?? 0
    guard h <= 24, mi < 60, s < 61 else { return nil }
    var frac: Double = 0
    if let f = m[7], !f.isEmpty { frac = Double("0." + f).map { $0 * 1000 } ?? 0 }
    let days = daysFromCivil(y, mo, d)
    var ms = Double(days) * 86_400_000 + Double(h * 3600 + mi * 60 + s) * 1000 + frac.rounded(.down)
    if let zone = m[8] {
        if zone != "Z" && zone != "z" {
            let sign: Double = zone.hasPrefix("-") ? -1 : 1
            let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
            let zh = Int(digits.prefix(2)) ?? 0
            let zm = digits.count > 2 ? Int(digits.suffix(digits.count - 2)) ?? 0 : 0
            ms -= sign * Double(zh * 60 + zm) * 60_000
        }
    } else if hasTime {
        let guess = Date(ms: ms)
        ms -= Double(TimeZone.current.secondsFromGMT(for: guess)) * 1000
    }
    return ms
}

// MARK: - JSON

// На iPhone і macOS числа з JSONSerialization приходять як NSNumber, на Linux і Windows — як Int чи Double.
// Тому спершу Int і Double (NSNumber до них теж приводиться), а NSNumber — наостанок.

/// Значення з JSONSerialization як рядок, як `String(v)` у JavaScript (null → "").
func jsonString(_ value: Any?) -> String {
    guard let value = value, !(value is NSNull) else { return "" }
    if let s = value as? String { return s }
    if let i = value as? Int { return String(i) }
    if let d = value as? Double {
        if d.rounded() == d && abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }
    if let b = value as? Bool { return b ? "true" : "false" }
    return "\(value)"
}

/// Число з JSON, лише якщо там справді число (як `typeof v === "number"`).
func jsonNumeric(_ value: Any?) -> Double? {
    guard let value = value, !(value is NSNull), !(value is String) else { return nil }
    if let i = value as? Int { return Double(i) }
    if let d = value as? Double { return d }
    return nil
}

/// Як `Number(v || 0)`: число з числа чи рядка; інакше nil (NaN).
func jsonNumber(_ value: Any?) -> Double? {
    guard let value = value, !(value is NSNull) else { return 0 }
    if let s = value as? String {
        let t = s.trimmed
        return t.isEmpty ? 0 : Double(t)
    }
    if let i = value as? Int { return Double(i) }
    if let d = value as? Double { return d }
    if let b = value as? Bool { return b ? 1 : 0 }
    return nil
}

/// Як істинність у JavaScript: порожній рядок, 0, false і null — хиба.
func jsonTruthy(_ value: Any?) -> Bool {
    guard let value = value, !(value is NSNull) else { return false }
    if let s = value as? String { return !s.isEmpty }
    if let i = value as? Int { return i != 0 }
    if let d = value as? Double { return d != 0 && !d.isNaN }
    if let b = value as? Bool { return b }
    return true
}

func jsonObject(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}
