// Live Activity під час тривоги: живий таймер від її початку на екрані блокування й у Dynamic Island.
// Тут лише рішення (почати, оновити, прибрати чи лишити як є), тож його видно в тестах; саму Live Activity
// ставить застосунок (App/LiveAlerts.swift), а малює розширення віджетів (Widget/AlertLiveActivity.swift).
//
// Обмеження iOS: без push-сервера Live Activity починається лише тоді, коли застосунок відкрито. Оновлюється
// й зникає вона, коли застосунок відкривають, торкаються «↻» на ній самій або iOS дає фонове оновлення.
// Тому стан має строк свіжості: після нього iOS показує її як застарілу, а напис просить оновити.
import Foundation

/// Що показати в Live Activity. Зберігається в iOS, тож лише прості поля.
public struct AlertActivityState: Codable, Hashable, Sendable {
    public var kind: String // "alert" чи "threat"
    public var title: String // «Повітряна тривога», «Попередня загроза»
    public var place: String // обране місце, коротко
    public var scope: String // де оголошено, якщо не там само: «уся область», район
    public var since: Millis // початок тривоги
    public var threat: String // що летить: «БпЛА, балістика», або порожньо
    public var checkedAt: Millis // коли alerts.in.ua востаннє підтвердив стан

    public init(kind: String, title: String, place: String, scope: String, since: Millis, threat: String, checkedAt: Millis) {
        self.kind = kind
        self.title = title
        self.place = place
        self.scope = scope
        self.since = since
        self.threat = threat
        self.checkedAt = checkedAt
    }
}

public enum ActivityAction: Equatable, Sendable {
    case start(AlertActivityState)
    case update(AlertActivityState)
    case end
    case keep
}

extension AlertLogic {
    /// Стан для Live Activity: лише тривога чи загроза в обраному місці з відомим початком, коротша за добу
    /// (окуповані території мають тривоги роками, там живий таймер не має сенсу). Інакше nil.
    public static func activityState(_ s: AlertStatus) -> AlertActivityState? {
        guard active(s), s.timer, s.since > 0 else { return nil }
        return AlertActivityState(
            kind: s.kind.rawValue, title: s.title, place: s.place, scope: s.where_, since: s.since,
            threat: s.threat ?? "", checkedAt: s.fetchedAt
        )
    }

    /// Що зробити з Live Activity за свіжим станом тривоги. running: та, що вже показується (nil — немає).
    /// Немає даних — нічого не міняємо: відсутність інтернету не означає, що тривогу скасовано.
    public static func activityAction(running: AlertActivityState?, status: AlertStatus?, settings: AlertSettings) -> ActivityAction {
        guard settings.isOn, settings.activityOn else { return running == nil ? .keep : .end }
        guard let s = status else { return .keep }
        if let state = activityState(s) {
            guard let running = running else { return .start(state) }
            return running == state ? .keep : .update(state)
        }
        if s.kind == .nodata { return .keep }
        return running == nil ? .keep : .end
    }

    /// Після цього iOS показує Live Activity як застарілу (дані тривог старші за staleMinutes).
    public static func activityStaleDate(_ state: AlertActivityState) -> Date {
        Date(ms: state.checkedAt + AlertConfig.staleMinutes * 60000)
    }

    /// Коротко для Dynamic Island: «Тривога», «Загроза».
    public static func activityShortTitle(_ state: AlertActivityState) -> String {
        if state.kind == AlertKind.threat.rawValue { return state.title == "Попередня загроза" ? "Загроза" : state.title }
        return state.title == "Повітряна тривога" ? "Тривога" : state.title
    }

    /// Другий рядок: місце й що летить, або де оголошено.
    public static func activityLine(_ state: AlertActivityState) -> String {
        let place = compactPlace(state.place)
        let extra = !state.threat.isEmpty ? state.threat : state.scope
        return [place, extra].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// «перевірено 10:42».
    public static func activityChecked(_ state: AlertActivityState) -> String {
        state.checkedAt > 0 ? "перевірено \(Logic.hm(Logic.kyivParts(ms: state.checkedAt).min))" : ""
    }
}
