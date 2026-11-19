// Застосунок «Графік світла»: три вкладки, як у «Маяку» для Android. «Світло» — головна картка стану, години
// відключень, черга, датчик, сповіщення й друга адреса; «Тривога» — картка тривоги й її налаштування;
// «Віджет» — вигляд, фон, як додати віджет і що означають його кнопки.
import SwiftUI
import UIKit
import Combine
import BackgroundTasks
import WidgetKit
import SvitloCore

@main
struct GrafikApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { BackgroundRefresh.schedule() }
        }
        // Фонове оновлення: iOS сама вирішує коли (зазвичай кілька разів на день). Так «графік змінився»
        // приходить і тоді, коли віджета на екрані немає.
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            BackgroundRefresh.schedule()
            let result = await Updater.refreshAll(force: false, budgetMs: 20000)
            // З фону Live Activity не почати, але оновити чи прибрати після відбою можна.
            await LiveAlerts.sync(result.alerts, settings: Shared.store.readAlerts())
            await Widgets.reload()
        }
    }
}

enum BackgroundRefresh {
    /// Береться прямо з BGTaskSchedulerPermittedIdentifiers в Info.plist: після сайдлоаду Bundle ID інший,
    /// а ідентифікатор, якого немає в цьому списку, iOS не приймає (застосунок упав би на запуску).
    static var id: String {
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.first
            ?? ((Bundle.main.bundleIdentifier ?? "ua.maiak.grafik") + ".refresh")
    }

    /// Попросити iOS про наступне фонове оновлення не раніше ніж за 30 хвилин.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let minute = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $model.tab) {
            LightTab()
                .tabItem { Label("Світло", systemImage: "bolt.fill") }
                .tag(0)
            AlertTab()
                .tabItem { Label("Тривога", systemImage: "light.beacon.max.fill") }
                .tag(1)
                .badge(AlertLogic.active(model.alertStatus) ? Text("!") : nil)
            WidgetTab()
                .tabItem { Label("Віджет", systemImage: "square.grid.2x2.fill") }
                .tag(2)
        }
        .tint(Palette.brand)
        .task { await model.start() }
        .onReceive(minute) { model.now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.now = Date()
                Task { await model.refresh(model.cfg, force: false) }
                Task { await model.refreshAlerts(model.alertSet, force: false) }
            }
        }
        // Дотик до віджета відкриває його сторінку: grafiksvitla://light або grafiksvitla://alert.
        .onOpenURL { url in
            model.tab = url.host == AlertLogic.alert ? 1 : 0
        }
    }
}

/// Кольори застосунку з палітри B (пари для світлої й темної теми iPhone).
enum Palette {
    static let brand = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.78, green: 0.79, blue: 1, alpha: 1) : UIColor(red: 0.26, green: 0.28, blue: 0.71, alpha: 1) })

    static func dynamic(_ light: RGBA, _ dark: RGBA) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }
}
