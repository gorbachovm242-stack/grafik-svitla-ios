// Три сповіщення: графік змінився, за 10 хвилин до відключення, за 10 хвилин до ввімкнення.
// Тут лише рішення, що й коли показати (його видно в тестах); ставить сповіщення в iOS застосунок
// чи віджет (Shared/Notifier.swift). Коли адрес дві, сповіщення про обидві, і текст починається з назви адреси.
// Перенесено з scripting/scripts/Графік світла/notifications.ts.
import Foundation

/// Заплановане попередження: id, текст і коли показати.
public struct ScheduledNotice: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fireAt: Date
}

/// Що зробити зі сповіщеннями після оновлення графіка.
public struct NotificationPlan: Equatable, Sendable {
    /// nil — заплановані лишаються як є; інакше всі заплановані замінити цими.
    public var replace: [ScheduledNotice]?
    /// Позначка набору; зберегти (commitPlanned), коли сповіщення поставлено.
    public var signature: String?
    /// Показати одразу: «Графік відключень змінився».
    public var immediate: [Message]
}

struct SavedKnown: Codable { var key: String; var known: Known }
struct SavedSignature: Codable { var signature: String }

extension Store {
    static func queueKey(_ cfg: Config) -> String { "\(cfg.region)|\(cfg.group)" }

    /// Заплановані попередження міняємо лише тоді, коли змінився їхній набір.
    public func planNotifications(_ base: Config, _ scheds: [Sched?], _ now: Now, _ date: Date) -> NotificationPlan {
        let prefs = Logic.notifyPrefs(base)
        let addresses = Logic.addressesOf(base)
        var items: [(planned: Planned, order: Int)] = []
        for (i, cfg) in addresses.enumerated() {
            guard i < scheds.count, let sched = scheds[i] else { continue }
            for p in Logic.plannedNotifications(sched, now, cfg.group, prefs, place: cfg.place) {
                var item = p
                item.id = "\(cfg.slot ?? 0):\(p.id)"
                items.append((item, items.count))
            }
        }
        items.sort { $0.planned.triggerMin != $1.planned.triggerMin ? $0.planned.triggerMin < $1.planned.triggerMin : $0.order < $1.order }
        // Назви адрес теж у позначці: перейменували «Батьки», і тексти запланованих попереджень оновляться.
        let who = addresses.map { "\(Store.queueKey($0)):\($0.place ?? "")" }.joined(separator: "+")
        let signature = "v3|\(who)#\(items.map { $0.planned.id }.joined(separator: "|"))"

        var plan = NotificationPlan(replace: nil, signature: nil, immediate: [])
        if get(Keys.planned, SavedSignature.self)?.signature != signature {
            let start = (date.timeIntervalSince1970 / 60).rounded(.down) * 60
            let nowS = clock() / 1000
            var out: [ScheduledNotice] = []
            for item in items.map({ $0.planned }) {
                let fire = start + Double(item.triggerMin - now.min) * 60
                if (fire - nowS).rounded() < 1 { continue }
                out.append(ScheduledNotice(id: item.id, title: item.title, body: item.body, fireAt: Date(timeIntervalSince1970: fire)))
            }
            plan.replace = out
            plan.signature = signature
        }

        // Графік черги змінився чи зʼявився новий: повідомляємо одразу. Перше завантаження й зміна черги мовчать.
        for (i, cfg) in addresses.enumerated() {
            guard i < scheds.count, let sched = scheds[i] else { continue }
            let key = Keys.slot(Keys.known, cfg.slot)
            let saved = get(key, SavedKnown.self)
            let prev = saved?.key == Store.queueKey(cfg) ? saved?.known : nil
            let next = Logic.knownWindows(prev, sched, now)
            put(key, SavedKnown(key: Store.queueKey(cfg), known: next))
            if Logic.notifyPrefs(cfg).change,
               let message = Logic.changeMessage(Logic.scheduleChanges(prev, next, now), now, cfg.group, place: cfg.place) {
                plan.immediate.append(message)
            }
        }
        return plan
    }

    /// Сповіщення поставлено: запамʼятати набір, щоб наступного разу не переставляти те саме.
    public func commitPlanned(_ signature: String) { put(Keys.planned, SavedSignature(signature: signature)) }

    /// Вимкнули всі три або змінили чергу: памʼять про графік і набір — з нуля (заплановані прибирає Notifier).
    public func resetNotifications() {
        remove(Keys.planned)
        remove(Keys.known)
        remove(Keys.slot(Keys.known, 1))
    }

    /// Друга адреса змінилася чи зникла: памʼять про її графік більше не годиться, а перша лишається.
    public func forgetSecond() {
        remove(Keys.slot(Keys.known, 1))
        remove(Keys.planned)
    }
}
