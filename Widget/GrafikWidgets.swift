// Розширення з віджетами «Графіка світла»: робочий екран (малий, середній, великий) і екран блокування.
// Live Activity для тривоги — наступним кроком (ActivityKit), тут поки лише віджет.
import WidgetKit
import SwiftUI

@main
struct GrafikWidgets: WidgetBundle {
    var body: some Widget {
        LightWidget()
    }
}

struct LightWidget: Widget {
    static let kind = "GrafikSvitla"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: LightWidget.kind, intent: SelectAddressIntent.self, provider: Provider()) { entry in
            LightWidgetView(entry: entry)
        }
        .configurationDisplayName("Графік світла")
        .description("Коли вимкнуть і ввімкнуть світло у вашій черзі, а з тривогою — і чи є повітряна тривога.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}
