// Справжня App Group (спільне сховище застосунку й віджета) після переписування підпису.
// Інструменти сайдлоаду (AltStore, SideStore) підписують застосунок безкоштовним Apple ID і перейменовують групу,
// бо назви груп унікальні на весь світ: group.ua.maiak.grafik стає group.ua.maiak.grafik.ABCDE12345. Якщо брати
// назву лише з Info.plist, застосунок і віджет писали б у різні місця, і віджет не бачив би налаштувань.
// Тому дивимось у вбудований профіль підпису (embedded.mobileprovision): там список груп, які справді дозволено.
// У збірках з App Store і TestFlight профілю немає — тоді назва з Info.plist.
import Foundation

public enum AppGroupLookup {
    /// Групи з профілю підпису. Профіль — підписані дані, усередині яких відкритим текстом лежить XML-plist.
    public static func groups(fromProfile data: Foundation.Data) -> [String] {
        guard let start = data.range(of: Foundation.Data("<?xml".utf8)),
              let end = data.range(of: Foundation.Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return [] }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let root = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups.filter { !$0.isEmpty && !$0.contains("*") }
    }

    /// Яку групу брати: ту, що в Info.plist, якщо її дозволено; інакше перейменовану з неї (з дописаним ID команди);
    /// інакше першу дозволену. Профілю чи груп немає — ту, що в Info.plist.
    public static func pick(configured: String, available: [String]) -> String {
        if available.isEmpty || available.contains(configured) { return configured }
        return available.first { $0.hasPrefix(configured + ".") } ?? available.first { $0.hasPrefix(configured) } ?? available[0]
    }
}
