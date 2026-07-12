import Foundation

struct APIEnvelope<T: Decodable>: Decodable { let ok: Bool?; let dashboard: T? }
struct DashboardResponse: Decodable { let ok: Bool; let dashboard: Dashboard }
struct Dashboard: Codable, Equatable {
    let date: String; let steps: Int?; let calories: Int?; let restingHR: Int?; let currentHR: Int?; let currentHRTime: String?; let sleepMinutes: Int?; let readiness: String; let todayPlan: String
    enum CodingKeys: String, CodingKey { case date, steps, calories, readiness; case restingHR = "resting_hr"; case currentHR = "current_hr"; case currentHRTime = "current_hr_time"; case sleepMinutes = "sleep_minutes"; case todayPlan = "today_plan" }
}
struct WorkoutPlanResponse: Decodable { let ok: Bool; let days: [WorkoutDay] }
struct WorkoutDay: Decodable, Identifiable, Hashable { let key: String; let label: String; let exercises: [String]; var id: String { key } }
struct GymSet: Codable, Identifiable, Hashable {
    let id: Int?
    let setNumber: Int
    var reps: Int
    var weight: Double
    var rpe: Int?
    var pain: Bool?
    var note: String?
    enum CodingKeys: String, CodingKey {
        case id, reps, weight, rpe, pain, note
        case setNumber = "set_number"
    }
}
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

struct RebuildAnalyticsResponse: Decodable { let ok: Bool; let message: String; let setsScanned: Int; let prsCreated: Int; enum CodingKeys: String, CodingKey { case ok, message; case setsScanned = "sets_scanned"; case prsCreated = "prs_created" } }


struct BodyProfile: Codable {
    let targetWeight: Double?
    let dailyCalories: Int?
    let proteinGrams: Int?
    let carbGrams: Int?
    let fatGrams: Int?
    enum CodingKeys: String, CodingKey {
        case targetWeight = "target_weight"
        case dailyCalories = "daily_calories"
        case proteinGrams = "protein_grams"
        case carbGrams = "carb_grams"
        case fatGrams = "fat_grams"
    }
}
struct BodyWeightEntry: Codable, Identifiable {
    let id: Int
    let weight: Double
    let loggedAt: String
    enum CodingKeys: String, CodingKey { case id, weight; case loggedAt = "logged_at" }
}
struct BodyMeasurement: Codable, Identifiable {
    let id: Int
    let waistCM: Double?
    let note: String?
    let measuredAt: String
    enum CodingKeys: String, CodingKey { case id, note; case waistCM = "waist_cm"; case measuredAt = "measured_at" }
}
struct StoredBodyAnalysis: Codable, Identifiable {
    let id: Int
    let summary: String
    let waistChange: String?
    let upperBody: String?
    let lowerBody: String?
    let posture: String?
    let estimatedChange: String?
    let confidence: String?
    let notes: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, summary, posture, confidence, notes
        case waistChange = "waist_change"; case upperBody = "upper_body"; case lowerBody = "lower_body"
        case estimatedChange = "estimated_change"; case createdAt = "created_at"
    }
}
struct BodySummaryResponse: Decodable {
    let ok: Bool
    let profile: BodyProfile
    let latestWeight: Double?
    let average7: Double?
    let trend7: Double?
    let remaining: Double?
    let entries: [BodyWeightEntry]
    let latestWaist: Double?
    let measurements: [BodyMeasurement]
    let analyses: [StoredBodyAnalysis]
    enum CodingKeys: String, CodingKey {
        case ok, profile, remaining, entries, measurements, analyses
        case latestWeight = "latest_weight"; case average7 = "average_7"; case trend7 = "trend_7"; case latestWaist = "latest_waist"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        profile = try c.decode(BodyProfile.self, forKey: .profile)
        latestWeight = try c.decodeIfPresent(Double.self, forKey: .latestWeight)
        average7 = try c.decodeIfPresent(Double.self, forKey: .average7)
        trend7 = try c.decodeIfPresent(Double.self, forKey: .trend7)
        remaining = try c.decodeIfPresent(Double.self, forKey: .remaining)
        entries = try c.decodeIfPresent([BodyWeightEntry].self, forKey: .entries) ?? []
        latestWaist = try c.decodeIfPresent(Double.self, forKey: .latestWaist)
        measurements = try c.decodeIfPresent([BodyMeasurement].self, forKey: .measurements) ?? []
        analyses = try c.decodeIfPresent([StoredBodyAnalysis].self, forKey: .analyses) ?? []
    }
}


// MARK: - FitbitAir 2.0 Wellness

struct FA2MacroTotals: Codable, Equatable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}
struct FA2NutritionTargets: Codable, Equatable { let calories: Int?; let protein: Int?; let carbs: Int?; let fat: Int? }
struct FA2NutritionRemaining: Codable, Equatable { let calories: Double?; let protein: Double?; let carbs: Double?; let fat: Double? }
struct FA2FoodLog: Codable, Identifiable, Equatable {
    let id: Int
    let logDate: String
    let mealType: String
    let productID: Int?
    let name: String
    let quantityGrams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let source: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat, source
        case logDate = "log_date"; case mealType = "meal_type"; case productID = "product_id"
        case quantityGrams = "quantity_grams"; case createdAt = "created_at"
    }
}
struct FA2NutritionDay: Codable {
    let ok: Bool
    let date: String
    let totals: FA2MacroTotals
    let targets: FA2NutritionTargets
    let remaining: FA2NutritionRemaining
    let entries: [FA2FoodLog]
    let savedID: Int?
    enum CodingKeys: String, CodingKey { case ok,date,totals,targets,remaining,entries; case savedID = "saved_id" }
}
struct FA2NutritionRange: Codable {
    let ok: Bool
    let days: [FA2NutritionDay]
    let averages: FA2MacroTotals
    let loggedDays: Int
    enum CodingKeys: String, CodingKey { case ok,days,averages; case loggedDays = "logged_days" }
}
struct FA2FoodProduct: Codable, Identifiable, Equatable {
    let id: Int
    let barcode: String?
    let name: String
    let brand: String
    let servingGrams: Double?
    let caloriesPer100: Double
    let proteinPer100: Double
    let carbsPer100: Double
    let fatPer100: Double
    let imageURL: String?
    let source: String
    let favorite: Bool
    enum CodingKeys: String, CodingKey {
        case id,barcode,name,brand,source,favorite
        case servingGrams = "serving_grams"; case caloriesPer100 = "calories_per_100"
        case proteinPer100 = "protein_per_100"; case carbsPer100 = "carbs_per_100"
        case fatPer100 = "fat_per_100"; case imageURL = "image_url"
    }
}
struct FA2ProductsResponse: Codable { let ok: Bool; let products: [FA2FoodProduct] }
struct FA2BarcodeResponse: Codable { let ok: Bool; let found: Bool; let product: FA2FoodProduct?; let barcode: String?; let cached: Bool? }
struct FA2ImageFoodResponse: Codable {
    struct Analysis: Codable {
        struct Item: Codable, Identifiable {
            let name: String; let estimatedGrams: Double?; let calories: Double?; let protein: Double?; let carbs: Double?; let fat: Double?
            var id: String { name + String(estimatedGrams ?? 0) }
            enum CodingKeys: String, CodingKey { case name,calories,protein,carbs,fat; case estimatedGrams = "estimated_grams" }
        }
        let name: String; let brand: String?; let servingGrams: Double?; let caloriesPer100: Double
        let proteinPer100: Double; let carbsPer100: Double; let fatPer100: Double
        let estimatedTotalGrams: Double?; let estimatedTotalCalories: Double?; let items: [Item]?
        let confidence: String?; let notes: String?; let source: String; let mode: String
        enum CodingKeys: String, CodingKey {
            case name,brand,items,confidence,notes,source,mode
            case servingGrams = "serving_grams"; case caloriesPer100 = "calories_per_100"
            case proteinPer100 = "protein_per_100"; case carbsPer100 = "carbs_per_100"
            case fatPer100 = "fat_per_100"; case estimatedTotalGrams = "estimated_total_grams"
            case estimatedTotalCalories = "estimated_total_calories"
        }
    }
    let ok: Bool; let analysis: Analysis
}
struct FA2BodyMeasurement: Codable, Identifiable, Equatable {
    let id: Int; let measureDate: String; let weight: Double?; let waist: Double?; let chest: Double?; let arm: Double?; let thigh: Double?; let note: String?; let createdAt: String
    enum CodingKeys: String, CodingKey { case id,weight,waist,chest,arm,thigh,note; case measureDate = "measure_date"; case createdAt = "created_at" }
}
struct FA2BodyChanges: Codable, Equatable { let weight: Double?; let waist: Double?; let chest: Double?; let arm: Double?; let thigh: Double? }
struct FA2BodyAnalysisRecord: Codable, Identifiable, Equatable {
    let id: Int; let analysisDate: String; let baselineDate: String?; let currentDate: String?; let pose: String?; let summary: String
    let visibleChanges: [String]; let areasImproved: [String]; let areasToFocus: [String]
    let confidence: String?; let photoConsistency: String?; let estimatedBodyFatRange: String?; let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id,pose,summary,confidence; case analysisDate = "analysis_date"; case baselineDate = "baseline_date"; case currentDate = "current_date"
        case visibleChanges = "visible_changes"; case areasImproved = "areas_improved"; case areasToFocus = "areas_to_focus"
        case photoConsistency = "photo_consistency"; case estimatedBodyFatRange = "estimated_body_fat_range"; case createdAt = "created_at"
    }
}
struct FA2BodyProgress: Codable { let ok: Bool; let entries: [FA2BodyMeasurement]; let latest: FA2BodyMeasurement?; let changes: FA2BodyChanges; let analyses: [FA2BodyAnalysisRecord]; let savedID: Int?
    enum CodingKeys: String, CodingKey { case ok,entries,latest,changes,analyses; case savedID = "saved_id" }
}
struct FA2BodyImageResponse: Codable {
    struct Analysis: Codable {
        let id: Int?; let summary: String; let visibleChanges: [String]; let areasImproved: [String]?; let areasToFocus: [String]?
        let confidence: String?; let photoConsistency: String?; let estimatedBodyFatRange: String?
        enum CodingKeys: String, CodingKey { case id,summary,confidence; case visibleChanges = "visible_changes"; case areasImproved = "areas_improved"; case areasToFocus = "areas_to_focus"; case photoConsistency = "photo_consistency"; case estimatedBodyFatRange = "estimated_body_fat_range" }
    }
    let ok: Bool; let analysis: Analysis
}
struct FA2WellnessReport: Codable { let reportType: String; let date: String; let summary: String; let details: String; let createdAt: String?; let cached: Bool?
    enum CodingKeys: String, CodingKey { case date,summary,details,cached; case reportType = "report_type"; case createdAt = "created_at" }
}
struct FA2ReportResponse: Codable { let ok: Bool; let report: FA2WellnessReport }
struct FA2AlternativesResponse: Codable { let ok: Bool; let exercise: String; let alternatives: [String]; let cached: Bool? }
struct FA2SessionResponse: Codable {
    struct Session: Codable { let id: Int; let durationSeconds: Int; let startedAt: String; let endedAt: String
        enum CodingKeys: String, CodingKey { case id; case durationSeconds = "duration_seconds"; case startedAt = "started_at"; case endedAt = "ended_at" }
    }
    let ok: Bool; let session: Session
}


// MARK: - FitbitAir 2.0 API models used by the native wellness screens
struct MacroValues: Codable {
    let calories: Double?; let protein: Double?; let carbs: Double?; let fat: Double?
}
struct NutritionEntry: Codable, Identifiable {
    let id: Int; let entryDate: String; let mealType: String; let name: String
    let calories: Double; let protein: Double; let carbs: Double; let fat: Double; let quantity: Double
    let servingDescription: String?; let source: String; let barcode: String?; let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id,name,calories,protein,carbs,fat,quantity,source,barcode
        case entryDate = "entry_date"; case mealType = "meal_type"; case servingDescription = "serving_description"; case createdAt = "created_at"
    }
}
struct NutritionDayResponse: Codable {
    let ok: Bool; let date: String; let goals: MacroValues; let totals: MacroValues; let remaining: MacroValues
    let entries: [NutritionEntry]; let savedID: Int?
    enum CodingKeys: String, CodingKey { case ok,date,goals,totals,remaining,entries; case savedID = "saved_id" }
}
struct FoodProduct: Codable {
    let barcode: String; let name: String; let brand: String?; let servingSize: String?; let servingGrams: Double?
    let calories: Double; let protein: Double; let carbs: Double; let fat: Double
    let imageURL: String?; let source: String; let per100g: Bool?
    enum CodingKeys: String, CodingKey {
        case barcode,name,brand,calories,protein,carbs,fat,source
        case servingSize = "serving_size"; case servingGrams = "serving_grams"
        case imageURL = "image_url"; case per100g = "per_100g"
    }
}
struct ProductLookupResponse: Codable { let ok: Bool; let found: Bool; let product: FoodProduct?; let message: String?; let cached: Bool? }
struct FoodImageAnalysis: Codable {
    let name: String; let mealType: String; let servingDescription: String?; let quantityGrams: Double
    let calories: Double; let protein: Double; let carbs: Double; let fat: Double; let confidence: String; let notes: String
    enum CodingKeys: String, CodingKey {
        case name,calories,protein,carbs,fat,confidence,notes
        case mealType = "meal_type"; case servingDescription = "serving_description"; case quantityGrams = "quantity_grams"
    }
}
struct FoodImageResponse: Codable { let ok: Bool; let analysis: FoodImageAnalysis }
struct BodyProgressAnalysis: Codable {
    let id: Int?; let summary: String; let waistChange: String; let upperBody: String; let lowerBody: String
    let posture: String; let estimatedChange: String; let confidence: String; let notes: String; let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id,summary,posture,confidence,notes
        case waistChange = "waist_change"; case upperBody = "upper_body"; case lowerBody = "lower_body"
        case estimatedChange = "estimated_change"; case createdAt = "created_at"
    }
}
struct BodyProgressResponse: Codable { let ok: Bool; let analysis: BodyProgressAnalysis }
struct DailyBriefResponse: Codable {
    let ok: Bool; let headline: String; let summary: String; let workoutRecommendation: String; let nutritionRecommendation: String
    let recoveryScore: Int; let remainingCalories: Double?; let remainingProtein: Double?; let latestWeight: Double?
    enum CodingKeys: String, CodingKey {
        case ok,headline,summary
        case workoutRecommendation = "workout_recommendation"; case nutritionRecommendation = "nutrition_recommendation"
        case recoveryScore = "recovery_score"; case remainingCalories = "remaining_calories"
        case remainingProtein = "remaining_protein"; case latestWeight = "latest_weight"
    }
}
struct TextResponse: Codable { let ok: Bool; let text: String }
