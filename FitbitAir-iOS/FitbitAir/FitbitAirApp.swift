import SwiftUI
import BackgroundTasks

@main
struct FitbitAirApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundSyncManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
                .tint(FitTheme.accent)
                .onAppear {
                    BackgroundSyncManager.shared.scheduleAll()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                BackgroundSyncManager.shared.scheduleAll()
            case .background:
                BackgroundSyncManager.shared.scheduleAll()
            default:
                break
            }
        }
    }
}


private final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()

    private let refreshIdentifier = "com.ahmed.fitbitair.refresh"
    private let processingIdentifier = "com.ahmed.fitbitair.processing"
    private let lastSyncKey = "fitbitair.background.lastSync"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleProcessing(processingTask)
        }
    }

    func scheduleAll() {
        scheduleRefresh()
        scheduleProcessing()
    }

    private func scheduleRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS may defer or reject a request temporarily; the next app lifecycle event retries.
        }
    }

    private func scheduleProcessing() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)

        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The refresh task remains available even if processing is deferred.
        }
    }

    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()

        let syncTask = Task {
            let success = await performSync()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    private func handleProcessing(_ task: BGProcessingTask) {
        scheduleProcessing()

        let syncTask = Task {
            let success = await performSync()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    private func performSync() async -> Bool {
        guard !Task.isCancelled else { return false }

        let date = qatarDateString()

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            group.addTask {
                do {
                    _ = try await APIClient.shared.healthSummary(date: date, force: true)
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                do {
                    _ = try await APIClient.shared.healthSleep(date: date, force: true)
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                do {
                    _ = try await APIClient.shared.healthActivity(date: date, force: true)
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                do {
                    _ = try await APIClient.shared.healthReadiness(date: date, force: true)
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                do {
                    _ = try await APIClient.shared.deviceStatus(force: true)
                    return true
                } catch {
                    return false
                }
            }

            group.addTask {
                do {
                    _ = try await APIClient.shared.liveHeart()
                    return true
                } catch {
                    return false
                }
            }

            var values: [Bool] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        let succeeded = results.contains(true)
        if succeeded {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
        }
        return succeeded
    }

    private func qatarDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Qatar")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct AppLaunchView: View {
    @State private var showMainApp = false

    var body: some View {
        ZStack {
            if showMainApp {
                RootView()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            } else {
                PersonalSplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: showMainApp)
        .task {
            try? await Task.sleep(for: .seconds(3.0))
            showMainApp = true
        }
    }
}

private struct PersonalSplashView: View {
    @State private var logoScale: CGFloat = 0.65
    @State private var logoOpacity = 0.0
    @State private var ringRotation = 0.0
    @State private var textOffset: CGFloat = 22
    @State private var textOpacity = 0.0
    @State private var glow = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [FitTheme.accent, FitTheme.accentBlue, FitTheme.accentPurple, FitTheme.accent],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 142, height: 142)
                        .rotationEffect(.degrees(ringRotation))
                        .opacity(0.75)

                    Circle()
                        .fill(FitTheme.accent.opacity(glow ? 0.20 : 0.08))
                        .frame(width: 112, height: 112)
                        .blur(radius: glow ? 24 : 8)

                    ZStack {
                        RoundedRectangle(cornerRadius: 31, style: .continuous)
                            .fill(FitTheme.gradient)
                            .frame(width: 92, height: 92)
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .shadow(color: FitTheme.accent.opacity(0.35), radius: 30, y: 8)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                VStack(spacing: 9) {
                    Text("FITBIT AIR")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(3.8)
                        .foregroundStyle(.white)

                    Text("نسخة شخصية")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FitTheme.accent)

                    HStack(spacing: 7) {
                        Image(systemName: "lock.fill")
                        Text("مخصص لأحمد المري فقط")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 4)
                }
                .offset(y: textOffset)
                .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.55)) {
                textOffset = 0
                textOpacity = 1
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glow.toggle()
            }
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, workout, history, coach, insights, more
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .workout: return "التمرين"
        case .history: return "السجل"
        case .coach: return "المدرب"
        case .insights: return "التحليلات"
        case .more: return "المزيد"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .workout: return "dumbbell.fill"
        case .history: return "clock.arrow.circlepath"
        case .coach: return "bubble.left.and.text.bubble.right.fill"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .more: return "ellipsis.circle.fill"
        }
    }
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            Group {
                switch selectedTab {
                case .home:
                    NavigationStack { HomeView() }
                case .workout:
                    NavigationStack { WorkoutView() }
                case .history:
                    NavigationStack { HistoryView() }
                case .coach:
                    CoachView()
                case .insights:
                    NavigationStack { InsightsView() }
                case .more:
                    NavigationStack { MoreView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 88)

            CustomTabBar(selection: $selectedTab)
        }
    }
}

private struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if selection == tab {
                                Capsule()
                                    .fill(FitTheme.accent.opacity(0.14))
                                    .frame(width: 44, height: 30)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(selection == tab ? FitTheme.accent : .white.opacity(0.42))
                        }
                        Text(tab.title)
                            .font(.system(size: 9, weight: selection == tab ? .bold : .medium))
                            .foregroundStyle(selection == tab ? .white : .white.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.045, green: 0.06, blue: 0.09).opacity(0.98))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.09)))
                .shadow(color: .black.opacity(0.32), radius: 24, y: 12)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 7)
    }
}
