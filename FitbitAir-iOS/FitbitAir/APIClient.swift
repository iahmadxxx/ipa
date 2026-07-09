import Foundation

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
    func editTodaySet(day: String, idx: Int, set: Int, reps: Int, weight: Double) async throws -> SaveSetResponse { try await request("api/ios/workout/edit", method: "POST", body: ["day":day,"idx":idx,"set_number":set,"reps":reps,"weight":weight]) }
    func addExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/add", method: "POST", body: ["day":day,"name":name]) }
    func deleteExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/delete", method: "POST", body: ["day":day,"name":name]) }
    func history() async throws -> [HistoryDay] { let r: HistoryResponse = try await request("api/ios/history"); return r.records }
    func editHistory(id: Int, reps: Int, weight: Double) async throws { let _: SimpleResponse = try await request("api/ios/history/edit", method: "POST", body: ["id":id,"reps":reps,"weight":weight]) }
    func deleteHistory(id: Int) async throws { let _: SimpleResponse = try await request("api/ios/history/delete", method: "POST", body: ["id":id]) }
    func ask(_ message: String) async throws -> String { let r: CoachResponse = try await request("api/ios/coach", method: "POST", body: ["message":message]); return r.answer }
    func insights() async throws -> InsightsResponse { try await request("api/ios/insights") }

    func connectionStatus() async throws -> ConnectionStatusResponse { try await request("api/ios/connection") }
    func healthDay(date: String) async throws -> HealthDayResponse { try await request("api/ios/health/day?date=\(date)") }
    func saveRefreshToken(_ token: String) async throws -> ConnectionStatusResponse { try await request("api/ios/connection/token", method: "POST", body: ["refresh_token": token]) }
}
