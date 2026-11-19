// Нове для iPhone: таймлайн віджета (Timeline.swift). У Scripting віджет мав один кадр, тож це не порт, а нові тести.
import XCTest
@testable import SvitloCore

/// Сьогодні без світла 12:30–14:30 і 18:15–20:45, завтра 06:30–09:10: жодна зміна не припадає на початок години.
private func sched() -> Sched {
    Sched(days: [
        "2026-11-06": Day(status: .ok, runs: Logic.runsFromOff([(750, 870), (1095, 1245)])),
        "2026-11-07": Day(status: .ok, runs: Logic.runsFromOff([(390, 550)])),
    ])
}

/// Межі відрізків графіка на спільній осі двох діб у вікні (зараз, зараз + доба].
private func edges(_ s: Sched, _ now: Now) -> [Int] {
    var out = Set<Int>()
    for run in Logic.timeline(s, now.ymd) {
        for edge in [run.s, run.e] where edge > now.min && edge <= now.min + WidgetTimeline.horizonMinutes { out.insert(edge) }
    }
    return out.sorted()
}

/// 10:00:30 — не на межі хвилини.
private let DATE = Date(ms: ms("2026-11-06T10:00:30+02:00"))

final class TimelineTests: XCTestCase {
    // Перший запис — сам момент оновлення
    func testПершийЗаписЦеЗараз() {
        XCTAssertEqual(WidgetTimeline.entryDates(sched(), from: DATE).first, DATE)
        XCTAssertEqual(WidgetTimeline.entryDates(nil, from: DATE).first, DATE)
    }

    // Кожна зміна графіка в межах доби має свій запис, рівно на початку хвилини
    func testКожнаЗмінаГрафікаМаєЗапис() {
        let now = Logic.kyivParts(DATE)
        let s = sched()
        let dates = Set(WidgetTimeline.entryDates(s, from: DATE))
        let changes = edges(s, now)
        XCTAssertEqual(changes, [750, 870, 1095, 1245, 1440 + 390, 1440 + 550])
        for minute in changes {
            let at = WidgetTimeline.dateOf(minute: minute, now: now, date: DATE)
            XCTAssertTrue(dates.contains(at), "немає запису на \(Logic.hm(minute % 1440))")
        }
        // 12:30 — це 12:30:00, а не 12:30:30.
        XCTAssertEqual(WidgetTimeline.dateOf(minute: 750, now: now, date: DATE), Date(ms: ms("2026-11-06T12:30:00+02:00")))
        XCTAssertEqual(WidgetTimeline.dateOf(minute: 1440 + 390, now: now, date: DATE), Date(ms: ms("2026-11-07T06:30:00+02:00")))
    }

    // Кожна година до доби вперед має свій запис (рамка «зараз» у будинку, плитках, гірлянді), північ теж
    func testКожнаГодинаМаєЗапис() {
        let now = Logic.kyivParts(DATE)
        let dates = Set(WidgetTimeline.entryDates(sched(), from: DATE))
        for minute in stride(from: 660, through: now.min + WidgetTimeline.horizonMinutes, by: 60) {
            XCTAssertTrue(dates.contains(WidgetTimeline.dateOf(minute: minute, now: now, date: DATE)), "немає запису на \(minute)")
        }
        XCTAssertTrue(dates.contains(Date(ms: ms("2026-11-07T00:00:00+02:00"))))
        // Без графіка — лише години.
        XCTAssertEqual(WidgetTimeline.entryDates(nil, from: DATE).count, 1 + 24)
    }

    // По порядку, без повторів, не більше maxEntries і не далі ніж на добу
    func testПоПорядкуБезПовторівНеБільшеМаксимуму() {
        let dates = WidgetTimeline.entryDates(sched(), from: DATE)
        XCTAssertLessThanOrEqual(dates.count, WidgetTimeline.maxEntries)
        XCTAssertEqual(dates.count, 1 + 24 + 6) // зараз, 24 години, 6 змін не на початку години
        for i in dates.indices.dropFirst() { XCTAssertLessThan(dates[i - 1], dates[i]) }
        XCTAssertEqual(Set(dates).count, dates.count)
        if let last = dates.last { XCTAssertLessThanOrEqual(last, DATE.addingTimeInterval(Double(WidgetTimeline.horizonMinutes) * 60)) }
    }

    // Графік, що змінюється щочверть години: записів рівно maxEntries, і це найближчі (обрізано лише хвіст)
    func testЧастіЗміниОбрізаютьсяДоНайближчих() throws {
        let quarters = stride(from: 0, to: 1440, by: 30).map { ($0, $0 + 15) }
        let busy = Sched(days: [
            "2026-11-06": Day(status: .ok, runs: Logic.runsFromOff(quarters)),
            "2026-11-07": Day(status: .ok, runs: Logic.runsFromOff(quarters)),
        ])
        let now = Logic.kyivParts(DATE)
        let dates = WidgetTimeline.entryDates(busy, from: DATE)
        XCTAssertEqual(dates.count, WidgetTimeline.maxEntries)
        let last = try XCTUnwrap(dates.last)
        let all = Set(dates)
        for minute in edges(busy, now) {
            let at = WidgetTimeline.dateOf(minute: minute, now: now, date: DATE)
            if at <= last { XCTAssertTrue(all.contains(at), "пропущено \(Logic.hm(minute % 1440))") }
        }
        for i in dates.indices.dropFirst() { XCTAssertLessThan(dates[i - 1], dates[i]) }
    }

    // Додаткові моменти (повернення сторінки, застарілі дані): лише майбутні, у межах доби, без дублів
    func testДодатковіМоменти() {
        let now = Logic.kyivParts(DATE)
        let soon = DATE.addingTimeInterval(5 * 60)
        let hour = WidgetTimeline.dateOf(minute: 660, now: now, date: DATE)
        let past = DATE.addingTimeInterval(-60)
        let far = DATE.addingTimeInterval(25 * 3600)
        let dates = WidgetTimeline.entryDates(nil, from: DATE, extra: [soon, hour, past, far])
        XCTAssertTrue(dates.contains(soon))
        XCTAssertFalse(dates.contains(past))
        XCTAssertFalse(dates.contains(far))
        XCTAssertEqual(dates.filter { $0 == hour }.count, 1)
        XCTAssertEqual(dates.count, 1 + 24 + 1)
    }

    // Запис зміни збігається з моментом таймера (Logic.changeDate)
    func testЗаписЗміниЗбігаєтьсяЗТаймером() {
        let now = Logic.kyivParts(DATE)
        let view = Logic.buildGlance(CFG, LightData(sched: sched(), status: .ok), now, nowMs: DATE.ms)
        XCTAssertEqual(view.changeMin, 750)
        let change = Logic.changeDate(view, now, DATE)
        XCTAssertEqual(change, WidgetTimeline.dateOf(minute: 750, now: now, date: DATE))
        XCTAssertTrue(WidgetTimeline.entryDates(sched(), from: DATE).contains(change))
    }

    // Коли дані стануть застарілими («Дані від 10:00»): саме тоді, а не раніше
    func testStaleDateКолиДаніСтаютьСтарими() throws {
        XCTAssertNil(WidgetTimeline.staleDate(nil))
        var s = sched()
        XCTAssertNil(WidgetTimeline.staleDate(s))
        s.fetchedAt = 0
        XCTAssertNil(WidgetTimeline.staleDate(s))
        let fetched = ms("2026-11-06T10:00:00+02:00")
        s.fetchedAt = fetched
        let stale = try XCTUnwrap(WidgetTimeline.staleDate(s))
        XCTAssertEqual(stale, Date(ms: fetched + 180 * MIN + 1000))
        let data = LightData(sched: s, status: .ok)
        XCTAssertEqual(Logic.buildGlance(CFG, data, Logic.kyivParts(stale), nowMs: stale.ms).notice, "Дані від 10:00")
        let before = stale.addingTimeInterval(-2)
        XCTAssertNil(Logic.buildGlance(CFG, data, Logic.kyivParts(before), nowMs: before.ms).notice)
    }
}
