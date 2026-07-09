import Foundation

// MARK: - Connection & Health Archive Models
// Kept in this file intentionally so APIClient and the new More/Health Archive
// features always compile together in the same target.

struct ConnectionStatusResponse: Decodable {
    let ok: Bool
    let connected: Bool
    let needsReauth: Bool
    let tokenUpdatedAt: String?
    let reauthURL: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok
        case connected
        case message
        case needsReauth = "needs_reauth"
        case tokenUpdatedAt = "token_updated_at"
        case reauthURL = "reauth_url"
    }
}

struct HealthDayResponse: Decodable {
    let ok: Bool
    let dashboard: Dashboard
    let sleep: SleepDetails?
}

struct SleepDetails: Decodable {
    let start: String?
    let end: String?
    let totalMinutes: Int?
    let deepMinutes: Int
    let lightMinutes: Int
    let remMinutes: Int
    let awakeMinutes: Int

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case totalMinutes = "total_minutes"
        case deepMinutes = "deep_minutes"
        case lightMinutes = "light_minutes"
        case remMinutes = "rem_minutes"
        case awakeMinutes = "awake_minutes"
    }
}


actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.baseURL)?.absoluteURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url); req.httpMethod = method; req.timeoutInterval = 30
        req.setValue("Bearer \(AppConfig.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "تعذر الاتصال بالخادم"
            throw NSError(domain: "FitbitAir", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try decoder.decode(T.self, from: data)
    }
    func dashboard(date: String? = nil) async throws -> Dashboard { let path = date == nil ? "api/ios/dashboard" : "api/ios/dashboard?date=\(date!)"; let r: DashboardResponse = try await request(path); return r.dashboard }
    func plan() async throws -> [WorkoutDay] { let r: WorkoutPlanResponse = try await request("api/ios/plan"); return r.days }
    func workoutContext(day: String, idx: Int) async throws -> WorkoutContext { try await request("api/ios/workout/context?day=\(day)&idx=\(idx)") }
    func saveSet(day: String, idx: Int, reps: Int, weight: Double) async throws -> SaveSetResponse { try await request("api/ios/workout/set", method: "POST", body: ["day":day,"idx":idx,"reps":reps,"weight":weight]) }
    func editTodaySet(day: String, idx: Int, id: Int?, set: Int, reps: Int, weight: Double) async throws -> SaveSetResponse {
        var body: [String: Any] = ["day": day, "idx": idx, "set_number": set, "reps": reps, "weight": weight]
        if let id { body["id"] = id }
        return try await request("api/ios/workout/edit", method: "POST", body: body)
    }
    func addExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/add", method: "POST", body: ["day":day,"name":name]) }
    func deleteExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/delete", method: "POST", body: ["day":day,"name":name]) }
    func renameExercise(day: String, oldName: String, newName: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/rename", method: "POST", body: ["day":day,"old_name":oldName,"new_name":newName]) }
    func addSection(label: String) async throws { let _: SimpleResponse = try await request("api/ios/section/add", method: "POST", body: ["label":label]) }
    func renameSection(day: String, label: String) async throws { let _: SimpleResponse = try await request("api/ios/section/rename", method: "POST", body: ["day":day,"label":label]) }
    func deleteSection(day: String) async throws { let _: SimpleResponse = try await request("api/ios/section/delete", method: "POST", body: ["day":day]) }
    func history() async throws -> [HistoryDay] { let r: HistoryResponse = try await request("api/ios/history"); return r.records }
    func editHistory(id: Int, reps: Int, weight: Double) async throws { let _: SimpleResponse = try await request("api/ios/history/edit", method: "POST", body: ["id":id,"reps":reps,"weight":weight]) }
    func deleteHistory(id: Int) async throws { let _: SimpleResponse = try await request("api/ios/history/delete", method: "POST", body: ["id":id]) }
    func ask(_ message: String) async throws -> String { let r: CoachResponse = try await request("api/ios/coach", method: "POST", body: ["message":message]); return r.answer }
    func insights() async throws -> InsightsResponse { try await request("api/ios/insights") }

    func connectionStatus() async throws -> ConnectionStatusResponse { try await request("api/ios/connection") }
    func healthDay(date: String) async throws -> HealthDayResponse {
        guard let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return try await request("api/ios/health/day?date=\(encodedDate)")
    }
    func saveRefreshToken(_ token: String) async throws -> ConnectionStatusResponse { try await request("api/ios/connection/token", method: "POST", body: ["refresh_token": token]) }
}
