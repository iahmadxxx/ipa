import SwiftUI

struct MoreView: View {
    @State private var status: ConnectionStatusResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var showTokenEntry = false
    @State private var manualToken = ""
    @State private var rebuildingAnalytics = false
    @State private var rebuildMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    connectionCard
                    archiveSection
                    intelligenceSection
                    appSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .refreshable { await loadStatus() }
        }
        .navigationTitle("المزيد")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStatus() }
        .sheet(isPresented: $showTokenEntry) { tokenSheet }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(FitTheme.accent.opacity(0.14)).frame(width: 58, height: 58)
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(FitTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("مركز تحكم أحمد").font(.title3.bold()).foregroundStyle(.white)
                    Text("الربط، السجل الصحي وإعدادات التطبيق").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "ربط البيانات الصحية", subtitle: "Google Health + Railway")
            GlassCard {
                VStack(spacing: 14) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(connectionColor.opacity(0.15)).frame(width: 46, height: 46)
                            Image(systemName: connectionIcon).foregroundStyle(connectionColor)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connectionTitle).font(.headline).foregroundStyle(.white)
                            Text(status?.message ?? "جاري فحص الاتصال…").font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        if loading { ProgressView().tint(FitTheme.accent) }
                    }

                    if let updated = status?.tokenUpdatedAt {
                        infoLine(icon: "clock.arrow.circlepath", title: "آخر تجديد للتوكن", value: updated)
                    }

                    if let error { ErrorBanner(message: error) }

                    HStack(spacing: 10) {
                        Button { Task { await loadStatus() } } label: {
                            Label("فحص الآن", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain).foregroundStyle(.white)

                        if let urlString = status?.reauthURL, let url = URL(string: urlString) {
                            Link(destination: url) {
                                Label("تجديد الربط", systemImage: "link.badge.plus")
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(FitTheme.gradient, in: RoundedRectangle(cornerRadius: 15))
                                    .foregroundStyle(.black.opacity(0.82)).fontWeight(.bold)
                            }
                        }
                    }

                    Button { showTokenEntry = true } label: {
                        Label("إضافة توكن يدويًا للطوارئ", systemImage: "key.fill")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var archiveSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "السجل الصحي", subtitle: "ارجع لأي يوم سابق وشاهد بياناتك")
            GlassCard(padding: 8) {
                VStack(spacing: 2) {
                    NavigationLink { HealthArchiveView(initialCategory: .summary) } label: { MoreRow(icon: "waveform.path.ecg.rectangle", tint: FitTheme.accent, title: "ملخص الأيام السابقة", subtitle: "كل مؤشرات اليوم في شاشة واحدة") }
                    NavigationLink { HealthArchiveView(initialCategory: .sleep) } label: { MoreRow(icon: "moon.stars.fill", tint: FitTheme.accentPurple, title: "سجل النوم", subtitle: "المدة ومراحل النوم لكل يوم") }
                    NavigationLink { HealthArchiveView(initialCategory: .heart) } label: { MoreRow(icon: "heart.fill", tint: .red, title: "سجل النبض", subtitle: "نبض الراحة والقراءة اللحظية") }
                    NavigationLink { HealthArchiveView(initialCategory: .activity) } label: { MoreRow(icon: "figure.walk", tint: FitTheme.accent, title: "سجل النشاط", subtitle: "الخطوات والسعرات") }
                    NavigationLink { HealthArchiveView(initialCategory: .readiness) } label: { MoreRow(icon: "bolt.heart.fill", tint: FitTheme.warning, title: "سجل الجاهزية", subtitle: "درجة وتفسير جاهزيتك") }
                }
            }
        }
    }

    private var intelligenceSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "الذكاء والتقارير")
            GlassCard(padding: 8) {
                VStack(spacing: 2) {
                    NavigationLink { InsightsView() } label: { MoreRow(icon: "chart.xyaxis.line", tint: FitTheme.accentBlue, title: "كل التحليلات", subtitle: "التقدم، التوازن، الأوزان والتقرير") }
                    NavigationLink { CoachView() } label: { MoreRow(icon: "sparkles", tint: FitTheme.accentPurple, title: "المدرب الذكي", subtitle: "اسأل عن صحتك وتمرينك الحالي") }
                    NavigationLink { ConnectionDiagnosticsView() } label: { MoreRow(icon: "stethoscope", tint: FitTheme.warning, title: "تشخيص الاتصال", subtitle: "Railway، التوكن، السوار والنبض") }

                    Button {
                        Task { await rebuildAnalytics() }
                    } label: {
                        MoreRow(
                            icon: rebuildingAnalytics ? "hourglass" : "arrow.triangle.2.circlepath.circle.fill",
                            tint: FitTheme.warning,
                            title: rebuildingAnalytics ? "جاري إعادة البناء…" : "إعادة بناء التحليلات",
                            subtitle: "ينظف الأوزان المحذوفة ويعيد حساب PR والتقرير",
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(rebuildingAnalytics)

                    if let rebuildMessage {
                        Text(rebuildMessage)
                            .font(.caption)
                            .foregroundStyle(FitTheme.positive)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var appSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "التطبيق")
            GlassCard(padding: 8) {
                VStack(spacing: 2) {
                    MoreRow(icon: "lock.shield.fill", tint: FitTheme.positive, title: "نسخة شخصية", subtitle: "مخصصة لأحمد المري فقط", showsChevron: false)
                    MoreRow(icon: "app.badge.checkmark.fill", tint: FitTheme.accent, title: "الإصدار", subtitle: "FitbitAir 1.0", showsChevron: false)
                    MoreRow(icon: "server.rack", tint: FitTheme.accentBlue, title: "الخادم", subtitle: AppConfig.baseURL.host ?? "Railway", showsChevron: false)
                }
            }
        }
    }

    private func rebuildAnalytics() async {
        rebuildingAnalytics = true
        rebuildMessage = nil
        do {
            let result = try await APIClient.shared.rebuildAnalytics()
            rebuildMessage = "تم تنظيف التحليلات: فحص \(result.setsScanned) جولة وإعادة بناء \(result.prsCreated) رقم شخصي."
        } catch {
            self.error = error.localizedDescription
        }
        rebuildingAnalytics = false
    }

    private func infoLine(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(FitTheme.accent).frame(width: 24)
            Text(title).foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
        }.font(.caption)
    }

    private var connectionColor: Color { status?.connected == true ? FitTheme.positive : (status?.needsReauth == true ? FitTheme.warning : FitTheme.danger) }
    private var connectionIcon: String { status?.connected == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    private var connectionTitle: String { status?.connected == true ? "متصل وجاهز" : (status?.needsReauth == true ? "يحتاج تجديد الربط" : "الاتصال غير متاح") }

    private func loadStatus() async {
        loading = true; error = nil
        do { status = try await APIClient.shared.connectionStatus() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private var tokenSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 18) {
                    Image(systemName: "key.horizontal.fill").font(.system(size: 44)).foregroundStyle(FitTheme.accent)
                    Text("إضافة Refresh Token").font(.title2.bold()).foregroundStyle(.white)
                    Text("استخدم هذا الخيار فقط للطوارئ. الأفضل دائمًا زر تجديد الربط.").font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.55))
                    TextEditor(text: $manualToken)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(height: 150).padding(10)
                        .scrollContentBackground(.hidden)
                        .background(FitTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    Button("حفظ التوكن") {
                        Task {
                            do {
                                status = try await APIClient.shared.saveRefreshToken(manualToken.trimmingCharacters(in: .whitespacesAndNewlines))
                                manualToken = ""; showTokenEntry = false
                            } catch { self.error = error.localizedDescription }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(manualToken.count < 20)
                    Spacer()
                }.padding(20)
            }
            .navigationTitle("إعدادات متقدمة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showTokenEntry = false } } }
        }.preferredColorScheme(.dark)
    }
}

private struct MoreRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(tint.opacity(0.15)).frame(width: 42, height: 42)
                Image(systemName: icon).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if showsChevron { Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.white.opacity(0.28)) }
        }.padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct ConnectionDiagnosticsView: View {
    @State private var result: DiagnosticsResponse?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 14) {
                    if let result {
                        DiagnosticRow(title: "Railway", icon: "server.rack", service: result.railway)
                        DiagnosticRow(title: "Google Health Token", icon: "key.fill", service: result.token)
                        DiagnosticRow(title: "حالة السوار", icon: "watch.analog", service: result.device)
                        DiagnosticRow(title: "النبض", icon: "heart.fill", service: result.heart)

                        GlassCard {
                            Text("آخر فحص: \(result.checkedAt)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    } else if loading {
                        LoadingStateView(text: "جاري فحص جميع الاتصالات…")
                    }

                    if let error {
                        ErrorBanner(message: error)
                    }

                    Button {
                        Task { await load() }
                    } label: {
                        Label(loading ? "جاري الفحص…" : "فحص الآن", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(loading)
                }
                .padding(18)
            }
        }
        .navigationTitle("تشخيص الاتصال")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            result = try await APIClient.shared.diagnostics()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct DiagnosticRow: View {
    let title: String
    let icon: String
    let service: DiagnosticsResponse.Service

    private var tint: Color {
        switch service.status {
        case "ok": return FitTheme.positive
        case "reauth": return FitTheme.warning
        default: return FitTheme.danger
        }
    }

    private var statusText: String {
        switch service.status {
        case "ok": return "يعمل"
        case "reauth": return "يحتاج ربط"
        case "no_data": return "لا توجد بيانات"
        default: return "غير متاح"
        }
    }

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(statusText)
                            .font(.caption.bold())
                            .foregroundStyle(tint)
                    }

                    Text(service.message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    if let bpm = service.bpm {
                        Text("النبض: \(bpm) BPM")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let age = service.ageSeconds {
                        Text("عمر القراءة: \(age) ثانية")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    if let battery = service.batteryLevel {
                        Text("البطارية: \(battery)%")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

enum HealthArchiveCategory: String, CaseIterable, Identifiable {
    case summary, sleep, heart, activity, readiness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "الملخص"
        case .sleep: return "النوم"
        case .heart: return "النبض"
        case .activity: return "النشاط"
        case .readiness: return "الجاهزية"
        }
    }

    var icon: String {
        switch self {
        case .summary: return "square.grid.2x2.fill"
        case .sleep: return "moon.stars.fill"
        case .heart: return "heart.fill"
        case .activity: return "figure.walk"
        case .readiness: return "bolt.heart.fill"
        }
    }
}

private enum HealthArchiveLocalCache {
    private static func key(_ category: HealthArchiveCategory, _ date: String) -> String {
        "fitbitair.archive.\(category.rawValue).\(date)"
    }

    static func load<T: Decodable>(_ type: T.Type, category: HealthArchiveCategory, date: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key(category, date)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, category: HealthArchiveCategory, date: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key(category, date))
    }
}

struct HealthArchiveView: View {
    @State private var category: HealthArchiveCategory
    @State private var selectedDate = Date()

    @State private var summary: HealthSummaryResponse?
    @State private var sleep: HealthSleepResponse?
    @State private var heart: HealthHeartResponse?
    @State private var activity: HealthActivityResponse?
    @State private var readiness: HealthReadinessResponse?

    @State private var loading = true
    @State private var refreshing = false
    @State private var error: String?

    init(initialCategory: HealthArchiveCategory) {
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    categoryPicker
                    dateNavigator

                    if hasVisibleData {
                        content
                    } else if loading {
                        LoadingStateView(text: "أحدث بيانات \(category.title)…")
                    }

                    if refreshing && hasVisibleData {
                        Label("جاري تحديث \(category.title)…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(FitTheme.accent)
                    }

                    if let error {
                        ErrorBanner(message: error)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .refreshable { await load(force: true) }
        }
        .navigationTitle("السجل الصحي")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(useLocalCache: true) }
        .onChange(of: selectedDate) { _, _ in
            clearVisibleState()
            Task { await load(useLocalCache: true) }
        }
        .onChange(of: category) { _, _ in
            Task { await load(useLocalCache: true) }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HealthArchiveCategory.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            category = item
                        }
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(
                                category == item ? FitTheme.accent.opacity(0.18) : FitTheme.card,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    category == item ? FitTheme.accent.opacity(0.4) : FitTheme.stroke
                                )
                            )
                            .foregroundStyle(category == item ? FitTheme.accent : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dateNavigator: some View {
        GlassCard(padding: 12) {
            HStack {
                Button { changeDate(-1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 38, height: 38)
                        .background(FitTheme.cardStrong, in: Circle())
                }

                Spacer()

                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(FitTheme.accent)

                Spacer()

                Button { changeDate(1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 38, height: 38)
                        .background(FitTheme.cardStrong, in: Circle())
                }
                .disabled(Calendar.current.isDateInToday(selectedDate))
                .opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1)
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .summary:
            if let summary { summaryContent(summary.dashboard) }
        case .sleep:
            if let sleep { sleepContent(sleep) }
        case .heart:
            if let heart { heartContent(heart) }
        case .activity:
            if let activity { activityContent(activity) }
        case .readiness:
            if let readiness { readinessContent(readiness) }
        }
    }

    private func summaryContent(_ d: Dashboard) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MetricCard(systemIcon: "heart.fill", title: "نبض الراحة", value: d.restingHR.map { "\($0) BPM" } ?? "—", tint: .red)
                MetricCard(systemIcon: "moon.fill", title: "النوم", value: minutesText(d.sleepMinutes), tint: FitTheme.accentPurple)
            }
            HStack(spacing: 12) {
                MetricCard(systemIcon: "figure.walk", title: "الخطوات", value: d.steps.map(String.init) ?? "—", tint: FitTheme.accent)
                MetricCard(systemIcon: "flame.fill", title: "السعرات", value: d.calories.map { "\($0)" } ?? "—", tint: .orange)
            }
            readinessCard(readiness: d.readiness, plan: d.todayPlan)
        }
    }

    private func sleepContent(_ r: HealthSleepResponse) -> some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 34)).foregroundStyle(FitTheme.accentPurple)
                    Text(minutesText(r.sleep?.totalMinutes)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("إجمالي النوم").foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                sleepTimeCard(
                    title: "نمت",
                    time: sleepClockText(r.sleep?.start),
                    icon: "moon.zzz.fill",
                    tint: FitTheme.accentPurple
                )
                sleepTimeCard(
                    title: "قمت",
                    time: sleepClockText(r.sleep?.end),
                    icon: "sunrise.fill",
                    tint: FitTheme.warning
                )
            }

            HStack(spacing: 10) {
                stageCard("عميق", r.sleep?.deepMinutes ?? 0, FitTheme.accentBlue)
                stageCard("خفيف", r.sleep?.lightMinutes ?? 0, FitTheme.accent)
            }
            HStack(spacing: 10) {
                stageCard("REM", r.sleep?.remMinutes ?? 0, FitTheme.accentPurple)
                stageCard("استيقاظ", r.sleep?.awakeMinutes ?? 0, FitTheme.warning)
            }
        }
    }

    private func heartContent(_ r: HealthHeartResponse) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MetricCard(systemIcon: "heart.fill", title: "النبض اللحظي", value: r.heart.currentBPM.map { "\($0) BPM" } ?? "غير متاح", tint: .red, subtitle: r.heart.lastReadingAt)
                MetricCard(systemIcon: "bed.double.fill", title: "نبض الراحة", value: r.heart.restingBPM.map { "\($0) BPM" } ?? "غير متاح", tint: FitTheme.danger)
            }
            GlassCard {
                Text(Calendar.current.isDateInToday(selectedDate) ? "النبض اللحظي يتحدث من أحدث قراءة متاحة من ساعتك." : "للأيام السابقة يعرض التطبيق نبض الراحة لذلك اليوم.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private func activityContent(_ r: HealthActivityResponse) -> some View {
        HStack(spacing: 12) {
            MetricCard(systemIcon: "figure.walk", title: "الخطوات", value: r.activity.steps.map(String.init) ?? "—", tint: FitTheme.accent)
            MetricCard(systemIcon: "flame.fill", title: "السعرات", value: r.activity.calories.map { "\($0)" } ?? "—", tint: .orange)
        }
    }

    private func readinessContent(_ r: HealthReadinessResponse) -> some View {
        readinessCard(readiness: r.readiness, plan: r.todayPlan)
    }

    private func readinessCard(readiness: String, plan: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("تحليل الجاهزية", systemImage: "bolt.heart.fill").font(.headline).foregroundStyle(FitTheme.warning)
                Text(readiness).font(.subheadline).foregroundStyle(.white.opacity(0.78)).textSelection(.enabled)
                Divider().overlay(Color.white.opacity(0.08))
                Label("خطة ذلك اليوم", systemImage: "scope").font(.headline).foregroundStyle(FitTheme.accent)
                Text(plan).font(.subheadline).foregroundStyle(.white.opacity(0.78)).textSelection(.enabled)
            }
        }
    }

    private func sleepTimeCard(
        title: String,
        time: String,
        icon: String,
        tint: Color
    ) -> some View {
        GlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(time)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func sleepClockText(_ value: String?) -> String {
        guard let value, !value.isEmpty, let date = parseSleepDate(value) else {
            return "غير متاح"
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ar_QA")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func parseSleepDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func stageCard(_ title: String, _ minutes: Int, _ tint: Color) -> some View {
        GlassCard(padding: 13) {
            VStack(alignment: .leading, spacing: 7) {
                Circle().fill(tint).frame(width: 9, height: 9)
                Text(minutesText(minutes)).font(.headline).foregroundStyle(.white)
                Text(title).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var hasVisibleData: Bool {
        switch category {
        case .summary: return summary != nil
        case .sleep: return sleep != nil
        case .heart: return heart != nil
        case .activity: return activity != nil
        case .readiness: return readiness != nil
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func load(force: Bool = false, useLocalCache: Bool = false) async {
        let date = dateString(selectedDate)
        error = nil

        if useLocalCache, restoreLocalCache(category: category, date: date) {
            loading = false
            refreshing = true
        } else if !hasVisibleData {
            loading = true
        }

        do {
            try await fetch(category: category, date: date, force: force, updateVisible: true)
            loading = false
            refreshing = false
            prefetchAdjacentDays(for: category)
        } catch {
            if !hasVisibleData { self.error = error.localizedDescription }
            loading = false
            refreshing = false
        }
    }

    private func fetch(
        category: HealthArchiveCategory,
        date: String,
        force: Bool,
        updateVisible: Bool
    ) async throws {
        switch category {
        case .summary:
            let value = try await APIClient.shared.healthSummary(date: date, force: force)
            if updateVisible { summary = value }
            HealthArchiveLocalCache.save(value, category: category, date: date)

        case .sleep:
            let value = try await APIClient.shared.healthSleep(date: date, force: force)
            if updateVisible { sleep = value }
            HealthArchiveLocalCache.save(value, category: category, date: date)

        case .heart:
            let value = try await APIClient.shared.healthHeart(date: date, force: force)
            if updateVisible { heart = value }
            HealthArchiveLocalCache.save(value, category: category, date: date)

        case .activity:
            let value = try await APIClient.shared.healthActivity(date: date, force: force)
            if updateVisible { activity = value }
            HealthArchiveLocalCache.save(value, category: category, date: date)

        case .readiness:
            let value = try await APIClient.shared.healthReadiness(date: date, force: force)
            if updateVisible { readiness = value }
            HealthArchiveLocalCache.save(value, category: category, date: date)
        }
    }

    private func restoreLocalCache(category: HealthArchiveCategory, date: String) -> Bool {
        switch category {
        case .summary:
            guard let value = HealthArchiveLocalCache.load(HealthSummaryResponse.self, category: category, date: date) else { return false }
            summary = value
        case .sleep:
            guard let value = HealthArchiveLocalCache.load(HealthSleepResponse.self, category: category, date: date) else { return false }
            sleep = value
        case .heart:
            guard let value = HealthArchiveLocalCache.load(HealthHeartResponse.self, category: category, date: date) else { return false }
            heart = value
        case .activity:
            guard let value = HealthArchiveLocalCache.load(HealthActivityResponse.self, category: category, date: date) else { return false }
            activity = value
        case .readiness:
            guard let value = HealthArchiveLocalCache.load(HealthReadinessResponse.self, category: category, date: date) else { return false }
            readiness = value
        }
        return true
    }

    private func prefetchAdjacentDays(for category: HealthArchiveCategory) {
        let currentDate = selectedDate
        let dates = [-1, 1].compactMap { Calendar.current.date(byAdding: .day, value: $0, to: currentDate) }
            .filter { $0 <= Date() }

        for day in dates {
            let date = dateString(day)
            Task(priority: .utility) {
                try? await fetch(category: category, date: date, force: false, updateVisible: false)
            }
        }
    }

    private func clearVisibleState() {
        summary = nil
        sleep = nil
        heart = nil
        activity = nil
        readiness = nil
        error = nil
    }

    private func minutesText(_ value: Int?) -> String {
        guard let m = value, m > 0 else { return "—" }
        return "\(m / 60)س \(m % 60)د"
    }

    private func changeDate(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate), d <= Date() {
            selectedDate = d
        }
    }
}
