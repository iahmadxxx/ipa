import Foundation

struct APIEnvelope<T: Decodable>: Decodable { let ok: Bool?; let dashboard: T? }
struct DashboardResponse: Decodable { let ok: Bool; let dashboard: Dashboard }
struct Dashboard: Decodable, Equatable {
    let date: String; let steps: Int?; let calories: Int?; let restingHR: Int?; let currentHR: Int?; let currentHRTime: String?; let sleepMinutes: Int?; let readiness: String; let todayPlan: String
    enum CodingKeys: String, CodingKey { case date, steps, calories, readiness; case restingHR = "resting_hr"; case currentHR = "current_hr"; case currentHRTime = "current_hr_time"; case sleepMinutes = "sleep_minutes"; case todayPlan = "today_plan" }
}
struct WorkoutPlanResponse: Decodable { let ok: Bool; let days: [WorkoutDay] }
struct WorkoutDay: Decodable, Identifiable, Hashable { let key: String; let label: String; let exercises: [String]; var id: String { key } }
struct GymSet: Codable, Identifiable, Hashable { let id: Int?; let setNumber: Int; var reps: Int; var weight: Double; enum CodingKeys: String, CodingKey { case id, reps, weight; case setNumber = "set_number" } }
struct WorkoutContext: Decodable { let ok: Bool; let dayLabel: String; let exercise: String; let todaySets: [GymSet]; let lastSession: LastSession?; let recommendation: Recommendation?; enum CodingKeys: String, CodingKey { case ok, exercise, recommendation; case dayLabel = "day_label"; case todaySets = "today_sets"; case lastSession = "last_session" } }
struct LastSession: Decodable { let date: String; let sets: [GymSet] }
struct Recommendation: Decodable { let text: String? }
struct SaveSetResponse: Decodable { let ok: Bool; let savedSet: Int?; let todaySets: [GymSet]; let prEvents: [String]?; enum CodingKeys: String, CodingKey { case ok; case savedSet = "saved_set"; case todaySets = "today_sets"; case prEvents = "pr_events" } }
struct HistoryResponse: Decodable { let ok: Bool; let records: [HistoryDay] }
struct HistoryDay: Decodable, Identifiable { let date: String; let exercises: [HistoryExercise]; var id: String { date } }
struct HistoryExercise: Decodable, Identifiable { let dayKey: String; let exercise: String; let dayLabel: String; let sets: [GymSet]; var id: String { dayKey + exercise }; enum CodingKeys: String, CodingKey { case exercise, sets; case dayKey = "day_key"; case dayLabel = "day_label" } }
struct CoachResponse: Decodable { let ok: Bool; let answer: String }
struct InsightsResponse: Decodable { let ok: Bool; let readiness: String; let todayPlan: String; let progress: String; let balance: String; let nextWeights: String; let weeklyReport: String; enum CodingKeys: String, CodingKey { case ok, readiness, progress, balance; case todayPlan = "today_plan"; case nextWeights = "next_weights"; case weeklyReport = "weekly_report" } }
struct SimpleResponse: Decodable { let ok: Bool?; let error: String? }
struct ChatMessage: Identifiable { let id = UUID(); let role: Role; let text: String; enum Role: Equatable { case user, assistant } }
