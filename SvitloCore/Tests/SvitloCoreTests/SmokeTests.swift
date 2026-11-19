import XCTest
@testable import SvitloCore

final class SmokeTests: XCTestCase {
    func testKyivTimeZoneExists() {
        XCTAssertTrue(["Europe/Kyiv", "Europe/Kiev"].contains(Logic.kyiv.identifier), Logic.kyiv.identifier)
    }

    func testParseDateIso() {
        XCTAssertEqual(parseDate("2026-11-09T04:53:00+00:00"), 1_794_200_000_000 - 1_794_200_000_000 + parseDate("2026-11-09T06:53:00+02:00")!)
        XCTAssertEqual(parseDate("1970-01-01T00:00:00Z"), 0)
        XCTAssertEqual(parseDate("1970-01-01T00:00:01.500Z"), 1500)
        XCTAssertNil(parseDate("вчора"))
    }
}
