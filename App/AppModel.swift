// Стан застосунку й дії користувача (порт логіки index.tsx). Зміни одразу видно у віджеті:
// після кожної дії просимо WidgetKit перемалювати таймлайни.
import Foundation
import SwiftUI
import WidgetKit
import SvitloCore

@MainActor
final class AppModel: ObservableObject {
    let store = Shared.store

    // У всіх полів є початкові значення, тож init нижче лише підставляє збережене.
    @Published var tab = 0
    @Published var cfg: Config? = nil
    // Область не обрано, поки користувач не обере сам.
    @Published var region = ""
    @Published var groups: [String] = []
    @Published var groupsError: String? = nil
    // Збережене видно одразу, ще до мережі: без інтернету застосунок не порожній.
    @Published var data = LightData(sched: nil, status: .ok)
    @Published var loading = false
    @Published var fact: Fact? = nil
    @Published var factLoaded = false
    @Published var query = ""
    @Published var channels: [Channel]? = nil
    @Published var channelsError: String? = nil
    // Друга адреса.
    @Published var data2 = LightData(sched: nil, status: .ok)
    @Published var fact2: Fact? = nil
    @Published var region2 = ""
    @Published var groups2: [String] = []
    @Published var groups2Error: String? = nil
    @Published var name2 = ""
    // Повітряна тривога.
    @Published var alertSet = AlertSettings()
    @Published var alertBundle: AlertBundle? = nil
    @Published var alertLoading = false
    @Published var locations: [Location] = []
    @Published var channelInput = ""
    @Published var channelError: String? = nil
    /// «Зараз» для написів і таймерів; оновлюється щохвилини.
    @Published var now = Date()

    init() {
        let store = Shared.store
        let cfg = store.readConfig()
        let second = Logic.addressesOf(cfg)[safe: 1]
        self.cfg = cfg
        region = cfg?.region ?? ""
        groups = AppModel.initialGroups(cfg?.region ?? "", cfg?.group)
        data = store.cachedData(cfg)
        fact = store.cachedFact(cfg)
        data2 = store.cachedData(second)
        fact2 = store.cachedFact(second)
        region2 = cfg?.second?.region ?? cfg?.region ?? ""
        groups2 = AppModel.initialGroups(cfg?.second?.region ?? "", cfg?.second?.group)
        name2 = cfg?.second?.name ?? ""
        let alerts = store.readAlerts()
        alertSet = alerts
        alertBundle = store.cachedAlerts(alerts)
        locations = store.cachedLocations() ?? AlertLogic.defaultOblasts()
    }

    /// Черги, які можна показати одразу, ще до мережі: у Запоріжжі список сталий, деінде хоча б обрана черга.
    static func initialGroups(_ regionId: String, _ current: String?) -> [String] {
        if Logic.regionById(regionId)?.official == true { return zoeGroups }
        return current.map { [$0] } ?? []
    }

    // MARK: Похідне

    var kyivNow: Now { Logic.kyivParts(now) }
    var view: Glance { Logic.buildGlance(cfg, LightData(sched: data.sched, status: data.status, fact: fact), kyivNow, nowMs: now.ms) }
    var second: Config? { Logic.addressesOf(cfg)[safe: 1] }
    var view2: Glance { Logic.buildGlance(second, LightData(sched: data2.sched, status: data2.status, fact: fact2), kyivNow, nowMs: now.ms) }
    var prefs: NotifyPrefs { cfg.map { Logic.notifyPrefs($0) } ?? NotifyPrefs() }
    var official: Bool { Logic.regionById(region)?.official == true }
    var alertStatus: AlertStatus? { alertSet.isOn ? alertBundle?.status : nil }
    var place: Place? { AlertLogic.cleanPlace(alertSet.place) }
    var oblast: Location? { AppModel.find(locations, place?.oblast) }
    var raion: Location? { oblast.flatMap { AppModel.find($0.children, place?.raion) } }

    var found: [Channel] {
        guard let channels = channels, !query.trimmed.isEmpty else { return [] }
        return Logic.searchChannels(channels, query)
    }

    /// Новий канал зʼявляється в пошуку лише після модерації СвітлоБота (кілька днів), а за посиланням працює одразу.
    var directNew: String {
        let direct = Logic.channelId(query)
        guard direct.lowercased().hasPrefix("svitlobot_") else { return "" }
        return found.contains { $0.id.lowercased() == direct.lowercased() } ? "" : direct
    }

    static func find(_ list: [Location], _ uid: String?) -> Location? {
        guard let uid = uid, !uid.isEmpty else { return nil }
        return list.first { $0.uid == uid }
    }

    // MARK: Оновлення

    func start() async {
        if cfg != nil { await Notifier.requestPermission() }
        async let light: Void = refresh(cfg, force: true)
        async let alerts: Void = startAlerts()
        _ = await (light, alerts)
        if !region.isEmpty { await loadGroups(second: false) }
        if cfg?.second != nil, !region2.isEmpty { await loadGroups(second: true) }
    }

    private func startAlerts() async {
        guard alertSet.isOn else { return }
        locations = await store.loadLocations()
        await refreshAlerts(alertSet, force: true)
    }

    func refresh(_ next: Config?, force: Bool) async {
        guard let next = next else { return }
        loading = true
        let date = Date()
        // Обидві адреси разом: сповіщення про обидві.
        let all = await store.freshAll(next, Logic.kyivParts(date), force: force, budgetMs: Timing.appBudgetMs,
                                       requestMs: Timing.timeoutSeconds * 1000)
        data = all[0].data
        fact = all[0].fact
        factLoaded = true
        data2 = all[safe: 1]?.data ?? LightData(sched: nil, status: .ok)
        fact2 = all[safe: 1]?.fact
        await Notifier.update(next, all.map { $0.data.sched }, store: store, timeoutMs: 4000)
        loading = false
        now = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refreshAlerts(_ next: AlertSettings, force: Bool) async {
        guard next.isOn else { return }
        alertLoading = true
        alertBundle = await store.freshAlerts(next, force: force, budgetMs: Timing.appBudgetMs, requestMs: Timing.timeoutSeconds * 1000)
        alertLoading = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveAlerts(_ next: AlertSettings) {
        store.writeAlerts(next)
        alertSet = next
        alertBundle = store.cachedAlerts(next)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Черга

    func setRegion(_ id: String) {
        region = id
        groups = AppModel.initialGroups(id, cfg?.region == id ? cfg?.group : nil)
        Task { await loadGroups(second: false) }
    }

    func setRegion2(_ id: String) {
        region2 = id
        groups2 = AppModel.initialGroups(id, cfg?.second?.region == id ? cfg?.second?.group : nil)
        Task { await loadGroups(second: true) }
    }

    func loadGroups(second: Bool) async {
        let id = second ? region2 : region
        guard let found = Logic.regionById(id) else {
            if second { groups2 = [] } else { groups = [] }
            return
        }
        if second { groups2Error = nil } else { groupsError = nil }
        do {
            let list = try await store.loadGroups(found)
            if (second ? region2 : region) != id { return } // поки вантажили, обрали іншу область
            if second { groups2 = list } else { groups = list }
            if list.isEmpty {
                let message = "Для цього регіону зараз немає списку черг."
                if second { groups2Error = message } else { groupsError = message }
            }
        } catch {
            if (second ? region2 : region) != id { return }
            let message = "Не вдалося завантажити список черг. Перевірте інтернет."
            if second {
                groups2 = []
                groups2Error = message
            } else {
                groups = []
                groupsError = message
            }
        }
    }

    /// Нова черга: старий кеш і памʼять про графік для сповіщень уже не годяться.
    func chooseGroup(_ group: String) async {
        guard !group.isEmpty, !region.isEmpty else { return }
        var next = cfg ?? Config(region: region, group: group)
        next.region = region
        next.group = group
        store.writeConfig(next)
        cfg = next
        store.clearCache()
        Notifier.reset(store: store)
        await Notifier.requestPermission()
        await refresh(next, force: true)
    }

    func update(_ change: (inout Config) -> Void) async {
        guard var next = cfg else { return }
        change(&next)
        store.writeConfig(next)
        cfg = next
        await Notifier.update(next, [data.sched, data2.sched], store: store, timeoutMs: 4000)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Датчик

    func searchIfNeeded() {
        // Список датчиків вантажимо лише тоді, коли почали шукати.
        guard !query.trimmed.isEmpty, channels == nil else { return }
        channelsError = nil
        Task {
            do {
                channels = try await store.loadChannels()
            } catch {
                channelsError = "Не вдалося завантажити датчики. Перевірте інтернет."
            }
        }
    }

    func chooseSensor(_ channel: Channel) async {
        guard var next = cfg else { return }
        next.svitlobot = channel.id
        next.svitlobotName = channel.name
        store.writeConfig(next)
        cfg = next
        query = ""
        fact = await store.getFact(next, force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Без свого датчика знову працює факт за чергою.
    func removeSensor() async {
        guard var next = cfg else { return }
        next.svitlobot = nil
        next.svitlobotName = nil
        store.writeConfig(next)
        cfg = next
        fact = await store.getFact(next, force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Друга адреса

    /// Друга адреса зберігається, щойно обрали чергу. Її кеш і памʼять про графік починаються з нуля.
    func chooseSecondGroup(_ group: String) async {
        guard var next = cfg, !group.isEmpty else { return }
        let name = name2.trimmed
        next.second = Address(name: name.isEmpty ? secondName : name, region: region2, group: group)
        store.writeConfig(next)
        cfg = next
        store.clearCache(1)
        store.forgetSecond()
        await refresh(next, force: true)
    }

    func renameSecond(_ value: String) {
        name2 = value
        guard var next = cfg, let second = next.second else { return }
        let name = value.trimmed
        next.second = Address(name: name.isEmpty ? secondName : name, region: second.region, group: second.group)
        store.writeConfig(next)
        cfg = next
    }

    func renameFirst(_ value: String) {
        guard var next = cfg else { return }
        let name = value.trimmed
        next.name = name.isEmpty ? nil : name
        store.writeConfig(next)
        cfg = next
    }

    func removeSecond() async {
        guard var next = cfg else { return }
        next.second = nil
        store.writeConfig(next)
        cfg = next
        store.clearCache(1)
        store.forgetSecond()
        name2 = ""
        data2 = LightData(sched: nil, status: .ok)
        fact2 = nil
        await refresh(next, force: false)
    }

    // MARK: Тривога

    /// Перше ввімкнення: місце одразу стоїть на області світла, якщо її обрано.
    func toggleAlerts(_ on: Bool) {
        var next = alertSet
        next.enabled = on
        if on && AlertLogic.cleanPlace(next.place) == nil {
            let uid = AlertLogic.oblastForRegion(cfg?.region)
            let oblast = AppModel.find(locations, uid) ?? AppModel.find(AlertLogic.defaultOblasts(), uid)
            next.place = oblast.map { Place(oblast: $0.uid, oblastTitle: $0.title) }
        }
        saveAlerts(next)
        if on {
            Task {
                locations = await store.loadLocations()
                await refreshAlerts(next, force: true)
            }
        }
    }

    func choosePlace(_ place: Place?) {
        var next = alertSet
        next.place = place
        saveAlerts(next)
        Task { await refreshAlerts(next, force: false) }
    }

    func chooseOblast(_ uid: String) {
        let o = AppModel.find(locations, uid)
        choosePlace(o.map { Place(oblast: $0.uid, oblastTitle: $0.title) })
    }

    func chooseRaion(_ uid: String) {
        guard let oblast = oblast else { return }
        if let r = AppModel.find(oblast.children, uid) {
            choosePlace(Place(oblast: oblast.uid, oblastTitle: oblast.title, raion: r.uid, raionTitle: r.title))
        } else {
            choosePlace(Place(oblast: oblast.uid, oblastTitle: oblast.title))
        }
    }

    func chooseHromada(_ uid: String) {
        guard let oblast = oblast, let raion = raion else { return }
        let base = Place(oblast: oblast.uid, oblastTitle: oblast.title, raion: raion.uid, raionTitle: raion.title)
        if let h = AppModel.find(raion.children, uid) {
            var place = base
            place.hromada = h.uid
            place.hromadaTitle = h.title
            choosePlace(place)
        } else {
            choosePlace(base)
        }
    }

    func connectChannel() async {
        let id = AlertLogic.channelName(channelInput)
        if id.isEmpty {
            channelError = "Вставте посилання на канал (t.me/назва) або @назва."
            return
        }
        channelError = nil
        do {
            guard let found = try await store.checkChannel(id) else {
                channelError = "Канал не знайдено або він закритий: підходять лише публічні канали."
                return
            }
            var next = alertSet
            next.channel = id
            next.channelTitle = found.title ?? id
            channelInput = ""
            saveAlerts(next)
            await refreshAlerts(next, force: false)
        } catch {
            channelError = "Не вдалося відкрити канал. Перевірте інтернет."
        }
    }

    func removeChannel() {
        var next = alertSet
        next.channel = nil
        next.channelTitle = nil
        saveAlerts(next)
    }
}
