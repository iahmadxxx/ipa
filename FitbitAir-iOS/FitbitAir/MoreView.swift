import SwiftUI

struct MoreView: View {
    @State private var status: ConnectionStatusResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var showTokenEntry = false
    @State private var manualToken = ""

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

enum HealthArchiveCategory: String, CaseIterable, Identifiable {
    case summary, sleep, heart, activity, readiness
    var id: String { rawValue }
    var title: String {
        switch self { case .summary: return "الملخص"; case .sleep: return "النوم"; case .heart: return "النبض"; case .activity: return "النشاط"; case .readiness: return "الجاهزية" }
    }
    var icon: String {
        switch self { case .summary: return "square.grid.2x2.fill"; case .sleep: return "moon.stars.fill"; case .heart: return "heart.fill"; case .activity: return "figure.walk"; case .readiness: return "bolt.heart.fill" }
    }
}

struct HealthArchiveView: View {
    @State private var category: HealthArchiveCategory
    @State private var selectedDate = Date()
    @State private var response: HealthDayResponse?
    @State private var loading = true
    @State private var error: String?

    init(initialCategory: HealthArchiveCategory) { _category = State(initialValue: initialCategory) }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    categoryPicker
                    dateNavigator
                    if loading { LoadingStateView(text: "أحدث بيانات هذا اليوم…") }
                    else if let error { ErrorBanner(message: error) }
                    else if let response { content(response) }
                }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 30)
            }.refreshable { await load() }
        }
        .navigationTitle("السجل الصحي")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: selectedDate) { _, _ in Task { await load() } }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HealthArchiveCategory.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { category = item }
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .background(category == item ? FitTheme.accent.opacity(0.18) : FitTheme.card, in: Capsule())
                            .overlay(Capsule().stroke(category == item ? FitTheme.accent.opacity(0.4) : FitTheme.stroke))
                            .foregroundStyle(category == item ? FitTheme.accent : .white.opacity(0.6))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var dateNavigator: some View {
        GlassCard(padding: 12) {
            HStack {
                Button { changeDate(-1) } label: { Image(systemName: "chevron.right").frame(width: 38, height: 38).background(FitTheme.cardStrong, in: Circle()) }
                Spacer()
                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).tint(FitTheme.accent)
                Spacer()
                Button { changeDate(1) } label: { Image(systemName: "chevron.left").frame(width: 38, height: 38).background(FitTheme.cardStrong, in: Circle()) }
                    .disabled(Calendar.current.isDateInToday(selectedDate)).opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1)
            }.foregroundStyle(.white)
        }
    }

    @ViewBuilder private func content(_ r: HealthDayResponse) -> some View {
        switch category {
        case .summary: summaryContent(r)
        case .sleep: sleepContent(r)
        case .heart: heartContent(r)
        case .activity: activityContent(r)
        case .readiness: readinessContent(r)
        }
    }

    private func summaryContent(_ r: HealthDayResponse) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MetricCard(systemIcon: "heart.fill", title: "نبض الراحة", value: r.dashboard.restingHR.map { "\($0) BPM" } ?? "—", tint: .red)
                MetricCard(systemIcon: "moon.fill", title: "النوم", value: minutesText(r.dashboard.sleepMinutes), tint: FitTheme.accentPurple)
            }
            HStack(spacing: 12) {
                MetricCard(systemIcon: "figure.walk", title: "الخطوات", value: r.dashboard.steps.map(String.init) ?? "—", tint: FitTheme.accent)
                MetricCard(systemIcon: "flame.fill", title: "السعرات", value: r.dashboard.calories.map { "\($0)" } ?? "—", tint: .orange)
            }
            readinessContent(r)
        }
    }

    private func sleepContent(_ r: HealthDayResponse) -> some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 34)).foregroundStyle(FitTheme.accentPurple)
                    Text(minutesText(r.sleep?.totalMinutes ?? r.dashboard.sleepMinutes)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("إجمالي النوم").foregroundStyle(.white.opacity(0.55))
                }.frame(maxWidth: .infinity)
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

    private func heartContent(_ r: HealthDayResponse) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MetricCard(systemIcon: "heart.fill", title: "النبض اللحظي", value: r.dashboard.currentHR.map { "\($0) BPM" } ?? "غير متاح", tint: .red, subtitle: r.dashboard.currentHRTime)
                MetricCard(systemIcon: "bed.double.fill", title: "نبض الراحة", value: r.dashboard.restingHR.map { "\($0) BPM" } ?? "غير متاح", tint: FitTheme.danger)
            }
            GlassCard { Text(Calendar.current.isDateInToday(selectedDate) ? "النبض اللحظي يتحدث من أحدث قراءة متاحة من ساعتك." : "للأيام السابقة يعرض التطبيق نبض الراحة المحفوظ لذلك اليوم؛ القراءة اللحظية متاحة لليوم الحالي فقط.").font(.footnote).foregroundStyle(.white.opacity(0.58)) }
        }
    }

    private func activityContent(_ r: HealthDayResponse) -> some View {
        HStack(spacing: 12) {
            MetricCard(systemIcon: "figure.walk", title: "الخطوات", value: r.dashboard.steps.map(String.init) ?? "—", tint: FitTheme.accent)
            MetricCard(systemIcon: "flame.fill", title: "السعرات", value: r.dashboard.calories.map { "\($0)" } ?? "—", tint: .orange)
        }
    }

    private func readinessContent(_ r: HealthDayResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("تحليل الجاهزية", systemImage: "bolt.heart.fill").font(.headline).foregroundStyle(FitTheme.warning)
                Text(r.dashboard.readiness).font(.subheadline).foregroundStyle(.white.opacity(0.78)).textSelection(.enabled)
                Divider().overlay(Color.white.opacity(0.08))
                Label("خطة ذلك اليوم", systemImage: "scope").font(.headline).foregroundStyle(FitTheme.accent)
                Text(r.dashboard.todayPlan).font(.subheadline).foregroundStyle(.white.opacity(0.78)).textSelection(.enabled)
            }
        }
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

    private func minutesText(_ value: Int?) -> String {
        guard let m = value, m > 0 else { return "—" }
        return "\(m / 60)س \(m % 60)د"
    }

    private func changeDate(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate), d <= Date() { selectedDate = d }
    }

    private func load() async {
        loading = true; error = nil
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        do { response = try await APIClient.shared.healthDay(date: f.string(from: selectedDate)) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
