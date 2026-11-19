// Новий (Swift): App Group після сайдлоаду. Профіль підпису складаємо самі: двійкові дані навколо XML-plist.
import XCTest
@testable import SvitloCore

final class AppGroupLookupTests: XCTestCase {
    func profile(_ entitlements: [String: Any]) throws -> Foundation.Data {
        let xml = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "test", "Entitlements": entitlements], format: .xml, options: 0
        )
        var data = Foundation.Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09])
        data.append(xml)
        data.append(Foundation.Data([0xA0, 0x82, 0x00, 0x10, 0xFF]))
        return data
    }

    // AltStore дописує ID команди до назви групи: беремо саме її
    func testПерейменованаГрупаПіслаСайдлоаду() throws {
        let data = try profile(["com.apple.security.application-groups": ["group.ua.maiak.grafik.ABCDE12345"]])
        let groups = AppGroupLookup.groups(fromProfile: data)
        XCTAssertEqual(groups, ["group.ua.maiak.grafik.ABCDE12345"])
        XCTAssertEqual(AppGroupLookup.pick(configured: "group.ua.maiak.grafik", available: groups), "group.ua.maiak.grafik.ABCDE12345")
    }

    // своя збірка (Xcode, платний акаунт): група та сама, що в Info.plist
    func testТаСамаГрупа() throws {
        let data = try profile(["com.apple.security.application-groups": ["group.other", "group.ua.maiak.grafik"]])
        XCTAssertEqual(AppGroupLookup.pick(configured: "group.ua.maiak.grafik", available: AppGroupLookup.groups(fromProfile: data)),
                       "group.ua.maiak.grafik")
    }

    // інша назва (інструмент придумав свою): перша дозволена; без профілю чи без груп — з Info.plist
    func testІншаНазваАбоБезПрофілю() throws {
        let data = try profile(["com.apple.security.application-groups": ["group.sideloadly.xyz"]])
        XCTAssertEqual(AppGroupLookup.pick(configured: "group.ua.maiak.grafik", available: AppGroupLookup.groups(fromProfile: data)),
                       "group.sideloadly.xyz")
        XCTAssertEqual(AppGroupLookup.groups(fromProfile: Foundation.Data("не профіль".utf8)), [])
        XCTAssertEqual(AppGroupLookup.groups(fromProfile: try profile(["get-task-allow": true])), [])
        XCTAssertEqual(AppGroupLookup.pick(configured: "group.ua.maiak.grafik", available: []), "group.ua.maiak.grafik")
    }
}
