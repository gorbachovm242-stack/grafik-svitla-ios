// Таймлайн віджета. У Scripting віджет мав лише один кадр і чекав, доки iOS його перемалює (о 23:30 лишалося
// «Світло є»). У WidgetKit можна віддати iOS наперед кілька записів: окремий запис на кожну зміну графіка,
// на кожну годину (рамка «зараз» у будинку, плитках, гірлянді), на північ і на повернення сторінки тривоги.
import Foundation

public enum WidgetTimeline {
    /// Скільки наперед готуємо записи.
    public static let horizonMinutes = 24 * 60
    /// Більше записів iOS не потрібно: решту дасть наступне оновлення.
    public static let maxEntries = 60

    /// Хвилина спільної осі двох діб (0..2880 від півночі сьогодні) як момент часу, від початку поточної хвилини.
    /// Так само рахує Logic.changeDate, тож таймер і запис таймлайну збігаються.
    public static func dateOf(minute: Int, now: Now, date: Date) -> Date {
        let base = (date.timeIntervalSince1970 / 60).rounded(.down) * 60
        return Date(timeIntervalSince1970: base + Double(minute - now.min) * 60)
    }

    /// Моменти, коли віджет має виглядати інакше: зміни стану за графіком, початок кожної години й північ.
    /// Перший запис — «зараз». extra: інші моменти (повернення сторінки, застарілі дані).
    public static func entryDates(_ sched: Sched?, from date: Date, extra: [Date] = []) -> [Date] {
        let now = Logic.kyivParts(date)
        let limit = now.min + horizonMinutes
        var minutes = Set<Int>()
        if let sched = sched {
            for run in Logic.timeline(sched, now.ymd) {
                for edge in [run.s, run.e] where edge > now.min && edge <= limit { minutes.insert(edge) }
            }
        }
        var hour = (now.min / 60 + 1) * 60
        while hour <= limit {
            minutes.insert(hour)
            hour += 60
        }
        var dates = minutes.sorted().map { dateOf(minute: $0, now: now, date: date) }
        let horizonEnd = date.addingTimeInterval(Double(horizonMinutes) * 60)
        dates += extra.filter { $0 > date && $0 <= horizonEnd }
        let unique = Set(dates.map { $0.timeIntervalSince1970 }).sorted().map { Date(timeIntervalSince1970: $0) }
        return [date] + unique.prefix(maxEntries - 1)
    }

    /// Коли знову спитати дані: між змінами раз на 30 хвилин, з датчиком раз на 15, з тривогами ще частіше.
    /// На відміну від Scripting, сама зміна графіка оновлення не потребує: вона вже є в записах таймлайну,
    /// тож денний ліміт оновлень iOS не витрачаємо на кожну зміну.
    public static func reloadDate(_ view: Glance, _ date: Date, alertMinutes: Double? = nil) -> Date {
        var minutes = view.fact != nil ? Timing.factRefreshMinutes : Timing.refreshMinutes
        if let a = alertMinutes { minutes = min(minutes, a) }
        return date.addingTimeInterval(minutes * 60)
    }

    /// Коли графік стане «застарілим» (напис «Дані від 10:42»): окремий запис.
    public static func staleDate(_ sched: Sched?) -> Date? {
        guard let fetched = sched?.fetchedAt, fetched > 0 else { return nil }
        return Date(ms: fetched + Timing.staleMinutes * 60000 + 1000)
    }
}
