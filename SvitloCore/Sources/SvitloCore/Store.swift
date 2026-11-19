// Налаштування, кеш графіка й тривог і завантаження з мережі. Сховище спільне для застосунку, віджета й кнопок
// у віджеті (App Group). Перенесено з scripting/scripts/Графік світла/store.ts; ключі ті самі.
import Foundation

/// Сховище «ключ → байти»: на телефоні UserDefaults спільної групи, у тестах словник у памʼяті.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Foundation.Data?
    func set(_ data: Foundation.Data?, forKey key: String)
}

public final class MemoryStore: KeyValueStore {
    private let lock = NSLock()
    private var values: [String: Foundation.Data] = [:]
    public init() {}

    public func data(forKey key: String) -> Foundation.Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ data: Foundation.Data?, forKey key: String) {
        lock.lock()
        values[key] = data
        lock.unlock()
    }

    public var keys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values.keys.sorted()
    }
}

/// UserDefaults спільної групи застосунку й віджета.
public final class DefaultsStore: KeyValueStore {
    let defaults: UserDefaults
    public init(_ defaults: UserDefaults) { self.defaults = defaults }
    public convenience init?(suiteName: String) {
        guard let d = UserDefaults(suiteName: suiteName) else { return nil }
        self.init(d)
    }

    public func data(forKey key: String) -> Foundation.Data? { defaults.data(forKey: key) }

    public func set(_ data: Foundation.Data?, forKey key: String) {
        if let data = data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public enum Keys {
    public static let config = "config"
    public static let cache = "cache"
    public static let fact = "fact"
    public static let factNone = "factNone"
    public static let offline = "offline"
    public static let alerts = "alerts" // налаштування модуля тривоги
    public static let alertFeed = "alertFeed"
    public static let alertChannel = "alertChannel"
    public static let locations = "alertLocations"
    public static let page = "page"
    public static let planned = "planned"
    public static let known = "known"

    /// Друга адреса зберігає графік і датчик поруч із першою: «cache2», «fact2».
    public static func slot(_ base: String, _ slot: Int?) -> String {
        guard let s = slot, s > 0 else { return base }
        return "\(base)\(s + 1)"
    }
}

/// Графік і стан датчика однієї адреси.
public struct Fresh: Equatable, Sendable {
    public var data: LightData
    public var fact: Fact?
    public init(data: LightData, fact: Fact?) {
        self.data = data
        self.fact = fact
    }
    public static let empty = Fresh(data: LightData(sched: nil, status: .ok), fact: nil)
    /// Дані для buildGlance: графік разом зі станом датчика.
    public var light: LightData { LightData(sched: data.sched, status: data.status, fact: fact) }
}

public struct SavedFeed: Codable, Equatable {
    public var at: Millis
    public var feed: AlertFeed
}

public struct SavedChannel: Codable, Equatable, Sendable {
    public var id: String
    public var at: Millis
    public var posts: [ChannelPost]
    public var title: String?
}

public struct AlertBundle: Equatable, Sendable {
    public var status: AlertStatus
    public var posts: [ChannelPost]
    public init(status: AlertStatus, posts: [ChannelPost]) {
        self.status = status
        self.posts = posts
    }
}

struct Stamp: Codable { var at: Millis }

/// Запис сторінки, що не ламає розбір усього списку, якщо в ньому чогось бракує.
struct LenientPage: Decodable {
    var page: String?
    var at: Millis?

    enum CodingKeys: String, CodingKey { case page, at }

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        page = (try? c?.decodeIfPresent(String.self, forKey: .page)) ?? nil
        at = (try? c?.decodeIfPresent(Double.self, forKey: .at)) ?? nil
    }
}
struct NoneMark: Codable { var id: String; var checkedAt: Millis }
struct SavedLocations: Codable { var at: Millis; var list: [Location] }

public final class Store: @unchecked Sendable {
    public let kv: KeyValueStore
    public let http: HTTPClient
    public var clock: () -> Millis
    public var log: (String) -> Void

    public init(kv: KeyValueStore, http: HTTPClient, clock: @escaping () -> Millis = { Date().ms }, log: @escaping (String) -> Void = { _ in }) {
        self.kv = kv
        self.http = http
        self.clock = clock
        self.log = log
    }

    // MARK: JSON у сховищі

    public func get<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        guard let data = kv.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func put<T: Encodable>(_ key: String, _ value: T) {
        kv.set(try? JSONEncoder().encode(value), forKey: key)
    }

    public func remove(_ key: String) { kv.set(nil, forKey: key) }

    // MARK: Налаштування

    /// Яку сторінку показує віджет (світло чи тривога): окремо для кожного розміру й адреси.
    public func readPage(_ key: String) -> PageChoice? { pages()[key] }

    public func writePage(_ key: String, _ page: String, nowMs: Millis? = nil) {
        var all = pages()
        all[key] = PageChoice(page: page, at: nowMs ?? clock())
        put(Keys.page, all)
    }

    /// Усі вибори сторінок. Зламаний запис одного віджета пропускаємо, а не губимо вибір решти (як у store.ts).
    func pages() -> [String: PageChoice] {
        guard let raw = get(Keys.page, [String: LenientPage].self) else { return [:] }
        var out: [String: PageChoice] = [:]
        for (key, entry) in raw {
            if let page = entry.page, let at = entry.at { out[key] = PageChoice(page: page, at: at) }
        }
        return out
    }

    public func readConfig() -> Config? {
        guard let cfg = get(Keys.config, Config.self), !cfg.region.isEmpty, !cfg.group.isEmpty else { return nil }
        return cfg
    }

    public func writeConfig(_ cfg: Config) { put(Keys.config, cfg) }

    public func readCache(_ slot: Int? = 0) -> Sched? { get(Keys.slot(Keys.cache, slot), Sched.self) }

    public func clearCache(_ slot: Int? = 0) { remove(Keys.slot(Keys.cache, slot)) }

    // MARK: Збережене: що малювати без мережі

    func cachedSched(_ cfg: Config) -> Sched? {
        guard let cached = readCache(cfg.slot), cached.key == "\(cfg.region)|\(cfg.group)" else { return nil }
        return cached
    }

    func factIdOf(_ cfg: Config) -> String {
        let own = cfg.svitlobot.map { Logic.channelId($0) } ?? ""
        return own.isEmpty ? Logic.queueId(cfg.region, cfg.group) : own
    }

    /// Збережений графік своєї черги: застосунок показує його одразу, ще до мережі.
    public func cachedData(_ cfg: Config?) -> LightData {
        LightData(sched: cfg.flatMap { cachedSched($0) }, status: .ok)
    }

    /// Збережений стан датчика; інший канал чи інша черга: nil.
    public func cachedFact(_ cfg: Config?) -> Fact? {
        guard let cfg = cfg, let saved = get(Keys.slot(Keys.fact, cfg.slot), Fact.self) else { return nil }
        return saved.channel.lowercased() == factIdOf(cfg).lowercased() ? saved : nil
    }

    // MARK: Мережа

    public func startNet(_ budgetMs: Double, _ requestMs: Double = Timing.timeoutSeconds * 1000) -> Net {
        Net(http: http, budgetMs: budgetMs, requestMs: requestMs, clock: clock)
    }

    /// Один запит; у межах одного запуску та сама адреса вантажиться лише раз.
    public func loadText(_ url: String, _ net: Net? = nil) async throws -> String {
        if let net = net { return try await net.load(url) }
        let ms = Timing.timeoutSeconds * 1000
        let http = self.http
        return try await withDeadline(ms) { try await http.get(url, timeoutMs: ms) }
    }

    /// Остання спроба не дістала жодного джерела графіка, тобто інтернету, найпевніше, немає. Кілька хвилин віджет
    /// не йде в мережу, а одразу малює збережене: так кнопка «↻» і віджет після неї не чекають двічі.
    func recentlyOffline() -> Bool {
        guard let saved = get(Keys.offline, Stamp.self) else { return false }
        let age = clock() - saved.at
        return age >= 0 && age < Timing.offlineRetryMinutes * 60000
    }

    func markOffline() { put(Keys.offline, Stamp(at: clock())) }

    /// Перші 10 хвилин після завантаження мережу не чіпаємо. Не вдалося оновити: працюємо зі збереженим.
    /// Кнопка «↻» і застосунок (force) пробують мережу завжди.
    public func getSchedule(_ cfg: Config, _ now: Now, force: Bool, net: Net? = nil) async -> LightData {
        let valid = cachedSched(cfg)
        var ageMinutes = Double.infinity
        if let fetched = valid?.fetchedAt, fetched != 0 { ageMinutes = (clock() - fetched) / 60000 }
        if !force && ageMinutes < Timing.cacheMinutes { return LightData(sched: valid, status: .ok) }
        if !force && recentlyOffline() { return LightData(sched: valid, status: .fail) }
        let result = await Logic.fetchSchedule(cfg, now.ymd, { url in try await self.loadText(url, net) }, clock: clock, log: log)
        switch result {
        case .fail:
            markOffline()
            return LightData(sched: valid, status: .fail)
        case .ok(var sched):
            remove(Keys.offline)
            sched.key = "\(cfg.region)|\(cfg.group)"
            sched.fetchedAt = clock()
            put(Keys.slot(Keys.cache, cfg.slot), sched)
            return LightData(sched: sched, status: .ok)
        case .nogroup:
            remove(Keys.offline)
            return LightData(sched: valid, status: .nogroup)
        }
    }

    /// Графік і датчик кожної адреси паралельно, зі спільним крайнім строком: не довше за budgetMs. Навіть якщо щось
    /// не відпустить після скасування, за budgetMs із запасом буде збережене, і віджет намалюється.
    func freshList(_ list: [Config], _ now: Now, force: Bool, budgetMs: Double, requestMs: Double) async -> [Fresh] {
        if list.isEmpty { return [Fresh.empty] }
        let net = startNet(budgetMs, requestMs)
        return await withFallback(after: budgetMs + 1500, {
            self.markOffline()
            return list.map { Fresh(data: LightData(sched: self.cachedSched($0), status: .fail), fact: self.cachedFact($0)) }
        }) {
            await withTaskGroup(of: (Int, Fresh).self) { group in
                for (i, cfg) in list.enumerated() {
                    group.addTask {
                        async let data = self.getSchedule(cfg, now, force: force, net: net)
                        async let fact = self.getFact(cfg, force: force, net: net)
                        return (i, Fresh(data: await data, fact: await fact))
                    }
                }
                var out = [Fresh](repeating: Fresh.empty, count: list.count)
                for await (i, fresh) in group { out[i] = fresh }
                return out
            }
        }
    }

    /// Одна адреса (cfg уже з тією чергою, яку треба).
    public func freshData(_ cfg: Config?, _ now: Now, force: Bool, budgetMs: Double, requestMs: Double) async -> Fresh {
        guard let cfg = cfg else { return Fresh.empty }
        return await freshList([cfg], now, force: force, budgetMs: budgetMs, requestMs: requestMs)[0]
    }

    /// Усі адреси з налаштувань: [перша, друга]. Віджет і кнопка «↻» оновлюють обидві, бо сповіщення про обидві.
    public func freshAll(_ base: Config?, _ now: Now, force: Bool, budgetMs: Double, requestMs: Double) async -> [Fresh] {
        await freshList(Logic.addressesOf(base), now, force: force, budgetMs: budgetMs, requestMs: requestMs)
    }

    /// Дані для віджета по всіх адресах. Щойно торкнулися значка в стовпчику (quick): лише збережене,
    /// без мережі, щоб сторінка перемикалася одразу. Свіже підтягне планове оновлення.
    public func widgetDataAll(_ base: Config?, _ now: Now, quick: Bool) async -> [Fresh] {
        let list = Logic.addressesOf(base)
        if quick { return list.isEmpty ? [Fresh.empty] : list.map { Fresh(data: cachedData($0), fact: cachedFact($0)) } }
        return await freshAll(base, now, force: false, budgetMs: Timing.widgetBudgetMs, requestMs: Timing.widgetRequestMs)
    }

    /// Збережене всіх адрес, без мережі.
    public func cachedAll(_ base: Config?) -> [Fresh] {
        let list = Logic.addressesOf(base)
        return list.isEmpty ? [Fresh.empty] : list.map { Fresh(data: cachedData($0), fact: cachedFact($0)) }
    }

    public func loadGroups(_ region: Region) async throws -> [String] {
        try await Logic.groupsFor(region) { url in try await self.loadText(url) }
    }

    /// Усі канали СвітлоБота: для пошуку датчика в застосунку.
    public func loadChannels() async throws -> [Channel] {
        Logic.parseChannels(try await loadText(SvitloBot.list))
    }

    /// Фактичний стан: обраний датчик, а без нього всі датчики СвітлоБота з черги користувача.
    /// Перші 4 хвилини після перевірки мережу не чіпаємо; без мережі віддаємо збережене. У черзі немає датчиків: nil.
    public func getFact(_ cfg: Config?, force: Bool, net: Net? = nil) async -> Fact? {
        guard let cfg = cfg else { return nil }
        let own = cfg.svitlobot.map { Logic.channelId($0) } ?? ""
        let id = factIdOf(cfg)
        let same = cachedFact(cfg)
        let nowMs = clock()
        if !force, let same = same, nowMs - same.checkedAt < Timing.factCacheMinutes * 60000 { return same }
        if !force && recentlyOffline() { return same }
        if !own.isEmpty { return await ownFact(cfg, own, same, nowMs, net) }
        // У черзі датчиків не було: перепитуємо раз на годину, а не за кожним оновленням віджета.
        let noneKey = Keys.slot(Keys.factNone, cfg.slot)
        if !force, same == nil, let none = get(noneKey, NoneMark.self), none.id == id, nowMs - none.checkedAt < 60 * 60000 { return nil }
        do {
            let list = Logic.parseChannels(try await loadText(SvitloBot.list, net))
            let queue = Logic.queueFact(same, list, cfg.region, cfg.group, nowMs)
            if let queue = queue {
                put(Keys.slot(Keys.fact, cfg.slot), queue)
                remove(noneKey)
            } else {
                remove(Keys.slot(Keys.fact, cfg.slot))
                put(noneKey, NoneMark(id: id, checkedAt: nowMs))
            }
            return queue
        } catch {
            return same
        }
    }

    /// Власний канал: спершу його дописи в Telegram (працює одразу, без модерації СвітлоБота й з точною тривалістю),
    /// а якщо дописів про світло немає чи сторінка недоступна, то список СвітлоБота.
    func ownFact(_ cfg: Config, _ id: String, _ same: Fact?, _ nowMs: Millis, _ net: Net?) async -> Fact? {
        if let html = try? await loadText(SvitloBot.posts(id), net),
           let fromPosts = Logic.postsFact(Logic.parseStatusPosts(html), id, cfg.svitlobotName ?? id, nowMs) {
            put(Keys.slot(Keys.fact, cfg.slot), fromPosts)
            return fromPosts
        }
        do {
            let list = Logic.parseChannels(try await loadText(SvitloBot.list, net))
            let fact = Logic.mergeFact(same, Logic.findChannel(list, id), id, nowMs)
            put(Keys.slot(Keys.fact, cfg.slot), fact)
            return fact
        } catch {
            return same
        }
    }

    // MARK: Повітряна тривога

    public func readAlerts() -> AlertSettings { get(Keys.alerts, AlertSettings.self) ?? AlertSettings() }

    public func writeAlerts(_ settings: AlertSettings) { put(Keys.alerts, settings) }

    func savedFeed() -> SavedFeed? { get(Keys.alertFeed, SavedFeed.self) }

    func savedChannel(_ id: String) -> SavedChannel? {
        guard let saved = get(Keys.alertChannel, SavedChannel.self), saved.id == id else { return nil }
        return saved
    }

    /// Усі активні тривоги України (близько 1–2 КБ). Повторний запит протягом cacheSeconds не йде в мережу.
    public func getAlertFeed(force: Bool, net: Net? = nil) async -> AlertFeed? {
        let saved = savedFeed()
        let nowMs = clock()
        if !force, let saved = saved, nowMs - saved.at >= 0, nowMs - saved.at < AlertConfig.cacheSeconds * 1000 { return saved.feed }
        if !force && recentlyOffline() { return saved?.feed }
        if let text = try? await loadText(AlertConfig.feed, net) {
            let feed = AlertLogic.parseAlertFeed(text)
            if feed.ok {
                put(Keys.alertFeed, SavedFeed(at: nowMs, feed: feed))
                return feed
            }
        }
        return saved?.feed
    }

    /// Публічний канал моніторингу: дописи й назва. maxAgeSeconds: коли щось відбувається, частіше.
    public func getChannelPosts(_ id: String, maxAgeSeconds: Double, force: Bool, net: Net? = nil) async -> SavedChannel? {
        let saved = savedChannel(id)
        let nowMs = clock()
        if !force, let saved = saved, nowMs - saved.at >= 0, nowMs - saved.at < maxAgeSeconds * 1000 { return saved }
        if !force && recentlyOffline() { return saved }
        guard let html = try? await loadText(AlertLogic.channelUrl(id), net) else { return saved }
        let fresh = SavedChannel(
            id: id, at: nowMs, posts: AlertLogic.parseChannelPosts(html),
            title: AlertLogic.parseChannelTitle(html) ?? saved?.title
        )
        put(Keys.alertChannel, fresh)
        return fresh
    }

    /// Канал для налаштувань: чи він є й публічний. Закритий канал чи помилка в назві: nil.
    public func checkChannel(_ id: String) async throws -> SavedChannel? {
        let html = try await loadText(AlertLogic.channelUrl(id))
        guard let title = AlertLogic.parseChannelTitle(html), Re("tgme_channel_info|tgme_widget_message").test(html) else { return nil }
        let fresh = SavedChannel(id: id, at: clock(), posts: AlertLogic.parseChannelPosts(html), title: title)
        put(Keys.alertChannel, fresh)
        return fresh
    }

    /// Стан тривоги зі збереженого, без мережі. Модуль вимкнено: nil.
    public func cachedAlerts(_ settings: AlertSettings, nowMs: Millis? = nil) -> AlertBundle? {
        guard settings.isOn else { return nil }
        let now = nowMs ?? clock()
        let status = AlertLogic.alertStatus(settings.place, savedFeed()?.feed, now)
        let channel = settings.channel.flatMap { savedChannel($0) }
        let posts = channel?.posts ?? []
        return AlertBundle(status: AlertLogic.withPosts(status, posts, channel?.title, now), posts: posts)
    }

    func loadAlerts(_ settings: AlertSettings, force: Bool, net: Net) async -> AlertBundle {
        let before = cachedAlerts(settings)
        let feed = await getAlertFeed(force: force, net: net)
        let nowMs = clock()
        let status = AlertLogic.alertStatus(settings.place, feed, nowMs)
        guard let channelId = settings.channel, status.kind != .setup else { return AlertBundle(status: status, posts: []) }
        // Канал частіше, коли щось відбувається (за щойно отриманим станом і збереженими дописами).
        let maxAge = AlertLogic.busy(status, before?.posts, nowMs) ? AlertConfig.channelBusySeconds : AlertConfig.channelQuietSeconds
        let channel = await getChannelPosts(channelId, maxAgeSeconds: maxAge, force: force, net: net)
        let posts = channel?.posts ?? []
        return AlertBundle(status: AlertLogic.withPosts(status, posts, channel?.title, clock()), posts: posts)
    }

    /// Тривоги з мережі не довше за budgetMs (як і графік): без інтернету — збережене. Модуль вимкнено: nil.
    public func freshAlerts(_ settings: AlertSettings, force: Bool, budgetMs: Double, requestMs: Double) async -> AlertBundle? {
        guard settings.isOn else { return nil }
        if AlertLogic.cleanPlace(settings.place) == nil { return cachedAlerts(settings) }
        let net = startNet(budgetMs, requestMs)
        return await withFallback(after: budgetMs + 1500, { self.cachedAlerts(settings) }) {
            await self.loadAlerts(settings, force: force, net: net)
        }
    }

    /// Збережений список місць: застосунок показує вибір району й громади одразу, ще до мережі.
    public func cachedLocations() -> [Location]? {
        guard let saved = get(Keys.locations, SavedLocations.self), !saved.list.isEmpty else { return nil }
        return saved.list
    }

    /// Області → райони → громади для вибору місця. Список оновлюємо раз на тиждень; без мережі — збережений,
    /// а якщо його ще немає, то лише області.
    public func loadLocations(force: Bool = false) async -> [Location] {
        let saved = get(Keys.locations, SavedLocations.self)
        let valid = (saved?.list.isEmpty == false) ? saved : nil
        if !force, let valid = valid, clock() - valid.at < AlertConfig.locationsDays * 86_400_000 { return valid.list }
        if let text = try? await loadText(AlertConfig.locations) {
            let list = AlertLogic.parseLocations(text)
            if !list.isEmpty {
                put(Keys.locations, SavedLocations(at: clock(), list: list))
                return list
            }
        }
        return valid?.list ?? AlertLogic.defaultOblasts()
    }
}
