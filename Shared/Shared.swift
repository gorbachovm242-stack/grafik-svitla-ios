// Спільне для застосунку й віджета: сховище App Group, кольори палітри в SwiftUI, оновлення «все разом».
import Foundation
import SwiftUI
import WidgetKit
import SvitloCore

enum Widgets {
    /// Перемалювати всі віджети. Через головний потік: так безпечно звідусіль (кнопки, фон, застосунок).
    static func reload() async {
        await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
    }
}

enum AppGroup {
    /// Назва групи з Info.plist (AppGroupID = $(APP_GROUP_ID) у project.yml), тож міняти її в одному місці.
    /// Після сайдлоаду інструмент перейменовує групу, тож справжню беремо з вбудованого профілю підпису.
    static let id: String = {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.ua.maiak.grafik"
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let profile = try? Foundation.Data(contentsOf: url) else { return configured }
        return AppGroupLookup.pick(configured: configured, available: AppGroupLookup.groups(fromProfile: profile))
    }()
}

enum Shared {
    /// Одне сховище на процес: застосунок, віджет і кнопки у віджеті бачать ті самі дані через App Group.
    static let store: Store = {
        let kv: KeyValueStore = DefaultsStore(suiteName: AppGroup.id) ?? MemoryStore()
        return Store(kv: kv, http: URLSessionClient())
    }()

    static let deepLinkScheme = "grafiksvitla"
}

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

extension Array where Element == RGBA {
    var gradient: Gradient { Gradient(colors: map { $0.color }) }
}

extension Array {
    subscript(safe index: Int) -> Element? { index >= 0 && index < count ? self[index] : nil }
}

/// Фон віджета чи сторінки тривоги: діагональний градієнт; alpha 0 — без фону.
struct TokenBackground: View {
    let bg0: RGBA
    let bg1: RGBA
    let alpha: Double
    var vertical = false

    var body: some View {
        if alpha <= 0 {
            Color.clear
        } else {
            LinearGradient(
                colors: [bg0.color, bg1.color],
                startPoint: vertical ? .top : .topLeading,
                endPoint: vertical ? .bottom : .bottomTrailing
            )
        }
    }
}

/// Оновлення «все разом»: графік і датчик обох адрес, тривоги й сповіщення.
/// Кнопка «↻» у віджеті й застосунок кличуть саме це.
enum Updater {
    @discardableResult
    static func refreshAll(force: Bool, budgetMs: Double, requestMs: Double = Timing.widgetRequestMs) async -> (fresh: [Fresh], alerts: AlertBundle?) {
        let store = Shared.store
        let base = store.readConfig()
        let date = Date()
        async let fresh = store.freshAll(base, Logic.kyivParts(date), force: force, budgetMs: budgetMs, requestMs: requestMs)
        async let alerts = store.freshAlerts(store.readAlerts(), force: force, budgetMs: budgetMs, requestMs: requestMs)
        let result = await (fresh: fresh, alerts: alerts)
        if let base = base {
            await Notifier.update(base, result.fresh.map { $0.data.sched }, store: store, timeoutMs: 3000)
        }
        return result
    }
}
