// Кнопки у віджеті (App Intents, iOS 17+) і вибір адреси в налаштуваннях віджета.
// «↻»: свіжий графік і стан датчика з мережі (для обох адрес), тривоги й канал моніторингу, сповіщення,
// і віджет перемальовується одразу. Значки в стовпчику: показати сторінку модуля (світло чи тривога).
import AppIntents
import WidgetKit
import SvitloCore

struct RefreshIntent: AppIntent {
    static let title: LocalizedStringResource = "Оновити графік світла"
    static let description = IntentDescription("Свіжий графік, датчик і тривоги; віджет одразу перемальовується.")

    init() {}

    func perform() async throws -> some IntentResult {
        // Без інтернету не довше за buttonBudgetMs, а віджет після цього одразу малює збережене.
        await Updater.refreshAll(force: true, budgetMs: Timing.buttonBudgetMs)
        await Widgets.reload()
        return .result()
    }
}

/// key: який це віджет (розмір і адреса), щоб інші віджети лишилися на своїх сторінках.
/// Сторінку тривоги спершу коротко оновлюємо, тож вона одразу свіжа; далі віджет малює збережене без мережі.
struct PageIntent: AppIntent {
    static let title: LocalizedStringResource = "Сторінка віджета"
    static let description = IntentDescription("Показати у віджеті світло або тривогу.")

    @Parameter(title: "Сторінка")
    var page: String

    @Parameter(title: "Віджет")
    var key: String

    init() {}

    init(page: String, key: String) {
        self.page = page
        self.key = key
    }

    func perform() async throws -> some IntentResult {
        let store = Shared.store
        store.writePage(key, page)
        if page == AlertLogic.alert {
            _ = await store.freshAlerts(store.readAlerts(), force: false, budgetMs: Timing.pageBudgetMs, requestMs: Timing.widgetRequestMs)
        }
        await Widgets.reload()
        return .result()
    }
}

/// Яку адресу показує віджет, коли їх дві (у Scripting це було поле Parameter «2»).
enum AddressChoice: String, AppEnum {
    case first
    case second

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Адреса"
    static let caseDisplayRepresentations: [AddressChoice: DisplayRepresentation] = [
        .first: "Перша",
        .second: "Друга",
    ]
}

struct SelectAddressIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Адреса"
    static let description = IntentDescription("Яку адресу показує віджет, коли в застосунку їх дві.")

    @Parameter(title: "Адреса", default: .first)
    var address: AddressChoice

    init() {}
}
