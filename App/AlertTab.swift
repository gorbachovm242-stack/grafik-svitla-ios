// Вкладка «Тривога»: картка тривоги для обраного місця, вмикач модуля у віджеті, місце (область → район → громада),
// публічний канал моніторингу в Telegram і посилання на офіційний застосунок.
import SwiftUI
import SvitloCore

enum AlertTexts {
    static let off = "Віджет покаже, чи є повітряна тривога у вашій громаді, з якого часу й що летить."
    static let rail = "Праворуч у віджеті зʼявиться стовпчик значків: торкніться значка тривоги, щоб побачити її докладно, і значка світла, щоб повернутися."
    static let about = "Оберіть свою громаду: у великих містах тривогу часто оголошують окремо від області."
    static let activity = "Під час тривоги в обраному місці на екрані блокування й у Dynamic Island — таймер від її початку й що летить. iPhone дозволяє почати її, лише коли застосунок відкрито; оновлюється вона, коли ви відкриваєте застосунок чи торкаєтеся «↻» на ній, а після відбою зникає з наступним оновленням."
    static let channel = "Публічний канал, де пишуть, що летить і куди. Віджет показує його дописи за останню годину, дослівно й з часом. Канали помиляються й запізнюються; закриті групи не підходять."
    static let limits = "Коли оновити віджет, iPhone вирішує сам: зазвичай раз на 15–30 хвилин. «↻» у віджеті оновлює одразу. Сирени віджет не подасть — для цього офіційний застосунок."
    static let source = "Дані: alerts.in.ua через сервер-посередник «Маяка». Телефон отримує всі тривоги й сам обирає ваші: місце нікуди не надсилається."
}

struct AlertTab: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var tokens: Tokens { colorScheme == .dark ? Theme.night() : Theme.light() }

    var body: some View {
        NavigationStack {
            List {
                Section { hero }
                Section {
                    Toggle("Показувати у віджеті", isOn: Binding(get: { model.alertSet.isOn }, set: { model.toggleAlerts($0) }))
                } footer: {
                    Text(AlertTexts.rail)
                }
                if model.alertSet.isOn {
                    placeSection
                    Section {
                        Toggle("Live Activity під час тривоги", isOn: Binding(
                            get: { model.alertSet.activityOn },
                            set: { model.setLiveActivity($0) }
                        ))
                    } footer: {
                        Text(AlertTexts.activity)
                    }
                    channelSection
                }
                Section {
                    if let url = URL(string: AlertConfig.officialApp) { Link("Офіційний застосунок «Повітряна тривога»", destination: url) }
                    if let url = URL(string: AlertConfig.source) { Link("Мапа тривог alerts.in.ua", destination: url) }
                } header: {
                    Text("Сирена й миттєві сповіщення")
                } footer: {
                    Text("\(AlertTexts.limits)\n\n\(AlertTexts.source)")
                }
            }
            .navigationTitle("Тривога")
            .refreshable { await model.refreshAlerts(model.alertSet, force: true) }
        }
    }

    @ViewBuilder var hero: some View {
        let t = tokens
        if let s = model.alertStatus {
            let page = Theme.alertPage(t, s.kind)
            let others = Array(s.others.dropFirst(s.kind == .nearby ? 1 : 0))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.place.isEmpty ? "Повітряна тривога" : s.place).font(.subheadline.weight(.semibold)).foregroundColor(page.muted.color)
                        Text(model.alertLoading ? "Оновлюю…" : s.title).font(.system(size: 26, weight: .bold)).foregroundColor(page.title.color)
                    }
                    Spacer()
                    StatusIcon(icon: Theme.alertIcon(t, s.kind), glyph: Theme.alertGlyph(s.kind), size: 44)
                }
                Text(s.sub).font(.body).foregroundColor(page.text.color)
                if AlertLogic.active(s) && !s.where_.isEmpty {
                    Text(s.where_ == "уся область" ? "оголошено на всю область" : "оголошено: \(s.where_)")
                        .font(.subheadline).foregroundColor(page.muted.color)
                }
                if s.timer {
                    Text(Date(ms: s.since), style: .timer)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(page.title.color)
                }
                if !s.posts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.channel.map { "Канал «\($0)»" } ?? "Канал").font(.footnote.weight(.semibold)).foregroundColor(page.muted.color)
                        ForEach(Array(s.posts.enumerated()), id: \.offset) { _, post in
                            Text(post).font(.subheadline).foregroundColor(page.text.color)
                        }
                    }
                    .padding(.top, 6)
                }
                if !others.isEmpty {
                    let head = AlertLogic.active(s) || s.kind == .nearby ? "Також тривога" : "В області тривога"
                    let list = others.prefix(3).joined(separator: ", ") + (others.count > 3 ? " і ще \(others.count - 3)" : "")
                    Text("\(head): \(list)").font(.subheadline).foregroundColor(page.muted.color).padding(.top, 4)
                }
                HStack {
                    Text(s.checked.map { "\(s.stale ? "дані за" : "перевірено о") \($0)" } ?? "").font(.footnote).foregroundColor(page.muted.color)
                    Spacer()
                    Button {
                        Task { await model.refreshAlerts(model.alertSet, force: true) }
                    } label: {
                        Label("Оновити", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(page.title.color)
                }
                .padding(.top, 6)
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
            .listRowBackground(LinearGradient(colors: [page.bg0.color, page.bg1.color], startPoint: .top, endPoint: .bottom))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("Повітряна тривога у віджеті").font(.system(size: 22, weight: .bold))
                    Spacer()
                    StatusIcon(icon: t.icons.idle, glyph: Theme.alertGlyph(.setup), size: 40)
                }
                Text(AlertTexts.off).font(.body).foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        }
    }

    var placeSection: some View {
        Section {
            Picker("Область", selection: Binding(get: { model.place?.oblast ?? "" }, set: { model.chooseOblast($0) })) {
                Text("Оберіть").tag("")
                ForEach(model.locations) { l in Text(l.title).tag(l.uid) }
            }
            .pickerStyle(.menu)
            if model.place != nil, let oblast = model.oblast, !oblast.children.isEmpty {
                Picker("Район", selection: Binding(get: { model.place?.raion ?? "" }, set: { model.chooseRaion($0) })) {
                    Text("Уся область").tag("")
                    ForEach(oblast.children) { l in Text(l.title).tag(l.uid) }
                }
                .pickerStyle(.navigationLink)
            }
            if model.place != nil, model.oblast != nil, let raion = model.raion, !raion.children.isEmpty {
                Picker("Громада", selection: Binding(get: { model.place?.hromada ?? "" }, set: { model.chooseHromada($0) })) {
                    Text("Увесь район").tag("")
                    ForEach(raion.children) { l in Text(l.title).tag(l.uid) }
                }
                .pickerStyle(.navigationLink)
            }
        } header: {
            Text("Місце")
        } footer: {
            Text(AlertTexts.about)
        }
    }

    var channelSection: some View {
        Section {
            if let channel = model.alertSet.channel {
                Label(model.alertSet.channelTitle ?? channel, systemImage: "paperplane.fill")
            }
            TextField("Канал", text: $model.channelInput,
                      prompt: Text(model.alertSet.channel != nil ? "Інший канал: t.me/назва або @назва" : "t.me/назва або @назва"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.channelInput.trimmed.isEmpty {
                Button("Підключити канал") { Task { await model.connectChannel() } }
            }
            if let error = model.channelError { Hint(text: error) }
            if model.alertSet.channel != nil {
                Button("Прибрати канал", role: .destructive) { model.removeChannel() }
            }
        } header: {
            Text("Що летить: канал у Telegram")
        } footer: {
            Text(AlertTexts.channel)
        }
    }
}
