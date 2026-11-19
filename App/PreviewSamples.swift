// Зразки віджета на синтетичних даних: усі розміри, вигляди й стани. Їх малюють тести на симуляторі
// (AppTests), щоб без Mac і без iPhone побачити, як виглядає кожна розкладка.
import SwiftUI
import WidgetKit
import SvitloCore

enum PreviewSamples {
    struct Sample {
        let name: String
        let size: CGSize
        let view: AnyView
    }

    static let small = CGSize(width: 158, height: 158)
    static let medium = CGSize(width: 338, height: 158)
    static let large = CGSize(width: 338, height: 354)
    static let rectangular = CGSize(width: 160, height: 72)
    static let circular = CGSize(width: 72, height: 72)

    /// 19.11.2026, 10:09 за Києвом, черга 3.2: без світла 06–10, світло до 14:00, потім відключення 14–18, вечір зі світлом.
    static var date: Date { Date(ms: parseDate("2026-11-19T10:09:00+02:00") ?? 0) }

    static func sched(_ date: Date) -> Sched {
        let now = Logic.kyivParts(date)
        let today = [
            Run(s: 0, e: 360, st: .on), Run(s: 360, e: 600, st: .off), Run(s: 600, e: 840, st: .on),
            Run(s: 840, e: 1080, st: .off), Run(s: 1080, e: 1260, st: .maybe), Run(s: 1260, e: 1440, st: .on),
        ]
        let tomorrow = [Run(s: 0, e: 480, st: .on), Run(s: 480, e: 660, st: .off), Run(s: 660, e: 1440, st: .on)]
        return Sched(
            days: [now.ymd: Day(status: .ok, runs: today), Logic.addDays(now.ymd, 1): Day(status: .ok, runs: tomorrow)],
            emergency: false, fetchedAt: date.ms
        )
    }

    static func alert(_ date: Date) -> AlertStatus {
        let feed = AlertFeed(ok: true, stale: false, fetchedAt: date.ms, alerts: [
            AirAlert(uid: "12", title: "Запорізька область", kind: "oblast", oblast: "12", level: "red",
                     since: date.ms - 89 * 60000, threats: ["drones"]),
        ])
        let place = Place(oblast: "12", oblastTitle: "Запорізька область")
        let posts = [ChannelPost(at: date.ms - 4 * 60000, text: "Група БпЛА курсом на місто з півдня")]
        return AlertLogic.withPosts(AlertLogic.alertStatus(place, feed, date.ms), posts, "Моніторинг", date.ms)
    }

    static func model(_ cfg: Config, _ data: LightData, _ family: WidgetFamily, _ size: CGSize, alert: AlertStatus? = nil,
                      page: String = AlertLogic.light) -> WidgetModel {
        let now = Logic.kyivParts(date)
        return WidgetModel(
            glance: Logic.buildGlance(cfg, data, now, nowMs: date.ms), now: now, date: date, family: family, size: size,
            alert: alert, pages: AlertLogic.pagesOf(alert != nil), page: page, pageKey: ""
        )
    }

    static func all() -> [Sample] {
        var out: [Sample] = []
        let data = LightData(sched: sched(date), status: .ok)
        func add(_ name: String, _ m: WidgetModel, dark: Bool = false) {
            let view = WidgetContent(m: m, inApp: true, dark: dark)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: m.size.width, height: m.size.height)
            out.append(Sample(name: name, size: m.size, view: AnyView(view)))
        }
        let families: [(WidgetFamily, CGSize)] = [(.systemSmall, small), (.systemMedium, medium), (.systemLarge, large)]
        for look in Logic.looks.map({ $0.id }) {
            let cfg = Config(region: "zaporizhzhia", group: "3.2", look: look)
            for (family, size) in families {
                add("\(family.key)-\(look)", model(cfg, data, family, size))
            }
        }
        // Нічний фон, тривога зі стовпчиком значків, сторінка тривоги, без даних.
        let night = Config(region: "zaporizhzhia", group: "3.2", style: "night")
        for (family, size) in families {
            add("\(family.key)-night", model(night, data, family, size), dark: true)
            add("\(family.key)-rail", model(night, data, family, size, alert: alert(date)), dark: true)
            add("\(family.key)-alert-page", model(Config(region: "zaporizhzhia", group: "3.2"), data, family, size,
                                                  alert: alert(date), page: AlertLogic.alert))
            add("\(family.key)-nodata", model(Config(region: "zaporizhzhia", group: "3.2"), LightData(sched: nil, status: .fail), family, size))
        }
        for look in Logic.lockLooks.map({ $0.id }) {
            let cfg = Config(region: "zaporizhzhia", group: "3.2", lockLook: look)
            add("lock-rectangular-\(look)", model(cfg, data, .accessoryRectangular, rectangular))
            add("lock-circular-\(look)", model(cfg, data, .accessoryCircular, circular))
        }
        return out
    }
}
