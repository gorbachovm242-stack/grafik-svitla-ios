// Живе в застосунку (не в розширенні): починає, оновлює й прибирає Live Activity тривоги за рішенням ядра
// (AlertLogic.activityAction). Почати iOS дозволяє лише з відкритого застосунку; з фону вийде тільки оновити чи прибрати.
import ActivityKit
import Foundation
import SvitloCore

enum LiveAlerts {
    static var running: Activity<AlertActivityAttributes>? { Activity<AlertActivityAttributes>.activities.first }

    static func content(_ state: AlertActivityState) -> ActivityContent<AlertActivityState> {
        ActivityContent(state: state, staleDate: AlertLogic.activityStaleDate(state), relevanceScore: 100)
    }

    /// Звірити Live Activity зі свіжим станом тривоги. bundle nil — стану немає (модуль вимкнено чи немає даних).
    static func sync(_ bundle: AlertBundle?, settings: AlertSettings) async {
        let current = running
        let action = AlertLogic.activityAction(running: current?.content.state, status: bundle?.status, settings: settings)
        switch action {
        case .start(let state):
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // З фону iOS не дає почати: тоді просто чекаємо, доки відкриють застосунок.
            _ = try? Activity.request(attributes: AlertActivityAttributes(), content: content(state), pushType: nil)
        case .update(let state):
            await current?.update(content(state))
        case .end:
            for activity in Activity<AlertActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        case .keep:
            break
        }
    }
}
