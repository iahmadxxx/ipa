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

struct SleepDetails: Codable {
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


struct HealthSleepResponse: Codable {
    let ok: Bool
    let date: String
    let sleep: SleepDetails?
}

struct HealthHeartResponse: Codable {
    struct HeartPayload: Codable {
        let currentBPM: Int?
        let restingBPM: Int?
        let lastReadingAt: String?

        enum CodingKeys: String, CodingKey {
            case currentBPM = "current_bpm"
            case restingBPM = "resting_bpm"
            case lastReadingAt = "last_reading_at"
        }
    }

    let ok: Bool
    let date: String
    let heart: HeartPayload
}

struct HealthActivityResponse: Codable {
    struct ActivityPayload: Codable {
        let steps: Int?
        let calories: Int?
    }

    let ok: Bool
    let date: String
    let activity: ActivityPayload
}

struct HealthReadinessResponse: Codable {
    let ok: Bool
    let date: String
    let readiness: String
    let todayPlan: String

    enum CodingKeys: String, CodingKey {
        case ok, date, readiness
        case todayPlan = "today_plan"
    }
}

struct HealthSummaryResponse: Codable {
    let ok: Bool
    let date: String
    let dashboard: Dashboard
}

struct DeviceStatusResponse: Codable {
    let ok: Bool
    let connected: Bool?
    let needsReauth: Bool?
    let status: String?
    let device: String?
    let batteryLevel: Int?
    let batteryStatus: String?
    let lastSyncTime: String?
    let message: String
    let reauthURL: String?

    enum CodingKeys: String, CodingKey {
        case ok, connected, device, message, status
        case needsReauth = "needs_reauth"
        case batteryLevel = "battery_level"
        case batteryStatus = "battery_status"
        case lastSyncTime = "last_sync_time"
        case reauthURL = "reauth_url"
    }
}


struct LiveHeartResponse: Decodable {
    let ok: Bool
    let bpm: Int?
    let measuredAt: String?
    let ageSeconds: Int?
    let stale: Bool
    let needsReauth: Bool?
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, bpm, stale, message
        case measuredAt = "measured_at"
        case ageSeconds = "age_seconds"
        case needsReauth = "needs_reauth"
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
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = (payload?["error"] as? String)
                ?? (payload?["message"] as? String)
                ?? "تعذر الاتصال بالخادم"
            throw NSError(
                domain: "FitbitAir",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
        return try decoder.decode(T.self, from: data)
    }
    func dashboard(date: String? = nil, force: Bool = false) async throws -> Dashboard {
        var parts: [String] = []
        if let date {
            let encoded = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
            parts.append("date=\(encoded)")
        }
        if force { parts.append("force=1") }
        let query = parts.isEmpty ? "" : "?" + parts.joined(separator: "&")
        let r: DashboardResponse = try await request("api/ios/dashboard\(query)")
        return r.dashboard
    }
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
    func insights(force: Bool = false) async throws -> InsightsResponse {
        try await request(force ? "api/ios/insights?force=1" : "api/ios/insights")
    }
    func rebuildAnalytics() async throws -> RebuildAnalyticsResponse {
        try await request("api/ios/analytics/rebuild", method: "POST", body: [:])
    }

    func connectionStatus() async throws -> ConnectionStatusResponse { try await request("api/ios/connection") }
    private func archivePath(_ kind: String, date: String, force: Bool) throws -> String {
        guard let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return "api/ios/health/\(kind)?date=\(encodedDate)" + (force ? "&force=1" : "")
    }

    func healthSummary(date: String, force: Bool = false) async throws -> HealthSummaryResponse {
        try await request(try archivePath("summary", date: date, force: force))
    }

    func healthSleep(date: String, force: Bool = false) async throws -> HealthSleepResponse {
        try await request(try archivePath("sleep", date: date, force: force))
    }

    func healthHeart(date: String, force: Bool = false) async throws -> HealthHeartResponse {
        try await request(try archivePath("heart", date: date, force: force))
    }

    func healthActivity(date: String, force: Bool = false) async throws -> HealthActivityResponse {
        try await request(try archivePath("activity", date: date, force: force))
    }

    func healthReadiness(date: String, force: Bool = false) async throws -> HealthReadinessResponse {
        try await request(try archivePath("readiness", date: date, force: force))
    }

    func deviceStatus(force: Bool = false) async throws -> DeviceStatusResponse {
        try await request(force ? "api/ios/device/status?force=1" : "api/ios/device/status")
    }
    func liveHeart() async throws -> LiveHeartResponse {
        try await request("api/ios/heart/live")
    }


    func healthDay(date: String) async throws -> HealthDayResponse {
        guard let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return try await request("api/ios/health/day?date=\(encodedDate)")
    }

    func saveRefreshToken(_ token: String) async throws -> ConnectionStatusResponse { try await request("api/ios/connection/token", method: "POST", body: ["refresh_token": token]) }
}
