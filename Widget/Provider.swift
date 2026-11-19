// Таймлайн віджета: бере графік (кеш 10 хвилин) і, якщо ввімкнено, тривоги, оновлює сповіщення й віддає iOS
// записи наперед: «зараз», кожна зміна графіка, кожна година, північ, повернення сторінки тривоги на світло.
import WidgetKit
import SwiftUI
import SvitloCore

struct LightEntry: TimelineEntry {
    let date: Date
    let model: WidgetModel
}

struct Provider: AppIntentTimelineProvider {
    typealias Entry = LightEntry
    typealias Intent = SelectAddressIntent

    func placeholder(in context: Context) -> LightEntry {
        LightEntry(date: Date(), model: Provider.sample(context.family, context.displaySize))
    }

    /// Галерея віджетів і попередній перегляд: лише збережене, без мережі.
    func snapshot(for configuration: SelectAddressIntent, in context: Context) async -> LightEntry {
        let store = Shared.store
        if store.readConfig() == nil { return placeholder(in: context) }
        return Provider.entries(configuration, context, fresh: store.cachedAll(store.readConfig()), alerts: store.cachedAlerts(store.readAlerts()))
            .first ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectAddressIntent, in context: Context) async -> Timeline<LightEntry> {
        let store = Shared.store
        let base = store.readConfig()
        let settings = store.readAlerts()
        let pages = AlertLogic.pagesOf(settings.isOn)
        let key = Provider.pageKey(configuration, context, base)
        let started = Date()
        let mode = AlertLogic.pageMode(store.readPage(key), pages, started.ms)
        // Щойно торкнулися значка в стовпчику: малюємо збережене одразу, а мережу лишаємо плановому оновленню.
        // Інакше графік, датчик і тривоги паралельно й не довше за widgetBudgetMs: без інтернету віджет малює
        // збережене, а не чекає, доки iOS його зупинить.
        let all: [Fresh]
        let alerts: AlertBundle?
        if mode.quick {
            all = store.cachedAll(base)
            alerts = store.cachedAlerts(settings)
        } else {
            async let fresh = store.widgetDataAll(base, Logic.kyivParts(started), quick: false)
            async let bundle = store.freshAlerts(settings, force: false, budgetMs: Timing.widgetBudgetMs, requestMs: Timing.widgetRequestMs)
            let result = await (fresh, bundle)
            all = result.0
            alerts = result.1
        }
        // Сповіщення про обидві адреси, хоч віджет показує одну.
        if let base = base, !mode.quick {
            await Notifier.update(base, all.map { $0.data.sched }, store: store, timeoutMs: 3000)
        }
        let entries = Provider.entries(configuration, context, fresh: all, alerts: alerts)
        // Самі зміни графіка вже стоять у записах. Між ними просимо iOS оновити дані: раз на 30 хвилин,
        // з датчиком раз на 15, з тривогами раз на 15 або 5 (iOS однаково вирішує сама, коли саме).
        let date = Date()
        let alertMinutes = alerts.map { AlertLogic.alertRefreshMinutes($0.status, $0.posts, date.ms) }
        let reload = WidgetTimeline.reloadDate(entries.first?.model.glance ?? Glance(), date, alertMinutes: alertMinutes)
        return Timeline(entries: entries, policy: .after(reload))
    }

    /// Який це віджет: розмір і адреса. Інші віджети лишаються на своїх сторінках.
    static func pageKey(_ configuration: SelectAddressIntent, _ context: Context, _ base: Config?) -> String {
        AlertLogic.pageKey(context.family.key, Provider.slot(configuration, base) == 1 ? "2" : "")
    }

    static func slot(_ configuration: SelectAddressIntent, _ base: Config?) -> Int {
        configuration.address == .second && Logic.hasSecond(base) ? 1 : 0
    }

    /// Записи таймлайну з уже отриманих даних: для кожного моменту свій стан графіка й своя сторінка.
    static func entries(_ configuration: SelectAddressIntent, _ context: Context, fresh: [Fresh], alerts: AlertBundle?) -> [LightEntry] {
        let store = Shared.store
        let base = store.readConfig()
        let index = Provider.slot(configuration, base)
        let cfg = Logic.addressesOf(base)[safe: index]
        let pick = fresh[safe: index] ?? fresh.first ?? Fresh.empty
        let pages = AlertLogic.pagesOf(alerts != nil)
        let key = Provider.pageKey(configuration, context, base)
        let choice = store.readPage(key)
        let date = Date()
        var extra: [Date] = []
        if let until = AlertLogic.pageMode(choice, pages, date.ms).until { extra.append(Date(ms: until + 1000)) }
        if let stale = WidgetTimeline.staleDate(pick.data.sched) { extra.append(stale) }
        return WidgetTimeline.entryDates(pick.data.sched, from: date, extra: extra).map { moment in
            let now = Logic.kyivParts(moment)
            let model = WidgetModel(
                glance: Logic.buildGlance(cfg, pick.light, now, nowMs: moment.ms),
                now: now, date: moment, family: context.family, size: context.displaySize,
                alert: alerts?.status, pages: pages,
                page: AlertLogic.pageMode(choice, pages, moment.ms).page, pageKey: key
            )
            return LightEntry(date: moment, model: model)
        }
    }

    /// Зразок для галереї віджетів: черга 3.2, світло до 14:00, потім відключення до 18:00.
    static func sample(_ family: WidgetFamily, _ size: CGSize) -> WidgetModel {
        let date = Date()
        let now = Logic.kyivParts(date)
        let runs = [Run(s: 0, e: 360, st: .off), Run(s: 360, e: 840, st: .on), Run(s: 840, e: 1080, st: .off), Run(s: 1080, e: 1440, st: .on)]
        let sched = Sched(days: [now.ymd: Day(status: .ok, runs: runs)], emergency: false, fetchedAt: date.ms)
        let cfg = Config(region: "zaporizhzhia", group: "3.2")
        let glance = Logic.buildGlance(cfg, LightData(sched: sched, status: .ok), now, nowMs: date.ms)
        return WidgetModel(glance: glance, now: now, date: date, family: family, size: size, alert: nil,
                           pages: [AlertLogic.light], page: AlertLogic.light, pageKey: "")
    }
}

struct LightWidgetView: View {
    let entry: LightEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        WidgetContent(m: entry.model, dark: colorScheme == .dark, clear: renderingMode != .fullColor)
    }
}
