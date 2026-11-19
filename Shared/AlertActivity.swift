// Live Activity тривоги: дані для ActivityKit, вигляд на екрані блокування й кнопка «↻» на ній.
// Файл спільний: застосунок починає й оновлює Live Activity (App/LiveAlerts.swift), розширення її малює
// (Widget/AlertLiveActivity.swift), а тести на симуляторі малюють вигляд у картинку.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import SvitloCore

struct AlertActivityAttributes: ActivityAttributes {
    typealias ContentState = AlertActivityState
}

/// Кольори Live Activity: «Нічна» палітра, бо екран блокування й Dynamic Island темні.
enum AlertActivityLook {
    static func kind(_ state: AlertActivityState) -> AlertKind { AlertKind(rawValue: state.kind) ?? .alert }
    static func page(_ state: AlertActivityState) -> PageTok { Theme.alertPage(Theme.night(), kind(state)) }
    static func icon(_ state: AlertActivityState) -> IconTok { Theme.alertIcon(Theme.night(), kind(state)) }
    static func glyph(_ state: AlertActivityState) -> String { Theme.alertGlyph(kind(state)) }
}

/// «↻» на самій Live Activity: iOS виконує її в процесі застосунку, тож вона може оновити чи прибрати
/// Live Activity (у розширенні віджетів це заборонено).
struct AlertActivityRefreshIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Оновити тривогу"
    static let description = IntentDescription("Свіжий стан тривоги для Live Activity і віджета.")

    init() {}

    func perform() async throws -> some IntentResult {
        let store = Shared.store
        let settings = store.readAlerts()
        let bundle = await store.freshAlerts(settings, force: true, budgetMs: Timing.buttonBudgetMs, requestMs: Timing.widgetRequestMs)
        #if !WIDGET_EXTENSION
        await LiveAlerts.sync(bundle, settings: settings)
        #else
        _ = bundle
        #endif
        await Widgets.reload()
        return .result()
    }
}

/// Live Activity на екрані блокування: знак тривоги, назва, місце й що летить, живий таймер від початку, «↻».
struct AlertActivityLockView: View {
    let state: AlertActivityState
    var stale = false
    var pauseAt: Date? = nil

    var body: some View {
        let p = AlertActivityLook.page(state)
        HStack(alignment: .center, spacing: 12) {
            StatusIcon(icon: AlertActivityLook.icon(state), glyph: AlertActivityLook.glyph(state), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(p.title.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(AlertLogic.activityLine(state))
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(p.text.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(stale ? "Дані можуть бути застарілі — оновіть" : AlertLogic.activityChecked(state))
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(stale ? Theme.night().warn.color : p.muted.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                countUp(Date(ms: state.since), pauseAt: pauseAt)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(p.title.color)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
                Button(intent: AlertActivityRefreshIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(p.muted.color)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
