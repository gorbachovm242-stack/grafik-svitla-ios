// Вкладка «Світло»: головна картка стану з таймером і смугою доби, години відключень, черга, датчик СвітлоБота,
// три сповіщення й друга адреса.
import SwiftUI
import SvitloCore

enum Texts {
    static let queueHint = "Точніше покаже датчик саме вашого будинку: знайдіть його за вулицею або вставте посилання на канал."
    static let noSensors = "У вашій черзі поки немає датчиків СвітлоБота. Знайдіть датчик свого будинку чи сусідів за вулицею, вставте посилання на канал або поставте свій."
    static let notFound = "Нічого не знайдено. Новий датчик зʼявляється в пошуку лише після перевірки СвітлоБотом (кілька днів), а свій канал можна підключити одразу: вставте посилання t.me/svitlobot_…"
    static let secondAbout = "Батьки, робота чи дача: віджет і попередження ще для однієї черги."
    static let secondWidget = "Щоб віджет показував другу адресу: утримуйте віджет → «Редагувати віджет» → Адреса: «Друга»."
    static let notifyHint = "Попередження приходять про обидві адреси, з назвою на початку. Щоб вони проходили крізь «Зосередження», дозвольте «Чутливі до часу» в Параметрах iPhone → Сповіщення → Графік світла."
    static let marks: [FactStatus: String] = [.on: "🟢", .off: "🔴", .unknown: "⚪️", .missing: "⚪️"]
}

/// Кольори головної картки за станом, як у застосунку для Android: сонячна зі світлом, темно-синя без нього.
struct HeroPaint {
    let bg0: Color
    let bg1: Color
    let ink: Color
    let soft: Color
    let dark: Bool

    static func of(_ kind: LightKind?) -> HeroPaint {
        func d(_ l: String, _ n: String) -> Color { Palette.dynamic(RGBA(hex: l), RGBA(hex: n)) }
        switch kind {
        case .on?:
            return HeroPaint(bg0: d("#FFF8E7", "#3A3322"), bg1: d("#FFE4A6", "#2A2415"), ink: d("#1C1F33", "#FFF4DA"), soft: d("#50556F", "#D9C9A0"), dark: false)
        case .off?:
            return HeroPaint(bg0: RGBA(hex: "#3E4378").color, bg1: RGBA(hex: "#262A55").color, ink: .white, soft: RGBA(hex: "#CDD0F0").color, dark: true)
        case .maybe?, .check?:
            return HeroPaint(bg0: d("#FFF7EB", "#3A2A1A"), bg1: d("#FFE5C6", "#2A1E12"), ink: d("#1C1F33", "#FFEFE0"), soft: d("#50556F", "#D9BFA6"), dark: false)
        default:
            return HeroPaint(bg0: d("#FFFFFF", "#232741"), bg1: d("#F1F2F8", "#14172A"), ink: d("#1C1F33", "#F3F4FF"), soft: d("#50556F", "#B5B9D6"), dark: false)
        }
    }
}

/// Смуга доби: 48 пів годин однакової ширини, поточна обведена; під нею години.
struct DayStrip: View {
    let runs: [Run]
    let nowMin: Int?
    let paint: HeroPaint

    func color(_ st: Status) -> Color {
        switch st {
        case .on: return RGBA(hex: "#FFC83F").color
        case .off: return paint.dark ? RGBA(hex: "#8A90CC").color : Palette.dynamic(RGBA(hex: "#3E4470"), RGBA(hex: "#8A90CC"))
        case .maybe: return RGBA(hex: "#E4CF98").color
        case .unknown: return paint.dark ? RGBA(hex: "#4A4F86").color : Palette.dynamic(RGBA(hex: "#E2E4EE"), RGBA(hex: "#4A4F86"))
        }
    }

    func state(_ m: Int) -> Status { runs.first { $0.s <= m && m < $0.e }?.st ?? .unknown }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 1.5) {
                ForEach(0..<48, id: \.self) { i in
                    ZStack {
                        RoundedRectangle(cornerRadius: 2.5).fill(color(state(i * 30 + 15)))
                        if let now = nowMin, now >= i * 30, now < i * 30 + 30 {
                            RoundedRectangle(cornerRadius: 2.5).strokeBorder(paint.ink, lineWidth: 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
                }
            }
            HStack(spacing: 0) {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { h in
                    Text(h).font(.system(size: 11)).foregroundColor(paint.soft)
                    if h != "24" { Spacer() }
                }
            }
        }
    }
}

struct Hint: View {
    let text: String
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary) }
}

func daysText(_ view: Glance, today: Bool) -> String {
    if today { return view.todayWindows.isEmpty ? "без відключень" : view.todayWindows.map(Logic.windowText).joined(separator: ", ") }
    guard view.tomorrowRuns != nil else { return "графіка ще немає" }
    let list = (view.tomorrowWindows ?? []).map(Logic.windowText).joined(separator: ", ")
    return list.isEmpty ? "без відключень" : list
}

struct LightTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let s = model.alertStatus, AlertLogic.active(s) { banner(s) }
                Section { hero }
                if model.cfg != nil { outages }
                queue
                if let cfg = model.cfg {
                    sensor(cfg)
                    notifications
                    secondAddress(cfg)
                }
            }
            .navigationTitle("Світло")
            .refreshable { await model.refresh(model.cfg, force: true) }
        }
    }

    // MARK: Головна картка

    var hero: some View {
        let view = model.view
        let cfg = model.cfg
        let paint = HeroPaint.of(cfg != nil ? view.kind : nil)
        let label = cfg.map { "\(model.second != nil ? "\($0.name ?? firstName) · " : "")черга \($0.group)" } ?? "Почніть тут"
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundColor(paint.soft)
            Text(cfg != nil ? (model.loading ? "Оновлюю…" : view.title) : "Оберіть область і чергу")
                .font(.system(size: 26, weight: .bold)).foregroundColor(paint.ink)
            Text(cfg != nil ? (view.notice.map { "\(view.sub). \($0)" } ?? view.sub) : "Нижче, у розділі «Моя черга». Потім додайте віджет на екран.")
                .font(.body).foregroundColor(paint.ink)
            if cfg != nil && Logic.hasTimer(view, model.kyivNow) {
                let end = max(Logic.changeDate(view, model.kyivNow, model.now), model.now)
                Text(timerInterval: model.now...end, countsDown: true)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(paint.ink)
            }
            if cfg != nil && !view.todayRuns.isEmpty {
                DayStrip(runs: view.todayRuns, nowMin: view.nowMin, paint: paint).padding(.top, 8)
            }
            if cfg != nil {
                HStack {
                    Text(view.checked.map { "перевірено о \(Logic.hm($0))" } ?? "").font(.footnote).foregroundColor(paint.soft)
                    Spacer()
                    Button {
                        Task { await model.refresh(model.cfg, force: true) }
                    } label: {
                        Label("Оновити", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(paint.ink)
                }
                .padding(.top, 6)
            }
        }
        .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .listRowBackground(LinearGradient(colors: [paint.bg0, paint.bg1], startPoint: .top, endPoint: .bottom))
    }

    /// Тривога в обраному місці: червона смуга над світлом, дотик веде на вкладку «Тривога».
    func banner(_ s: AlertStatus) -> some View {
        let tok = Theme.alertIcon(Theme.light(), s.kind)
        return Section {
            Button {
                model.tab = 1
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: Theme.alertGlyph(s.kind)).font(.system(size: 18, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AlertLogic.alertShortTitle(s) + (s.subShort.map { " \($0)" } ?? "")).font(.headline)
                        Text(s.place).font(.footnote).opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(tok.glyph.color)
            }
            .buttonStyle(.plain)
            .listRowBackground(tok.fill.color)
        }
    }

    // MARK: Розділи

    var outages: some View {
        let view = model.view
        return Section("Відключення") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Сьогодні").font(.footnote).foregroundStyle(.secondary)
                Text(daysText(view, today: true))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Завтра").font(.footnote).foregroundStyle(.secondary)
                Text(daysText(view, today: false))
            }
        }
    }

    var queue: some View {
        Section {
            Picker("Область", selection: Binding(get: { model.region }, set: { model.setRegion($0) })) {
                Text("Оберіть").tag("")
                ForEach(regions, id: \.id) { r in Text(r.name).tag(r.id) }
            }
            .pickerStyle(.menu)
            if !model.region.isEmpty {
                if model.groups.isEmpty {
                    Hint(text: model.groupsError ?? "Завантажую черги…")
                } else {
                    Picker("Черга", selection: Binding(
                        get: { model.cfg?.region == model.region ? (model.cfg?.group ?? "") : "" },
                        set: { value in Task { await model.chooseGroup(value) } }
                    )) {
                        Text("Оберіть").tag("")
                        ForEach(model.groups, id: \.self) { g in Text("Черга \(g)").tag(g) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if model.official, let url = URL(string: URLs.zoeQueue) {
                Link("Не знаю свою чергу", destination: url)
            }
        } header: {
            Text("Моя черга")
        } footer: {
            if model.official { Text("Для Запоріжжя є пошук черги за адресою на сайті обленерго.") }
        }
    }

    func sensor(_ cfg: Config) -> some View {
        let view = model.view
        return Section {
            if let fact = view.fact {
                Label(fact.full + (fact.checked.map { " · \($0)" } ?? ""),
                      systemImage: fact.kind == .on ? "lightbulb.max.fill" : fact.kind == .off ? "lightbulb.slash.fill" : "lightbulb")
            } else {
                Hint(text: cfg.svitlobot != nil || !model.factLoaded ? "Перевіряю датчики…" : Texts.noSensors)
            }
            TextField("Пошук датчика", text: $model.query,
                      prompt: Text(cfg.svitlobot != nil ? "Інший датчик: вулиця чи посилання" : "Вулиця, будинок або посилання на канал"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: model.query) { _ in model.searchIfNeeded() }
            if !model.directNew.isEmpty {
                Button("Підключити канал \(model.directNew)") {
                    let id = model.directNew
                    Task { await model.chooseSensor(Channel(id: id, name: id, status: .unknown, since: nil, users: 0, queue: nil)) }
                }
            }
            let searching = !model.query.trimmed.isEmpty
            if searching, let error = model.channelsError { Hint(text: error) }
            if searching && model.channelsError == nil && model.channels == nil { Hint(text: "Завантажую датчики…") }
            if searching && model.channels != nil && model.found.isEmpty && model.directNew.isEmpty { Hint(text: Texts.notFound) }
            ForEach(model.found, id: \.id) { channel in
                Button("\(Texts.marks[channel.status] ?? "⚪️") \(channel.name)") {
                    Task { await model.chooseSensor(channel) }
                }
            }
            if cfg.svitlobot != nil {
                Button("Прибрати датчик", role: .destructive) { Task { await model.removeSensor() } }
            }
            if let url = URL(string: SvitloBot.howTo) { Link("Як поставити свій датчик", destination: url) }
        } header: {
            Text("Чи є світло насправді")
        } footer: {
            Text(cfg.svitlobot != nil ? "Датчик: \(cfg.svitlobotName ?? cfg.svitlobot ?? "")" : view.fact != nil ? Texts.queueHint : "")
        }
    }

    var notifications: some View {
        let prefs = model.prefs
        return Section {
            Toggle("Графік черги змінився", isOn: Binding(get: { prefs.change }, set: { v in Task { await model.update { $0.notifyChange = v } } }))
            Toggle("За 10 хв до відключення", isOn: Binding(get: { prefs.off }, set: { v in Task { await model.update { $0.notifyOff = v } } }))
            Toggle("За 10 хв до ввімкнення", isOn: Binding(get: { prefs.on }, set: { v in Task { await model.update { $0.notifyOn = v } } }))
        } header: {
            Text("Сповіщення")
        } footer: {
            Text(Texts.notifyHint)
        }
    }

    func secondAddress(_ cfg: Config) -> some View {
        let second = model.second
        let view2 = model.view2
        return Section {
            if let second = second {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.loading ? "Оновлюю…" : "\(second.place ?? secondName): \(view2.title)").font(.headline)
                    Text("Сьогодні: \(daysText(view2, today: true))").font(.subheadline).foregroundStyle(.secondary)
                    Text("Завтра: \(daysText(view2, today: false))").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            TextField("Назва", text: Binding(get: { model.name2 }, set: { model.renameSecond($0) }), prompt: Text("Наприклад, Батьки"))
            Picker("Область", selection: Binding(get: { model.region2 }, set: { model.setRegion2($0) })) {
                Text("Оберіть").tag("")
                ForEach(regions, id: \.id) { r in Text(r.name).tag(r.id) }
            }
            .pickerStyle(.menu)
            if !model.region2.isEmpty {
                if model.groups2.isEmpty {
                    Hint(text: model.groups2Error ?? "Завантажую черги…")
                } else {
                    Picker("Черга", selection: Binding(
                        get: { cfg.second?.region == model.region2 ? (cfg.second?.group ?? "") : "" },
                        set: { value in Task { await model.chooseSecondGroup(value) } }
                    )) {
                        Text("Оберіть").tag("")
                        ForEach(model.groups2, id: \.self) { g in Text("Черга \(g)").tag(g) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if second != nil {
                TextField("Назва першої адреси", text: Binding(get: { cfg.name ?? "" }, set: { model.renameFirst($0) }), prompt: Text(firstName))
                Button("Прибрати другу адресу", role: .destructive) { Task { await model.removeSecond() } }
            }
        } header: {
            Text("Друга адреса")
        } footer: {
            Text(second != nil ? Texts.secondWidget : Texts.secondAbout)
        }
    }
}
