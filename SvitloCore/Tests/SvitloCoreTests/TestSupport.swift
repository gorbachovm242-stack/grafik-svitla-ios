// Спільне для тестів SvitloCore: синтетичні сторінки обленерго, спільні дані, підставна мережа, керований годинник
// і «Notifier», що поводиться як заглушка Scripting (tools/scripting-shim.mjs). Усі дані синтетичні.
import Foundation
import XCTest
@testable import SvitloCore

// MARK: - Адреси джерел: ті самі рядки, що в JS-тестах (заодно перевіряють сталі Swift)

let ZOE = "https://www.zoe.com.ua/outage/"
let NEW = "https://dtek-api.svitlo-proxy.workers.dev/"
let GH = "https://raw.githubusercontent.com/chaichuk/UA-power-outages-monitor/main/artifacts/last-message.json"
let OLD = "https://svitlo-proxy.svitlo-proxy.workers.dev"
let FEED_URL = "https://maiak-alerts.maiak.workers.dev/v1/alerts"
let CHANNEL_URL = "https://t.me/s/test_monitor"
let LOCATIONS_URL = "https://maiak-alerts.maiak.workers.dev/v1/locations"

let MIN: Millis = 60000
let LOGIC_NOW = "2026-11-06T10:00:00+02:00"
let CFG = Config(region: "zaporizhzhia", group: "3.2")

// MARK: - Час

/// Як Date.parse у JavaScript (дати ISO). Нерозібраний рядок — помилка тесту.
func ms(_ iso: String, file: StaticString = #filePath, line: UInt = #line) -> Millis {
    guard let value = parseDate(iso) else {
        XCTFail("Не розібрано дату \(iso)", file: file, line: line)
        return 0
    }
    return value
}

/// Як L.kyivParts(new Date(iso)).
func kyivNow(_ iso: String) -> Now { Logic.kyivParts(ms: ms(iso)) }

// MARK: - Сайт обленерго

/// Рядки черг як на сайті: дефіс стає «&#8211;», рядки через <br />.
func zoeLines(_ lines: [String]) -> String {
    lines.map { $0.replacingOccurrences(of: "-", with: "&#8211;") }.joined(separator: "<br />\n")
}

let TODAY_TITLE = "6 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ ДІЯТИМУТЬ ГПВ"
let TOMORROW_TITLE = "7 ЛИСТОПАДА ПО ЗАПОРІЗЬКІЙ ОБЛАСТІ ДІЯТИМУТЬ ГПВ"

/// Допис як у scripting-logic.test.mjs: з id, абзацом «Години відсутності» й обгорткою content.
func post(_ title: String, _ lines: [String]) -> String {
    "<article id=\"post-1\">\n<h2>\(title)</h2>\n<div class=\"content\"><p>Години відсутності:</p>\n<p>\(zoeLines(lines))</p>\n</div></article>"
}

/// Сторінка як у scripting-logic.test.mjs: спершу порожній допис, наприкінці «Лінія довіри».
func pageOf(_ posts: [String]) -> String {
    "<html><body><article id=\"post-0\"><h2></h2><div></div></article>\(posts.joined(separator: "\n"))<article><p>Лінія довіри</p></article></body></html>"
}

func page(_ posts: String...) -> String { pageOf(posts) }
func today(_ lines: [String]) -> String { post(TODAY_TITLE, lines) }
func tomorrowPost(_ lines: [String]) -> String { post(TOMORROW_TITLE, lines) }
/// Сайт обленерго з одним дописом на сьогодні.
func ok(_ lines: [String]) -> [String: Route] { [ZOE: .text(page(today(lines)))] }

/// Простий допис, як у scripting-store/two/tomorrow/offline.test.mjs.
func simplePost(_ title: String, _ lines: [String]) -> String {
    "<article><h2>\(title)</h2><div><p>\(zoeLines(lines))</p></div></article>"
}

func simplePageOf(_ posts: [String]) -> String { "<html><body>\(posts.joined(separator: "\n"))</body></html>" }
func simplePage(_ posts: String...) -> String { simplePageOf(posts) }
func simpleToday(_ lines: [String]) -> String { simplePost(TODAY_TITLE, lines) }
func simpleTomorrow(_ lines: [String]) -> String { simplePost(TOMORROW_TITLE, lines) }
/// Сайт обленерго з простими дописами (як state.routes = { [ZOE]: page(...) }).
func zoe(_ posts: String...) -> [String: Route] { [ZOE: .text(simplePageOf(posts))] }

// MARK: - Спільні дані обленерго

/// Клітинка «HH:MM» півгодинного графіка.
func slotKey(_ index: Int) -> String { "\(pad(index / 2)):\(index % 2 == 1 ? "30" : "00")" }

/// 48 півгодинних клітинок: fill (1 — світло є), а в діапазонах ranges — code (2 — немає, 3 — можливо).
func cells(_ ranges: [(Int, Int)], code: Int = 2, fill: Int = 1) -> [String: Any] {
    var out: [String: Any] = [:]
    for i in 0..<48 {
        let min = i * 30
        let off = ranges.contains { $0.0 <= min && min < $0.1 }
        out[slotKey(i)] = off ? code : fill
    }
    return out
}

/// { regions: [{ cpu, schedule: { [group]: days }, ...extra }] }
func feed(_ cpu: String, _ group: String, _ days: [String: Any], extra: [String: Any] = [:]) -> [String: Any] {
    var region: [String: Any] = ["cpu": cpu, "schedule": [group: days]]
    for (key, value) in extra { region[key] = value }
    return ["regions": [region]]
}

func toJSON(_ value: Any) -> String {
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    } catch {
        XCTFail("Не вдалося зібрати JSON: \(error)")
        return "{}"
    }
}

// MARK: - Підставна мережа

enum TestNetError: Error, Equatable {
    case noRoute(String) // невідома адреса: помилка мережі одразу (режим польоту)
    case offline(String)
    case unexpected(String)
}

/// Відповідь за адресою: рядок, JSON або функція, що вертає рядок чи кидає помилку.
enum Route {
    case text(String)
    case down // помилка мережі одразу
    case make(() throws -> String)

    static func json(_ value: [String: Any]) -> Route { .text(toJSON(value)) }
}

func resolve(_ route: Route?, _ url: String) throws -> String {
    switch route {
    case nil: throw TestNetError.noRoute(url)
    case .text(let text)?: return text
    case .down?: throw TestNetError.offline(url)
    case .make(let produce)?: return try produce()
    }
}

/// Як loader(routes) у scripting-logic.test.mjs: підставні джерела й список запитів.
final class Loader: @unchecked Sendable {
    private let lock = NSLock()
    private let routes: [String: Route]
    private var log: [String] = []

    init(_ routes: [String: Route] = [:]) { self.routes = routes }

    var requests: [String] { locked { log } }

    func load(_ url: String) async throws -> String {
        let route: Route? = locked {
            log.append(url)
            return routes[url]
        }
        return try resolve(route, url)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Запит, що не чує скасування: тримаємо продовження, яке ніхто не продовжить (як never() у заглушці).
final class DeafHold: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in keep(cont) }
    }

    private func keep(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        held.append(cont)
        lock.unlock()
    }
}

let deafHold = DeafHold()

/// Мережа як у tools/scripting-shim.mjs: routes, список запитів і режим без інтернету.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    /// online — як задано в routes; hang — кожен запит висить, доки його не скасують;
    /// deaf — висить і скасування не чує (так буває, коли iOS чекає на звʼязок).
    enum Mode { case online, hang, deaf }

    private let lock = NSLock()
    private var _routes: [String: Route] = [:]
    private var _mode = Mode.online
    private var _requests: [String] = []

    var routes: [String: Route] {
        get { locked { _routes } }
        set { locked { _routes = newValue } }
    }

    var offline: Mode {
        get { locked { _mode } }
        set { locked { _mode = newValue } }
    }

    var requests: [String] { locked { _requests } }

    func clearRequests() { locked { _requests = [] } }

    func reset() {
        locked {
            _routes = [:]
            _mode = .online
            _requests = []
        }
    }

    func get(_ url: String, timeoutMs: Double) async throws -> String {
        let (mode, route): (Mode, Route?) = locked {
            _requests.append(url)
            return (_mode, _routes[url])
        }
        switch mode {
        case .deaf:
            await deafHold.wait()
            throw TestNetError.offline(url)
        case .hang:
            try await Task.sleep(nanoseconds: 120_000_000_000) // скасування перериває сон одразу
            throw TestNetError.offline(url)
        case .online:
            return try resolve(route, url)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Годинник

/// Керований годинник для Store. Застиглий, як Date.now = () => clock у JS-тестах. ticking: іде далі від заданого
/// моменту в реальному часі — у JS крайній строк мережі рахували справжні таймери, а Net у Swift рахує його за цим годинником.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var base: Millis = 0
    private var anchor: Double = ProcessInfo.processInfo.systemUptime
    let ticking: Bool

    init(ticking: Bool = false) { self.ticking = ticking }

    func set(_ value: Millis) {
        lock.lock()
        base = value
        anchor = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    func advance(_ by: Millis) {
        lock.lock()
        base += by
        lock.unlock()
    }

    func now() -> Millis {
        lock.lock()
        defer { lock.unlock() }
        return ticking ? base + (ProcessInfo.processInfo.systemUptime - anchor) * 1000 : base
    }
}

// MARK: - Сповіщення

/// Як Notification у заглушці: заплановані (pending) і показані одразу (delivered). Застосовує план так,
/// як це робив updateNotifications у notifications.ts: новий набір замінює заплановані, позначку зберігаємо.
final class FakeNotifier {
    private(set) var pending: [ScheduledNotice] = []
    private(set) var delivered: [Message] = []
    private(set) var replacements = 0

    @discardableResult
    func update(_ store: Store, _ base: Config, _ scheds: [Sched?], _ now: Now, _ date: Date) -> NotificationPlan {
        let plan = store.planNotifications(base, scheds, now, date)
        if let replace = plan.replace {
            pending = replace
            replacements += 1
            if let signature = plan.signature { store.commitPlanned(signature) }
        }
        delivered.append(contentsOf: plan.immediate)
        return plan
    }

    /// Як resetNotifications() у notifications.ts: памʼять у сховищі й заплановані.
    func reset(_ store: Store) {
        store.resetNotifications()
        pending = []
    }

    func clear() {
        pending = []
        delivered = []
        replacements = 0
    }
}

// MARK: - Середовище: сховище, мережа, годинник (як state у заглушці)

struct Moment {
    let ms: Millis
    let date: Date
    let now: Now
}

struct Refreshed {
    let data: LightData
    let now: Now
    let date: Date
    let plan: NotificationPlan
}

final class Env {
    let http: FakeHTTP
    let clock: TestClock
    let notifier = FakeNotifier()
    private(set) var kv: MemoryStore
    private(set) var store: Store

    init(ticking: Bool = false) {
        let clock = TestClock(ticking: ticking)
        let http = FakeHTTP()
        let kv = MemoryStore()
        self.clock = clock
        self.http = http
        self.kv = kv
        store = Store(kv: kv, http: http, clock: { clock.now() })
    }

    /// Як resetState(): порожнє сховище, мережа без адрес. Годинник лишається.
    func reset() {
        let clock = self.clock
        kv = MemoryStore()
        http.reset()
        notifier.clear()
        store = Store(kv: kv, http: http, clock: { clock.now() })
    }

    /// Як at(iso) у JS-тестах: годинник показує цей момент.
    @discardableResult
    func at(_ iso: String) -> Moment {
        let value = ms(iso)
        clock.set(value)
        return Moment(ms: value, date: Date(ms: value), now: Logic.kyivParts(ms: value))
    }

    var nowMs: Millis { clock.now() }

    /// Як refresh() у scripting-store.test.mjs: графік однієї адреси, потім сповіщення.
    func refresh(_ iso: String, _ cfg: Config = CFG, force: Bool = false) async -> Refreshed {
        let t = at(iso)
        let data = await store.getSchedule(cfg, t.now, force: force)
        let plan = notifier.update(store, cfg, [data.sched], t.now, t.date)
        return Refreshed(data: data, now: t.now, date: t.date, plan: plan)
    }
}

// MARK: - Сценарій графіка (scripting-logic.test.mjs)

struct Scenario {
    let view: Glance
    let requests: [String]
    let sched: Sched?
    let now: Now
    let nowMs: Millis
}

/// Як scenario() у scripting-logic.test.mjs: завантажити графік із підставних джерел і побудувати вигляд.
func scenario(now iso: String = LOGIC_NOW, cfg: Config = CFG, routes: [String: Route] = [:], fetchedAgoMin: Double = 0) async -> Scenario {
    let nowMs = ms(iso)
    let kyiv = Logic.kyivParts(ms: nowMs)
    let loader = Loader(routes)
    let result = await Logic.fetchSchedule(cfg, kyiv.ymd, loader.load)
    var sched: Sched? = nil
    if case .ok(var found) = result {
        found.fetchedAt = nowMs - fetchedAgoMin * 60000
        sched = found
    }
    let view = Logic.buildGlance(cfg, LightData(sched: sched, status: result.status), kyiv, nowMs: nowMs)
    return Scenario(view: view, requests: loader.requests, sched: sched, now: kyiv, nowMs: nowMs)
}

/// Скільки мілісекунд забрала дія (монотонний годинник).
func timed<T>(_ op: () async throws -> T) async rethrows -> (value: T, ms: Double) {
    let started = ProcessInfo.processInfo.systemUptime
    let value = try await op()
    return (value, (ProcessInfo.processInfo.systemUptime - started) * 1000)
}
