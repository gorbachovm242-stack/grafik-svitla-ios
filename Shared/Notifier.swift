// Ставить у iOS те, що вирішило ядро (Store.planNotifications): заплановані попередження за 10 хвилин
// і «графік змінився» одразу. Працює і в застосунку, і у віджеті (iOS дозволяє розширенню ставити сповіщення).
import Foundation
import UserNotifications
import SvitloCore

enum Notifier {
    static let thread = "grafik-svitla"

    /// Попросити дозвіл (застосунок, щойно обрано чергу).
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func content(_ title: String, _ body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        // Проходить крізь «Зосередження», якщо користувач дозволив «Чутливі до часу».
        content.interruptionLevel = .timeSensitive
        return content
    }

    static func apply(_ plan: NotificationPlan, store: Store) async {
        let center = UNUserNotificationCenter.current()
        if let replace = plan.replace {
            center.removeAllPendingNotificationRequests()
            for notice in replace {
                let interval = notice.fireAt.timeIntervalSinceNow
                if interval < 1 { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: notice.id, content: content(notice.title, notice.body), trigger: trigger))
            }
            if let signature = plan.signature { store.commitPlanned(signature) }
        }
        for message in plan.immediate {
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content(message.title, message.body), trigger: nil))
        }
    }

    /// Сповіщення необовʼязкові: їхня помилка чи зависання не повинні лишити віджет порожнім.
    static func update(_ base: Config, _ scheds: [Sched?], store: Store, timeoutMs: Double) async {
        let date = Date()
        let plan = store.planNotifications(base, scheds, Logic.kyivParts(date), date)
        _ = await withFallback(after: timeoutMs, { false }) {
            await apply(plan, store: store)
            return true
        }
    }

    /// Вимкнули всі три або змінили чергу: старі заплановані прибираємо одразу.
    static func reset(store: Store) {
        store.resetNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
