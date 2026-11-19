// Live Activity тривоги: екран блокування й Dynamic Island. Дотик відкриває вкладку «Тривога».
import ActivityKit
import WidgetKit
import SwiftUI
import SvitloCore

struct AlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlertActivityAttributes.self) { context in
            AlertActivityLockView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(AlertActivityLook.page(context.state).bg0.color)
                .activitySystemActionForegroundColor(AlertActivityLook.page(context.state).title.color)
                .widgetURL(URL(string: "\(Shared.deepLinkScheme)://alert"))
        } dynamicIsland: { context in
            let state = context.state
            let p = AlertActivityLook.page(state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusIcon(icon: AlertActivityLook.icon(state), glyph: AlertActivityLook.glyph(state), size: 34)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(state.title)
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(p.title.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(AlertLogic.activityLine(state))
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Date(ms: state.since), style: .timer)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(p.title.color)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.isStale ? "Дані застарілі — оновіть" : AlertLogic.activityChecked(state))
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Button(intent: AlertActivityRefreshIntent()) {
                            Label("Оновити", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold, design: .default))
                        }
                        .tint(p.title.color)
                    }
                }
            } compactLeading: {
                Image(systemName: AlertActivityLook.glyph(state))
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(AlertActivityLook.icon(state).fill.color)
            } compactTrailing: {
                Text(Date(ms: state.since), style: .timer)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(p.title.color)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 56, alignment: .trailing)
            } minimal: {
                Image(systemName: AlertActivityLook.glyph(state))
                    .font(.system(size: 13, weight: .bold, design: .default))
                    .foregroundColor(AlertActivityLook.icon(state).fill.color)
            }
            .widgetURL(URL(string: "\(Shared.deepLinkScheme)://alert"))
            .keylineTint(AlertActivityLook.icon(state).fill.color)
        }
    }
}
