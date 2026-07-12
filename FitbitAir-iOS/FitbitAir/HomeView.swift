import SwiftUI

private enum DashboardLocalCache {
    private static let key = "fitbitair.dashboard.cache"

    static func load(for date: String) -> Dashboard? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: Dashboard].self, from: data) else {
            return nil
        }
        return payload[date]
    }

    static func save(_ dashboard: Dashboard) {
        var payload: [String: Dashboard] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let existing = try? JSONDecoder().decode([String: Dashboard].self, from: data) {
            payload = existing
        }
        payload[dashboard.date] = dashboard
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private enum LiveHeartLocalCache {
    private static let key = "fitbitair.liveheart.last.valid"

    static func load() -> LiveHeartResponse? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(LiveHeartResponse.self, from: data)
        else { return nil }

        // قراءة بلا وقت لا تُحفظ كأنها صالحة للأبد.
        guard value.bpm != nil, value.measuredAt != nil else {
            clear()
            return nil
        }

        return value
    }

    static func save(_ value: LiveHeartResponse) {
        // نخزن فقط قراءة لها وقت قياس حقيقي.
        guard value.bpm != nil,
              value.measuredAt != nil,
              let data = try? JSONEncoder().encode(value)
        else { return }

        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct HomeView: View {
    @State private var dashboard: Dashboard?
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDate = Date()
    @State private var deviceStatus: DeviceStatusResponse?
    @State private var deviceStatusError: String?
    @State private var liveHeart: LiveHeartResponse?
    @State private var liveHeartMessage: String?
    @State private var dailyBrief: DailyBriefResponse?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                heroHeader
                dateSelector
                if isToday {
                    deviceSyncCard
                    if let dailyBrief { dailyBriefCard(dailyBrief) }
                }

                if let dashboard {
                    readinessHero(dashboard)
                    metricGrid(dashboard)
                    planCard(dashboard)
                    readinessDetailsCard(dashboard)
                } else if loading {
                    LoadingStateView(text: "جاري مزامنة بياناتك…")
                }

                if let error, dashboard == nil {
                    ErrorBanner(message: error)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.clear)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            async let dashboardTask: Void = load(force: true)
            async let deviceTask: Void = loadDeviceStatus(force: true)
            async let heartTask: Void = loadLiveHeart()
            async let briefTask: Void = loadDailyBrief()
            _ = await (dashboardTask, deviceTask, heartTask, briefTask)
        }
        .task {
            async let dashboardTask: Void = load(useLocalCache: true)
            async let deviceTask: Void = loadDeviceStatus()
            async let heartTask: Void = loadLiveHeart()
            async let briefTask: Void = loadDailyBrief()
            _ = await (dashboardTask, deviceTask, heartTask, briefTask)
        }
        .task(id: isToday) {
            guard isToday else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await loadLiveHeart()
            }
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FitTheme.accent)
                Text("هلا أحمد 👋")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("كل أرقامك الصحية والرياضية في مكان واحد")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            CompactIconButton(systemName: loading ? "hourglass" : "arrow.clockwise") {
                Task {
                    async let dashboardTask: Void = load(force: true)
                    async let deviceTask: Void = loadDeviceStatus(force: true)
                    async let heartTask: Void = loadLiveHeart()
                    async let briefTask: Void = loadDailyBrief()
                    _ = await (dashboardTask, deviceTask, heartTask, briefTask)
                }
            }
            .disabled(loading)
        }
    }

    private var dateSelector: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .foregroundStyle(FitTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "بيانات اليوم" : "بيانات يوم محدد")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                    DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                }
                Spacer()
                if !isToday {
                    Button("اليوم") {
                        selectedDate = Date()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accent)
                }
            }
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await load(useLocalCache: true) }
        }
    }

    private var deviceSyncCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(deviceAccentColor.opacity(0.14))
                            .frame(width: 48, height: 48)

                        Image(systemName: deviceIcon)
                            .font(.title3.bold())
                            .foregroundStyle(deviceAccentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(deviceTitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)

                        Text(deviceSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))

                        if let device = deviceStatus?.device {
                            Text(device)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("شحن السوار")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        HStack(spacing: 4) {
                            if deviceStatus?.batteryStatus == "CHARGING" {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(FitTheme.warning)
                            }
                            Text(batteryText)
                                .font(.title3.bold())
                                .foregroundStyle(batteryColor)
                        }
                    }
                }

                if deviceStatus?.needsReauth == true,
                   let urlString = deviceStatus?.reauthURL,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("تجديد الربط", systemImage: "link.badge.plus")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(FitTheme.gradient, in: RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.black.opacity(0.82))
                    }
                } else if deviceStatus?.status == "unavailable" || deviceStatus == nil {
                    Button {
                        Task { await loadDeviceStatus(force: true) }
                    } label: {
                        Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func dailyBriefCard(_ brief: DailyBriefResponse) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13).fill(FitTheme.accent.opacity(0.15)).frame(width: 42, height: 42)
                        Image(systemName: "sparkles").foregroundStyle(FitTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("تقرير اليوم").font(.caption).foregroundStyle(.white.opacity(0.55))
                        Text(brief.headline).font(.headline)
                    }
                    Spacer()
                    Text("\(brief.recoveryScore)%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(FitTheme.accent)
                }
                Text(brief.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                Divider().overlay(Color.white.opacity(0.08))
                Label(brief.workoutRecommendation, systemImage: "dumbbell.fill")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                Label(brief.nutritionRecommendation, systemImage: "fork.knife")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
    }

    private func readinessHero(_ d: Dashboard) -> some View {
        let score = extractedScore(d.readiness)
        return GlassCard(padding: 18) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(
                            FitTheme.gradient,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(score)")
                            .font(.system(size: 31, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("من 100")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Image(systemName: "bolt.heart.fill")
                            .foregroundStyle(FitTheme.accent)
                        Text("جاهزيتك اليوم")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Text(readinessLabel(score))
                        .font(.title3.bold())
                        .foregroundStyle(readinessColor(score))
                    Text(readinessSummary(d.readiness))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metricGrid(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "مؤشراتك الآن", subtitle: "آخر بيانات متاحة من ساعتك")
            LazyVGrid(columns: columns, spacing: 10) {
                MetricCard(
                    systemIcon: "heart.fill",
                    title: liveHeartTitle,
                    value: liveHeartBPMText,
                    tint: .red,
                    subtitle: liveHeartSubtitle
                )
                MetricCard(systemIcon: "bed.double.fill", title: "نبض الراحة", value: d.restingHR.map { "\($0) BPM" } ?? "—", tint: .pink)
                MetricCard(systemIcon: "moon.stars.fill", title: "النوم", value: minutes(d.sleepMinutes), tint: FitTheme.accentPurple)
                MetricCard(systemIcon: "figure.walk", title: "الخطوات", value: d.steps.map { $0.formatted() } ?? "—", tint: FitTheme.accent)
                MetricCard(systemIcon: "flame.fill", title: "السعرات", value: d.calories.map { "\($0)" } ?? "—", tint: .orange)
                MetricCard(systemIcon: "calendar.badge.clock", title: "التاريخ", value: compactDate(d.date), tint: FitTheme.accentBlue)
            }
        }
    }

    private func planCard(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "خطة اليوم", subtitle: "توصية مخصصة بناءً على بياناتك")
            GlassCard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(FitTheme.accent.opacity(0.13))
                            .frame(width: 46, height: 46)
                        Image(systemName: "target")
                            .font(.title3.bold())
                            .foregroundStyle(FitTheme.accent)
                    }
                    Text(d.todayPlan)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func readinessDetailsCard(_ d: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "تفاصيل الجاهزية")
            GlassCard {
                Text(d.readiness)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    private func load(force: Bool = false, useLocalCache: Bool = false) async {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let dateString = fmt.string(from: selectedDate)

        if useLocalCache, let cached = DashboardLocalCache.load(for: dateString) {
            dashboard = cached
            loading = false
        } else if dashboard == nil {
            loading = true
        }

        error = nil

        do {
            let fresh = try await APIClient.shared.dashboard(date: dateString, force: force)
            dashboard = fresh
            DashboardLocalCache.save(fresh)
        } catch {
            if dashboard == nil {
                self.error = error.localizedDescription
            }
        }

        loading = false
    }

    private func loadDailyBrief() async {
        guard isToday else { return }
        do {
            dailyBrief = try await APIClient.shared.dailyBrief()
        } catch {
            // The normal dashboard stays usable if the optional brief is unavailable.
        }
    }

    private func loadDeviceStatus(force: Bool = false) async {
        do {
            deviceStatus = try await APIClient.shared.deviceStatus(force: force)
            deviceStatusError = nil
        } catch {
            // Device status is optional and never becomes a global Home error.
            deviceStatusError = "حالة السوار غير متاحة مؤقتًا."
        }
    }

    private func loadLiveHeart() async {
        guard isToday else { return }

        if liveHeart == nil, let cached = LiveHeartLocalCache.load() {
            liveHeart = cached
        }

        do {
            let value = try await APIClient.shared.liveHeart()
            liveHeartMessage = value.message

            // Strict rule: never show BPM without its matching measurement time.
            guard value.ok,
                  value.bpm != nil,
                  let measuredAt = value.measuredAt,
                  parseHealthDate(measuredAt) != nil
            else {
                liveHeart = nil
                LiveHeartLocalCache.clear()
                if value.status == "no_data" {
                    liveHeartMessage = value.message
                }
                return
            }

            liveHeart = value
            LiveHeartLocalCache.save(value)
        } catch {
            liveHeartMessage = "تعذر جلب قراءة نبض موثقة الآن."
        }
    }

    private var deviceTitle: String {
        guard let status = deviceStatus else { return "حالة السوار" }
        switch status.status {
        case "ok": return "السوار متصل"
        case "reauth": return "يحتاج تجديد الربط"
        default: return "حالة السوار غير متاحة"
        }
    }

    private var deviceSubtitle: String {
        guard let status = deviceStatus else {
            return deviceStatusError ?? "جاري فحص حالة السوار…"
        }

        if let sync = status.lastSyncTime, !sync.isEmpty {
            return "آخر مزامنة: \(formatFullHealthTime(sync))"
        }

        return status.message
    }

    private var deviceIcon: String {
        switch deviceStatus?.status {
        case "ok": return batteryIcon
        case "reauth": return "link.badge.plus"
        default: return "exclamationmark.triangle"
        }
    }

    private var deviceAccentColor: Color {
        switch deviceStatus?.status {
        case "ok": return FitTheme.accent
        case "reauth": return FitTheme.warning
        default: return .white.opacity(0.45)
        }
    }

    private var liveHeartTitle: String {
        guard let value = liveHeart,
              value.bpm != nil,
              value.measuredAt != nil
        else { return "النبض" }

        return effectiveHeartAgeSeconds(value) <= 120 ? "النبض الآن" : "آخر نبض متاح"
    }

    private var liveHeartBPMText: String {
        guard let bpm = liveHeart?.bpm else { return "غير متاح" }
        return "\(bpm) BPM"
    }

    private var liveHeartSubtitle: String? {
        guard let value = liveHeart,
              value.bpm != nil,
              let measuredAt = value.measuredAt
        else {
            return liveHeartMessage ?? "لا توجد قراءة نبض موثقة"
        }

        let age = effectiveHeartAgeSeconds(value)
        let time = formatHealthTime(measuredAt)

        if age <= 120 {
            return "آخر قراءة موثقة • \(time) • قبل \(age)ث"
        }

        if age < 3600 {
            return "قراءة قديمة • \(time) • قبل \(age / 60)د"
        }

        return "قراءة قديمة • \(time)"
    }

    private func effectiveHeartAgeSeconds(_ value: LiveHeartResponse) -> Int {
        if let measuredAt = value.measuredAt,
           let date = parseHealthDate(measuredAt) {
            return max(0, Int(Date().timeIntervalSince(date)))
        }
        return value.ageSeconds ?? Int.max
    }

    private func parseHealthDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return fallback.date(from: value)
    }

    private func formatHealthTime(_ value: String) -> String {
        guard let date = parseHealthDate(value) else { return value }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_QA")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar")
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    private func formatFullHealthTime(_ value: String) -> String {
        guard let date = parseHealthDate(value) else { return value }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ar_QA")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar")
        formatter.dateFormat = Calendar.current.isDateInToday(date)
            ? "اليوم، h:mm:ss a"
            : "d MMM، h:mm:ss a"
        return formatter.string(from: date)
    }

    private var batteryText: String {
        guard let level = deviceStatus?.batteryLevel else { return "—" }
        return "\(level)%"
    }

    private var batteryIcon: String {
        guard let level = deviceStatus?.batteryLevel else { return "battery.0percent" }
        switch level {
        case 80...: return "battery.100percent"
        case 55..<80: return "battery.75percent"
        case 30..<55: return "battery.50percent"
        case 10..<30: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var batteryColor: Color {
        guard let level = deviceStatus?.batteryLevel else { return .white.opacity(0.45) }
        switch level {
        case 50...: return FitTheme.positive
        case 20..<50: return FitTheme.warning
        default: return FitTheme.danger
        }
    }

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "صباح النشاط"
        case 12..<18: return "مساء الإنجاز"
        default: return "مساء العافية"
        }
    }

    private func minutes(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value / 60)س \(value % 60)د"
    }

    private func extractedScore(_ text: String) -> Int {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        return min(max(numbers.first ?? 75, 0), 100)
    }

    private func readinessLabel(_ score: Int) -> String {
        switch score {
        case 85...: return "جاهزية ممتازة"
        case 70..<85: return "جاهزية جيدة"
        case 50..<70: return "خذها بهدوء"
        default: return "الأولوية للتعافي"
        }
    }

    private func readinessColor(_ score: Int) -> Color {
        switch score {
        case 80...: return FitTheme.positive
        case 60..<80: return FitTheme.warning
        default: return FitTheme.danger
        }
    }

    private func readinessSummary(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        return clean.count > 150 ? String(clean.prefix(150)) + "…" : clean
    }

    private func compactDate(_ date: String) -> String {
        let input = DateFormatter(); input.dateFormat = "yyyy-MM-dd"
        guard let value = input.date(from: date) else { return date }
        let output = DateFormatter(); output.locale = Locale(identifier: "ar_QA"); output.dateFormat = "d MMM"
        return output.string(from: value)
    }
}
