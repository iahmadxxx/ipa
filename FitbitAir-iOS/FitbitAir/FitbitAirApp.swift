import SwiftUI

@main struct FitbitAirApp: App {
    var body: some Scene { WindowGroup { RootView().environment(\.layoutDirection, .rightToLeft).tint(FitTheme.accent) } }
}
struct RootView: View {
    var body: some View { TabView {
        NavigationStack { HomeView() }.tabItem { Label("الرئيسية", systemImage:"house.fill") }
        NavigationStack { WorkoutView() }.tabItem { Label("التمرين", systemImage:"dumbbell.fill") }
        NavigationStack { HistoryView() }.tabItem { Label("السجل", systemImage:"clock.arrow.circlepath") }
        NavigationStack { CoachView() }.tabItem { Label("المدرب", systemImage:"bubble.left.and.bubble.right.fill") }
        NavigationStack { InsightsView() }.tabItem { Label("التحليلات", systemImage:"chart.line.uptrend.xyaxis") }
    } }
}
