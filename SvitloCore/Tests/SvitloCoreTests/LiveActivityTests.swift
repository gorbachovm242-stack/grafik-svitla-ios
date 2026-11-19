// Новий (Swift): коли показувати, оновлювати й прибирати Live Activity тривоги. Усі дані синтетичні.
import XCTest
@testable import SvitloCore

final class LiveActivityTests: XCTestCase {
    let now = parseDate("2026-11-19T10:09:00+02:00")!
    let place = Place(oblast: "12", oblastTitle: "Запорізька область")
    var on: AlertSettings { AlertSettings(enabled: true, place: place) }

    func feed(_ alerts: [AirAlert], fetchedAt: Millis? = nil) -> AlertFeed {
        AlertFeed(ok: true, stale: false, fetchedAt: fetchedAt ?? now, alerts: alerts)
    }

    func oblast(since: Millis, level: String = "red", threats: [String] = ["drones"]) -> AirAlert {
        AirAlert(uid: "12", title: "Запорізька область", kind: "oblast", oblast: "12", level: level, since: since, threats: threats)
    }

    func status(_ alerts: [AirAlert], fetchedAt: Millis? = nil) -> AlertStatus {
        AlertLogic.alertStatus(place, feed(alerts, fetchedAt: fetchedAt), now)
    }

    func started(_ alerts: [AirAlert], fetchedAt: Millis? = nil) throws -> AlertActivityState {
        let action = AlertLogic.activityAction(running: nil, status: status(alerts, fetchedAt: fetchedAt), settings: on)
        guard case .start(let state) = action else {
            XCTFail("очікувався start, а маємо \(action)")
            throw XCTSkip("немає стану")
        }
        return state
    }

    // тривога в обраному місці: почати з часом початку, загрозою й часом перевірки
    func testТривогаПочинаєLiveActivity() throws {
        let state = try started([oblast(since: now - 89 * 60000)])
        XCTAssertEqual(state, AlertActivityState(
            kind: "alert", title: "Повітряна тривога", place: "Запорізька область", scope: "уся область",
            since: now - 89 * 60000, threat: "БпЛА", checkedAt: now
        ))
        XCTAssertEqual(AlertLogic.activityShortTitle(state), "Тривога")
        XCTAssertEqual(AlertLogic.activityLine(state), "Запорізька обл. · БпЛА")
        XCTAssertEqual(AlertLogic.activityChecked(state), "перевірено 10:09")
        XCTAssertEqual(AlertLogic.activityStaleDate(state), Date(ms: now + 30 * 60000))
    }

    // той самий стан — лишити; свіжіша перевірка чи нова загроза — оновити
    func testОновлюєтьсяЛишеКолиЗмінилося() throws {
        let running = try started([oblast(since: now - 89 * 60000)])
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: status([oblast(since: now - 89 * 60000)]), settings: on), .keep)
        let later = status([oblast(since: now - 89 * 60000, threats: ["drones", "ballistic_missiles"])], fetchedAt: now)
        guard case .update(let state) = AlertLogic.activityAction(running: running, status: later, settings: on) else {
            return XCTFail("очікувалось оновлення")
        }
        XCTAssertEqual(state.threat, "БпЛА, балістика")
        let rechecked = status([oblast(since: now - 89 * 60000)], fetchedAt: now - 60000)
        XCTAssertNotEqual(AlertLogic.activityAction(running: running, status: rechecked, settings: on), .keep)
    }

    // відбій — прибрати; у тиші без Live Activity нічого не робимо
    func testВідбійПрибирає() throws {
        let running = try started([oblast(since: now - 89 * 60000)])
        let quiet = status([])
        XCTAssertEqual(quiet.kind, .quiet)
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: quiet, settings: on), .end)
        XCTAssertEqual(AlertLogic.activityAction(running: nil, status: quiet, settings: on), .keep)
        // Тривога в іншому районі області — у вас тихо: теж прибрати.
        let other = AirAlert(uid: "120", title: "Пологівський район", kind: "raion", oblast: "12", raion: "Пологівський район", level: "red", since: now)
        let nearby = AlertLogic.alertStatus(
            Place(oblast: "12", oblastTitle: "Запорізька область", raion: "121", raionTitle: "Запорізький район"), feed([other]), now
        )
        XCTAssertEqual(nearby.kind, .nearby)
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: nearby, settings: on), .end)
    }

    // без інтернету чи без свіжих даних тривогу не скасовуємо
    func testБезДанихЛишається() throws {
        let running = try started([oblast(since: now - 89 * 60000)])
        let nodata = AlertLogic.alertStatus(place, nil, now)
        XCTAssertEqual(nodata.kind, .nodata)
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: nodata, settings: on), .keep)
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: nil, settings: on), .keep)
        let old = status([oblast(since: now - 89 * 60000)], fetchedAt: now - 4 * 3_600_000)
        XCTAssertEqual(old.kind, .nodata)
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: old, settings: on), .keep)
    }

    // вимкнули тривоги у віджеті чи саму Live Activity — прибрати й не починати
    func testВимкненоПрибирає() throws {
        let running = try started([oblast(since: now - 89 * 60000)])
        let active = status([oblast(since: now - 89 * 60000)])
        var off = on
        off.liveActivity = false
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: active, settings: off), .end)
        XCTAssertEqual(AlertLogic.activityAction(running: nil, status: active, settings: off), .keep)
        var disabled = on
        disabled.enabled = false
        XCTAssertEqual(AlertLogic.activityAction(running: running, status: active, settings: disabled), .end)
        XCTAssertTrue(AlertSettings().activityOn, "не задано — увімкнено")
    }

    // попередня загроза — коротко «Загроза»; тривога довша за добу (окуповані території) — без Live Activity
    func testЗагрозаЙДовгаТривога() throws {
        let threat = try started([oblast(since: now - 10 * 60000, level: "yellow", threats: [])])
        XCTAssertEqual(threat.kind, "threat")
        XCTAssertEqual(AlertLogic.activityShortTitle(threat), "Загроза")
        XCTAssertEqual(AlertLogic.activityLine(threat), "Запорізька обл. · уся область")
        let long = status([oblast(since: now - 25 * 3_600_000)])
        XCTAssertEqual(long.kind, .alert)
        XCTAssertNil(AlertLogic.activityState(long))
        XCTAssertEqual(AlertLogic.activityAction(running: nil, status: long, settings: on), .keep)
        XCTAssertEqual(AlertLogic.activityAction(running: threat, status: long, settings: on), .end)
    }
}
