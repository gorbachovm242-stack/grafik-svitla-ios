// Вкладка «Віджет»: вигляд і фон, справжні віджети з поточними даними, що означають кнопки й значки,
// як додати віджет на робочий екран і екран блокування, про застосунок.
import SwiftUI
import WidgetKit
import SvitloCore

enum WidgetTexts {
    static let styleHint = "«Як система» вдень світлий, а в темній темі iPhone нічний. У прозорому й тонованому режимах робочого екрана iOS фарбує віджет сама."
    static let about = "Неофіційний застосунок: не повʼязаний з обленерго, ДТЕК, Укренерго чи державними органами. Важливе перевіряйте на сайті свого обленерго. Даних про вас застосунок не збирає."
    static let privacy = "https://github.com/gorbachovm242-stack/grafik-svitla/blob/main/PRIVACY.md"
    static let homeSteps = [
        "Утримуйте порожнє місце на робочому екрані → «Редагувати» → «Додати віджет».",
        "Знайдіть «Графік світла», оберіть розмір і додайте.",
        "Друга адреса: утримуйте віджет → «Редагувати віджет» → Адреса: «Друга».",
    ]
    static let lockSteps = [
        "Утримуйте екран блокування → «Налаштувати» → «Екран блокування».",
        "Торкніться поля віджетів і оберіть «Графік світла».",
    ]
    static let reading: [(String, String)] = [
        ("Будинок і плитки", "кожне вікно — година, день читається зверху вниз; жовті горять, темні без світла, рамка — зараз"),
        ("Гірлянда", "24 лампочки: верхній дріт 0–12, нижній 12–24"),
        ("Батарея", "зі світлом розряджається до відключення, без світла заряджається до ввімкнення"),
        ("Кільце", "24 години по колу, північ угорі, крапка — зараз"),
    ]
}

struct Steps: View {
    let steps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.body.weight(.bold)).foregroundColor(Palette.brand).frame(width: 16, alignment: .leading)
                    Text(step)
                }
            }
        }
    }
}

struct WidgetTab: View {
    @EnvironmentObject var model: AppModel

    var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                if let cfg = model.cfg {
                    Section {
                        Picker("Робочий екран", selection: Binding(
                            get: { Logic.lookOf(cfg.look, Logic.defaultLook) },
                            set: { v in Task { await model.update { $0.look = v } } }
                        )) {
                            ForEach(Logic.looks, id: \.id) { l in Text(l.name).tag(l.id) }
                        }
                        Picker("Екран блокування", selection: Binding(
                            get: { Logic.lockLookOf(cfg.lockLook) },
                            set: { v in Task { await model.update { $0.lockLook = v } } }
                        )) {
                            ForEach(Logic.lockLooks, id: \.id) { l in Text(l.name).tag(l.id) }
                        }
                        Picker("Фон", selection: Binding(
                            get: { Theme.styleOf(cfg.style) },
                            set: { v in Task { await model.update { $0.style = v } } }
                        )) {
                            ForEach(Theme.styleIds, id: \.self) { id in Text(Theme.styleNames[id] ?? id).tag(id) }
                        }
                    } header: {
                        Text("Вигляд")
                    } footer: {
                        Text(WidgetTexts.styleHint)
                    }
                    Section("Подивитися віджет") {
                        NavigationLink {
                            WidgetPreviews()
                        } label: {
                            Label("Усі розміри з вашими даними", systemImage: "rectangle.on.rectangle")
                        }
                    }
                }
                Section("Кнопки у віджеті") {
                    Label("«↻» — оновити все одразу", systemImage: "arrow.clockwise")
                    Label("Значок світла — сторінка світла", systemImage: "bolt.fill")
                    Label("Значок тривоги — тривога докладно", systemImage: "light.beacon.max.fill")
                    Label("Кружечки внизу — яка сторінка відкрита", systemImage: "ellipsis")
                    Label("Дотик до віджета — відкрити цю сторінку тут", systemImage: "hand.tap")
                }
                Section {
                    let t = Theme.light()
                    legendRow(t.icons.alert, .alert, "тривога у вашій громаді")
                    legendRow(t.icons.threat, .threat, "попередня загроза")
                    legendRow(t.icons.nearby, .nearby, "тривога поруч, у вас тихо")
                    legendRow(t.icons.quiet, .quiet, "тихо")
                    legendRow(t.icons.stale, .nodata, "немає свіжих даних")
                } header: {
                    Text("Значок тривоги")
                } footer: {
                    Text("Стовпчик значків зʼявляється, коли на вкладці «Тривога» ввімкнено «Показувати у віджеті».")
                }
                Section("Як додати на робочий екран") { Steps(steps: WidgetTexts.homeSteps) }
                Section("Як додати на екран блокування") { Steps(steps: WidgetTexts.lockSteps) }
                Section("Як читати малюнок") {
                    ForEach(Array(WidgetTexts.reading.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0).font(.headline)
                            Text(item.1).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if model.official, let url = URL(string: URLs.zoe) { Link("Сайт Запоріжжяобленерго", destination: url) }
                    if let url = URL(string: WidgetTexts.privacy) { Link("Політика конфіденційності", destination: url) }
                } header: {
                    Text("Про застосунок · версія \(version)")
                } footer: {
                    Text(WidgetTexts.about)
                }
            }
            .navigationTitle("Віджет")
        }
    }

    func legendRow(_ tok: IconTok, _ kind: AlertKind, _ text: String) -> some View {
        HStack(spacing: 12) {
            StatusIcon(icon: tok, glyph: Theme.alertGlyph(kind), size: 28)
            Text(text)
        }
    }
}

/// Усі розміри віджета з поточними даними: так видно, як він виглядатиме, ще до того, як його додати.
struct WidgetPreviews: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    // Розміри віджетів на 6,1-дюймовому iPhone.
    static let small = CGSize(width: 158, height: 158)
    static let medium = CGSize(width: 338, height: 158)
    static let large = CGSize(width: 338, height: 354)
    static let rectangular = CGSize(width: 160, height: 72)
    static let circular = CGSize(width: 72, height: 72)

    func preview(_ family: WidgetFamily, _ size: CGSize, page: String = AlertLogic.light) -> some View {
        let m = WidgetModel(
            glance: model.view, now: model.kyivNow, date: model.now, family: family, size: size,
            alert: model.alertStatus, pages: AlertLogic.pagesOf(model.alertSet.isOn), page: page, pageKey: ""
        )
        return WidgetContent(m: m, inApp: true, dark: colorScheme == .dark).frame(width: size.width, height: size.height)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                group("Малий") { preview(.systemSmall, WidgetPreviews.small) }
                group("Середній") { preview(.systemMedium, WidgetPreviews.medium) }
                if model.alertSet.isOn {
                    group("Середній, сторінка тривоги") { preview(.systemMedium, WidgetPreviews.medium, page: AlertLogic.alert) }
                }
                group("Великий") { preview(.systemLarge, WidgetPreviews.large) }
                group("Екран блокування") {
                    HStack(spacing: 16) {
                        preview(.accessoryRectangular, WidgetPreviews.rectangular)
                        preview(.accessoryCircular, WidgetPreviews.circular)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Віджет з вашими даними")
        .navigationBarTitleDisplayMode(.inline)
    }

    func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
