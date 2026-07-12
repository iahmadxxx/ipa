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

struct TokenServiceStatus: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String
    let message: String
    let updatedAt: String?
    let canAutoRefresh: Bool
    let externalActionRequired: Bool
    let renewalMode: String

    enum CodingKeys: String, CodingKey {
        case id, name, status, message
        case updatedAt = "updated_at"
        case canAutoRefresh = "can_auto_refresh"
        case externalActionRequired = "external_action_required"
        case renewalMode = "renewal_mode"
    }
}

struct TokenCenterResponse: Decodable {
    let ok: Bool
    let checkedAt: String
    let needsGoogleReauth: Bool
    let reauthURL: String
    let summary: String
    let services: [TokenServiceStatus]

    enum CodingKeys: String, CodingKey {
        case ok, summary, services
        case checkedAt = "checked_at"
        case needsGoogleReauth = "needs_google_reauth"
        case reauthURL = "reauth_url"
    }
}

struct HealthDayResponse: Decodable {
    let ok: Bool
    let dashboard: Dashboard
    let sleep: SleepDetails?
}

struct SleepStageInterval: Codable, Identifiable, Hashable {
    let type: String
    let start: String
    let end: String
    let durationMinutes: Int

    var id: String {
        "\(type)|\(start)|\(end)"
    }

    enum CodingKeys: String, CodingKey {
        case type, start, end
        case durationMinutes = "duration_minutes"
    }
}

struct SleepDetails: Codable {
    let start: String?
    let end: String?
    let totalMinutes: Int?
    let deepMinutes: Int
    let lightMinutes: Int
    let remMinutes: Int
    let awakeMinutes: Int
    let stages: [SleepStageInterval]?

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case totalMinutes = "total_minutes"
        case deepMinutes = "deep_minutes"
        case lightMinutes = "light_minutes"
        case remMinutes = "rem_minutes"
        case awakeMinutes = "awake_minutes"
        case stages
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
    let status: String
    let connected: Bool
    let needsReauth: Bool
    let device: String?
    let batteryLevel: Int?
    let batteryStatus: String?
    let lastSyncTime: String?
    let message: String
    let reauthURL: String?

    enum CodingKeys: String, CodingKey {
        case ok, status, connected, device, message
        case needsReauth = "needs_reauth"
        case batteryLevel = "battery_level"
        case batteryStatus = "battery_status"
        case lastSyncTime = "last_sync_time"
        case reauthURL = "reauth_url"
    }
}

struct LiveHeartResponse: Codable {
    let ok: Bool
    let status: String
    let bpm: Int?
    let measuredAt: String?
    let ageSeconds: Int?
    let stale: Bool
    let needsReauth: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok, status, bpm, stale, message
        case measuredAt = "measured_at"
        case ageSeconds = "age_seconds"
        case needsReauth = "needs_reauth"
    }
}

struct DiagnosticsResponse: Decodable {
    struct Service: Decodable {
        let status: String
        let message: String
        let batteryLevel: Int?
        let lastSyncTime: String?
        let bpm: Int?
        let measuredAt: String?
        let ageSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case status, message, bpm
            case batteryLevel = "battery_level"
            case lastSyncTime = "last_sync_time"
            case measuredAt = "measured_at"
            case ageSeconds = "age_seconds"
        }
    }

    let ok: Bool
    let railway: Service
    let token: Service
    let device: Service
    let heart: Service
    let checkedAt: String

    enum CodingKeys: String, CodingKey {
        case ok, railway, token, device, heart
        case checkedAt = "checked_at"
    }
}


actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 30) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.baseURL)?.absoluteURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url); req.httpMethod = method; req.timeoutInterval = timeout
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
    func bodySummary() async throws -> BodySummaryResponse { try await request("api/ios/body") }
    func addBodyWeight(_ weight: Double) async throws -> BodySummaryResponse { try await request("api/ios/body/weight", method: "POST", body: ["weight": weight]) }
    func deleteBodyWeight(id: Int) async throws -> BodySummaryResponse { try await request("api/ios/body/weight/delete", method: "POST", body: ["id": id]) }
    func saveBodyProfile(targetWeight: Double?, dailyCalories: Int?, proteinGrams: Int?, carbGrams: Int? = nil, fatGrams: Int? = nil) async throws -> BodySummaryResponse {
        var body: [String: Any] = [:]
        if let targetWeight { body["target_weight"] = targetWeight }
        if let dailyCalories { body["daily_calories"] = dailyCalories }
        if let proteinGrams { body["protein_grams"] = proteinGrams }
        if let carbGrams { body["carb_grams"] = carbGrams }
        if let fatGrams { body["fat_grams"] = fatGrams }
        return try await request("api/ios/body/profile", method: "POST", body: body)
    }
    func addWaist(_ waistCM: Double, note: String = "") async throws -> BodySummaryResponse {
        _ = try await fa2SaveMeasurement(date: Self.todayString(), weight: nil, waist: waistCM, chest: nil, arm: nil, thigh: nil, note: note)
        return try await bodySummary()
    }
    func plan() async throws -> [WorkoutDay] { let r: WorkoutPlanResponse = try await request("api/ios/plan"); return r.days }
    func workoutContext(day: String, idx: Int) async throws -> WorkoutContext { try await request("api/ios/workout/context?day=\(day)&idx=\(idx)") }
    func saveSet(day: String, idx: Int, reps: Int, weight: Double, rpe: Int? = nil, pain: Bool = false, note: String = "") async throws -> SaveSetResponse {
        var body: [String: Any] = ["day":day,"idx":idx,"reps":reps,"weight":weight,"pain":pain,"note":note]
        if let rpe { body["rpe"] = rpe }
        return try await request("api/ios/workout/set", method: "POST", body: body)
    }
    func editTodaySet(day: String, idx: Int, id: Int?, set: Int, reps: Int, weight: Double, rpe: Int? = nil, pain: Bool? = nil, note: String? = nil) async throws -> SaveSetResponse {
        var body: [String: Any] = ["day": day, "idx": idx, "set_number": set, "reps": reps, "weight": weight]
        if let id { body["id"] = id }
        if let rpe { body["rpe"] = rpe }
        if let pain { body["pain"] = pain }
        if let note { body["note"] = note }
        return try await request("api/ios/workout/edit", method: "POST", body: body)
    }
    func addExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/add", method: "POST", body: ["day":day,"name":name]) }
    func deleteExercise(day: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/delete", method: "POST", body: ["day":day,"name":name]) }
    func renameExercise(day: String, oldName: String, newName: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/rename", method: "POST", body: ["day":day,"old_name":oldName,"new_name":newName]) }
    func reorderExercises(day: String, exercises: [String]) async throws { let _: SimpleResponse = try await request("api/ios/exercise/reorder", method: "POST", body: ["day":day,"exercises":exercises]) }
    func moveExercise(sourceDay: String, targetDay: String, name: String) async throws { let _: SimpleResponse = try await request("api/ios/exercise/move", method: "POST", body: ["source_day":sourceDay,"target_day":targetDay,"name":name]) }
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
    func tokenCenterStatus() async throws -> TokenCenterResponse {
        try await request("api/ios/tokens/status")
    }
    func refreshAllTokens() async throws -> TokenCenterResponse {
        try await request("api/ios/tokens/refresh-all", method: "POST", body: [:])
    }
    func saveGeminiAPIKey(_ apiKey: String) async throws -> TokenCenterResponse {
        try await request("api/ios/tokens/gemini", method: "POST", body: ["api_key": apiKey])
    }
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

    func diagnostics() async throws -> DiagnosticsResponse {
        try await request("api/ios/diagnostics")
    }


    func healthDay(date: String) async throws -> HealthDayResponse {
        guard let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return try await request("api/ios/health/day?date=\(encodedDate)")
    }


    // MARK: - FitbitAir 2.0 Wellness
    func fa2NutritionDay(date: String? = nil) async throws -> FA2NutritionDay {
        let q = date.map { "?date=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0) } ?? ""
        return try await request("api/ios/nutrition/day\(q)")
    }
    func fa2NutritionRange(days: Int = 7) async throws -> FA2NutritionRange { try await request("api/ios/nutrition/range?days=\(days)") }
    func fa2Products(query: String = "", favorites: Bool = false) async throws -> [FA2FoodProduct] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: FA2ProductsResponse = try await request("api/ios/nutrition/products?q=\(q)&favorites=\(favorites ? 1 : 0)")
        return r.products
    }
    func fa2LookupBarcode(_ code: String) async throws -> FA2BarcodeResponse {
        let value = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return try await request("api/ios/nutrition/product/barcode?code=\(value)")
    }
    func fa2LogFood(productID: Int? = nil, product: [String: Any]? = nil, grams: Double, meal: String, date: String? = nil) async throws -> FA2NutritionDay {
        var body: [String: Any] = ["quantity_grams": grams, "meal_type": meal]
        if let productID { body["product_id"] = productID }
        if let product { body["product"] = product }
        if let date { body["date"] = date }
        return try await request("api/ios/nutrition/log", method: "POST", body: body)
    }
    func fa2DeleteFood(id: Int) async throws -> FA2NutritionDay { try await request("api/ios/nutrition/log/delete", method: "POST", body: ["id":id]) }
    func fa2FavoriteProduct(id: Int, favorite: Bool) async throws { let _: SimpleResponse = try await request("api/ios/nutrition/product/favorite", method: "POST", body: ["id":id,"favorite":favorite]) }
    func fa2AnalyzeFoodImage(base64: String, mode: String) async throws -> FA2ImageFoodResponse {
        try await request("api/ios/nutrition/analyze-image", method: "POST", body: ["image_base64":base64,"mime_type":"image/jpeg","mode":mode], timeout: 90)
    }
    func fa2BodyProgress() async throws -> FA2BodyProgress { try await request("api/ios/body/progress") }
    func fa2SaveMeasurement(date: String, weight: Double?, waist: Double?, chest: Double?, arm: Double?, thigh: Double?, note: String) async throws -> FA2BodyProgress {
        var body: [String: Any] = ["date":date,"note":note]
        if let weight { body["weight"] = weight }; if let waist { body["waist"] = waist }; if let chest { body["chest"] = chest }; if let arm { body["arm"] = arm }; if let thigh { body["thigh"] = thigh }
        return try await request("api/ios/body/measurement", method: "POST", body: body)
    }
    func fa2AnalyzeBody(baseline: String, current: String, pose: String, baselineDate: String, currentDate: String) async throws -> FA2BodyImageResponse {
        try await request("api/ios/body/analyze", method: "POST", body: ["baseline_image_base64":baseline,"current_image_base64":current,"pose":pose,"baseline_date":baselineDate,"current_date":currentDate], timeout: 120)
    }
    func fa2Report(kind: String, force: Bool = false) async throws -> FA2WellnessReport {
        let r: FA2ReportResponse = try await request("api/ios/reports/\(kind)\(force ? "?force=1" : "")", timeout: 60)
        return r.report
    }
    func fa2Alternatives(exercise: String) async throws -> [String] {
        let e = exercise.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? exercise
        let r: FA2AlternativesResponse = try await request("api/ios/workout/alternatives?exercise=\(e)", timeout: 60)
        return r.alternatives
    }
    func fa2LogSession(dayKey: String, seconds: Int, effort: Int?, note: String) async throws -> FA2SessionResponse {
        var body: [String: Any] = ["day_key":dayKey,"duration_seconds":seconds,"note":note]
        if let effort { body["effort"] = effort }
        return try await request("api/ios/workout/session", method: "POST", body: body)
    }

    // MARK: - Native wellness-screen compatibility
    private static func todayString() -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Qatar")
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func nativeNutrition(_ value: FA2NutritionDay) -> NutritionDayResponse {
        let entries = value.entries.map { item in
            NutritionEntry(
                id: item.id, entryDate: item.logDate, mealType: item.mealType, name: item.name,
                calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat,
                quantity: item.quantityGrams, servingDescription: "\(item.quantityGrams.formatted(.number.precision(.fractionLength(0...1)))) غ",
                source: item.source, barcode: nil, createdAt: item.createdAt
            )
        }
        return NutritionDayResponse(
            ok: value.ok, date: value.date,
            goals: MacroValues(calories: value.targets.calories.map { Double($0) }, protein: value.targets.protein.map { Double($0) }, carbs: value.targets.carbs.map { Double($0) }, fat: value.targets.fat.map { Double($0) }),
            totals: MacroValues(calories: value.totals.calories, protein: value.totals.protein, carbs: value.totals.carbs, fat: value.totals.fat),
            remaining: MacroValues(calories: value.remaining.calories, protein: value.remaining.protein, carbs: value.remaining.carbs, fat: value.remaining.fat),
            entries: entries, savedID: value.savedID
        )
    }

    func nutritionDay(date: String? = nil) async throws -> NutritionDayResponse {
        nativeNutrition(try await fa2NutritionDay(date: date))
    }

    func addNutritionEntry(
        date: String? = nil, mealType: String, name: String, calories: Double,
        protein: Double, carbs: Double, fat: Double, quantity: Double = 100,
        servingDescription: String? = nil, source: String = "manual", barcode: String? = nil
    ) async throws -> NutritionDayResponse {
        let grams = max(1, min(5000, quantity))
        let toPer100 = 100 / grams
        var product: [String: Any] = [
            "name": name, "brand": "", "calories_per_100": max(0, calories) * toPer100,
            "protein_per_100": max(0, protein) * toPer100,
            "carbs_per_100": max(0, carbs) * toPer100,
            "fat_per_100": max(0, fat) * toPer100,
            "serving_grams": grams, "source": source
        ]
        if let barcode { product["barcode"] = barcode }
        return nativeNutrition(try await fa2LogFood(product: product, grams: grams, meal: mealType, date: date))
    }

    func deleteNutritionEntry(id: Int) async throws -> NutritionDayResponse { nativeNutrition(try await fa2DeleteFood(id: id)) }

    func lookupBarcode(_ code: String) async throws -> ProductLookupResponse {
        let value = try await fa2LookupBarcode(code)
        let product = value.product.map { item in
            FoodProduct(
                barcode: item.barcode ?? code, name: item.name, brand: item.brand,
                servingSize: item.servingGrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) غ" },
                servingGrams: item.servingGrams,
                calories: item.caloriesPer100, protein: item.proteinPer100, carbs: item.carbsPer100, fat: item.fatPer100,
                imageURL: item.imageURL, source: item.source, per100g: true
            )
        }
        return ProductLookupResponse(ok: value.ok, found: value.found, product: product, message: value.found ? nil : "المنتج غير موجود؛ صوّر جدول القيم الغذائية", cached: value.cached)
    }

    func analyzeFoodImage(_ imageBase64: String, mode: String) async throws -> FoodImageResponse {
        let value = try await fa2AnalyzeFoodImage(base64: imageBase64, mode: mode)
        let a = value.analysis
        let grams = mode == "meal" ? max(1, a.estimatedTotalGrams ?? a.servingGrams ?? 100) : 100
        let factor = grams / 100
        let result = FoodImageAnalysis(
            name: a.name, mealType: mode == "meal" ? "lunch" : "snack",
            servingDescription: mode == "meal" ? "تقدير بصري: \(grams.formatted(.number.precision(.fractionLength(0...0)))) غ" : "القيم لكل 100 غ",
            quantityGrams: grams,
            calories: a.estimatedTotalCalories ?? (a.caloriesPer100 * factor),
            protein: a.proteinPer100 * factor, carbs: a.carbsPer100 * factor, fat: a.fatPer100 * factor,
            confidence: a.confidence ?? "متوسط", notes: a.notes ?? "راجع القيم قبل الحفظ"
        )
        return FoodImageResponse(ok: value.ok, analysis: result)
    }

    func analyzeBodyProgress(_ images: [[String: String]]) async throws -> BodyProgressResponse {
        guard let firstItem = images.first, let lastItem = images.last,
              let first = firstItem["data"], let last = lastItem["data"], images.count >= 2 else {
            throw NSError(domain: "FitbitAir", code: 400, userInfo: [NSLocalizedDescriptionKey: "اختر صورتين على الأقل"])
        }
        let pose = firstItem["pose"] ?? "front"
        let baselineDate = firstItem["date"] ?? Self.todayString()
        let currentDate = lastItem["date"] ?? Self.todayString()
        let value = try await fa2AnalyzeBody(baseline: first, current: last, pose: pose, baselineDate: baselineDate, currentDate: currentDate)
        let a = value.analysis
        let changes = a.visibleChanges.joined(separator: "، ")
        let result = BodyProgressAnalysis(
            id: a.id, summary: a.summary, waistChange: changes,
            upperBody: (a.areasImproved ?? []).joined(separator: "، "),
            lowerBody: (a.areasToFocus ?? []).joined(separator: "، "),
            posture: a.photoConsistency ?? "", estimatedChange: a.estimatedBodyFatRange ?? "",
            confidence: a.confidence ?? "متوسط",
            notes: "تحليل بصري تقديري. لتحسين الدقة استخدم نفس الإضاءة والمسافة والوضعية.", createdAt: nil
        )
        return BodyProgressResponse(ok: value.ok, analysis: result)
    }

    func saveWorkoutSession(dayKey: String, durationSeconds: Int, startedAt: String?) async throws {
        _ = try await fa2LogSession(dayKey: dayKey, seconds: durationSeconds, effort: nil, note: "")
    }

    func workoutAlternatives(exercise: String) async throws -> String {
        try await fa2Alternatives(exercise: exercise).joined(separator: "\n")
    }

    private static func readinessScore(from text: String?) -> Int {
        guard let text else { return 75 }
        let values = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        return min(100, max(0, values.first(where: { (0...100).contains($0) }) ?? 75))
    }

    func dailyBrief() async throws -> DailyBriefResponse {
        let report = try await fa2Report(kind: "daily")
        let dashboardValue = try? await dashboard()
        let nutrition = try? await fa2NutritionDay()
        let body = try? await bodySummary()
        let score = Self.readinessScore(from: dashboardValue?.readiness)

        var nutritionParts: [String] = []
        if let protein = nutrition?.remaining.protein {
            nutritionParts.append(protein > 0 ? "باقي لك \(protein.formatted(.number.precision(.fractionLength(0...1)))) غ بروتين" : "وصلت هدف البروتين")
        }
        if let calories = nutrition?.remaining.calories {
            nutritionParts.append(calories > 0 ? "باقي \(calories.formatted(.number.precision(.fractionLength(0...0)))) سعرة" : "وصلت هدف السعرات")
        }
        let nutritionText = nutritionParts.isEmpty
            ? "سجّل وجباتك اليوم ليحسب المدرب المتبقي من أهدافك."
            : nutritionParts.joined(separator: " • ")
        let headline: String
        switch score {
        case 85...: headline = "جاهزيتك ممتازة"
        case 70..<85: headline = "جاهزيتك جيدة"
        case 50..<70: headline = "تمرّن بهدوء اليوم"
        default: headline = "الأولوية للتعافي"
        }

        return DailyBriefResponse(
            ok: true, headline: headline, summary: report.summary,
            workoutRecommendation: report.details.isEmpty ? (dashboardValue?.todayPlan ?? "راجع تمرين اليوم") : report.details,
            nutritionRecommendation: nutritionText,
            recoveryScore: score,
            remainingCalories: nutrition?.remaining.calories,
            remainingProtein: nutrition?.remaining.protein,
            latestWeight: body?.latestWeight
        )
    }

    func saveRefreshToken(_ token: String) async throws -> ConnectionStatusResponse { try await request("api/ios/connection/token", method: "POST", body: ["refresh_token": token]) }
}
