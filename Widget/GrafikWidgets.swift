// Розширення з віджетами «Графіка світла»: робочий екран (малий, середній, великий), екран блокування
// і Live Activity тривоги (екран блокування й Dynamic Island).
import WidgetKit
import SwiftUI

@main
struct GrafikWidgets: WidgetBundle {
    var body: some Widget {
        LightWidget()
        AlertLiveActivity()
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
