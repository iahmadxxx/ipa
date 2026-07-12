import SwiftUI
import CoreLocation
import UIKit

// MARK: - Activity catalog

struct ActivityDefinition: Identifiable, Codable, Hashable {
    let officialType: String
    let nameAR: String
    let nameEN: String
    let icon: String
    let category: ActivityCategory
    let tracksGPS: Bool

    var id: String { officialType }
}

enum ActivityCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case all, popular, cardio, strength, sports, outdoors, water, mindBody, winter, daily, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "الكل"
        case .popular: return "الأكثر استخدامًا"
        case .cardio: return "كارديو"
        case .strength: return "قوة"
        case .sports: return "رياضات"
        case .outdoors: return "خارجية"
        case .water: return "مائية"
        case .mindBody: return "مرونة وهدوء"
        case .winter: return "شتوية"
        case .daily: return "نشاط يومي"
        case .other: return "أخرى"
        }
    }
}

enum ActivityCatalog {
    static let officialTypes: [String] = [
        "AEROBIC_WORKOUT","ARCHERY","ASSAULT_BIKE","BACKPACKING","BADMINTON","BALLET","BALLROOM_DANCE","BARRE_CLASS","BASEBALL","BASKETBALL","BIKING","BILLIARDS","BODY_WEIGHT","BOOTCAMP","BOWLING","BOXING","BREAKDANCING","CALISTHENICS","CANOEING","CARDIO_SCULPT","CARDIO_WORKOUT","CARPENTRY","CHEERLEADING","CIRCUIT_TRAINING","CLEANING","CLIMBING","CORE_TRAINING","CRICKET","CROQUET","CROSS_COUNTRY_SKI","CROSS_TRAINING","CROSSFIT","CURLING","DANCING","DIVING","ELECTRIC_BIKE","ELECTRIC_SCOOTER","ELLIPTICAL","EQUESTRIAN_SPORTS","EXERCISE_CLASS","FENCING","FIELD_HOCKEY","FISHING","FITNESS_GAMING","FOILING","FOOTBALL_AMERICAN","FOOTBALL_AUSTRALIAN","FREE_WEIGHTS","FRISBEE_PLAYING_GENERAL","FUNCTIONAL_STRENGTH_TRAINING","GARDENING","GOLF","GYMNASTICS","HANDBALL","HAND_CYCLING","HIIT","HIKING","HIP_HOP","HOCKEY","HOEING","HOUSEHOLD_CHORES","HUNTING","ICE_SKATING","INCLINE_RUN","INCLINE_WALK","INDOOR_CLIMBING","INTERVAL_WORKOUT","JAZZ_DANCE","JIU_JITSU","JUMPING_ROPE","KARATE","KAYAKING","KICKBOXING","KITESURFING","LACROSSE","MARTIAL_ARTS","MEDITATE","MODERN_DANCE","MOTOCROSS","MOTORCYCLE","MOUNTAIN_BIKE","MOWING_LAWN","MUAY_THAI","MULTISPORT","MUSICAL_PERFORMANCE","NORDIC_WALKING","ORIENTEERING","OTHER","OUTDOOR_BIKE","OUTDOOR_WORKOUT","PADDLEBOARDING","PADEL","PAINTING","PARAGLIDING","PARKOUR","PICKELBALL","PILATES","POLO","POWERLIFTING","POWER_WALKING","RACKET_SPORTS","RACQUETBALL","RESISTANCE_BANDS","ROCK_CLIMBING","ROLLERBLADING","ROLLER_SKATING","ROWING","ROWING_MACHINE","RUCKING","RUGBY","RUNNING","SAILING","SCOOTERING","SCUBA_DIVING","SHOOTING","SHOVELING","SKATEBOARDING","SKATING","SKIING","SKYDIVING","SNORKELING","SNOWBOARDING","SNOWMOBILING","SNOWSHOEING","SNOW_SPORT","SOCCER","SOFTBALL","SPEED_SKATING","SPINNING","SPORT","SQUASH","STAIRCLIMBER","STATIONARY_BIKE","STEP_TRAINING","STRENGTH_TRAINING","STRETCHING","STROLLER_WALK","SURFING","SWIMMING","SWIMMING_OPEN_WATER","SWIMMING_POOL","SYNCHRONIZED_SWIMMING","TABATA_WORKOUT","TABLE_TENNIS","TAEKWONDO","TAI_CHI","TANGO","TENNIS","TRACK_AND_FIELD","TRAIL_RUN","TRAMPOLINE","TREADMILL","TREADMILL_WALK","TRX","ULTIMATE_FRISBEE","UNICYCLING","VOLLEYBALL","VOLLEYBALL_BEACH","WAKEBOARDING","WALKING","WALK_WITH_WEIGHTS","WATER_AEROBICS","WATER_JOGGING","WATER_POLO","WATER_SKIING","WATER_SPORT","WATER_VOLLEYBALL","WEEDING","WEIGHTLIFTING","WEIGHT_MACHINES","WEIGHTS","WHEELCHAIR","WINDSURFING","WORKOUT","WRESTLING","YOGA","YOGA_BIKRAM","YOGA_HATHA","YOGA_POWER","YOGA_VINYASA","ZUMBA"
    ]

    private static let arabic: [String: String] = [
        "AEROBIC_WORKOUT":"تمارين هوائية","ARCHERY":"الرماية بالقوس","ASSAULT_BIKE":"دراجة Assault","BACKPACKING":"مشي بحقيبة","BADMINTON":"ريشة طائرة","BALLET":"باليه","BALLROOM_DANCE":"رقص صالونات","BARRE_CLASS":"تمارين بار","BASEBALL":"بيسبول","BASKETBALL":"كرة سلة","BIKING":"دراجة","BILLIARDS":"بلياردو","BODY_WEIGHT":"وزن الجسم","BOOTCAMP":"بوت كامب","BOWLING":"بولينغ","BOXING":"ملاكمة","BREAKDANCING":"بريك دانس","CALISTHENICS":"كاليستنكس","CANOEING":"كانوي","CARDIO_SCULPT":"كارديو ونحت","CARDIO_WORKOUT":"تمرين كارديو","CARPENTRY":"نجارة","CHEERLEADING":"تشجيع رياضي","CIRCUIT_TRAINING":"تمرين دائري","CLEANING":"تنظيف","CLIMBING":"تسلق","CORE_TRAINING":"تمارين الجذع","CRICKET":"كريكيت","CROQUET":"كروكيه","CROSS_COUNTRY_SKI":"تزلج ريفي","CROSS_TRAINING":"تدريب متنوع","CROSSFIT":"كروس فت","CURLING":"كيرلنغ","DANCING":"رقص","DIVING":"غطس","ELECTRIC_BIKE":"دراجة كهربائية","ELECTRIC_SCOOTER":"سكوتر كهربائي","ELLIPTICAL":"إليبتيكال","EQUESTRIAN_SPORTS":"فروسية","EXERCISE_CLASS":"حصة رياضية","FENCING":"مبارزة","FIELD_HOCKEY":"هوكي ميدان","FISHING":"صيد سمك","FITNESS_GAMING":"ألعاب لياقة","FOILING":"فويل مائي","FOOTBALL_AMERICAN":"كرة قدم أمريكية","FOOTBALL_AUSTRALIAN":"كرة قدم أسترالية","FREE_WEIGHTS":"أوزان حرة","FRISBEE_PLAYING_GENERAL":"فريسبي","FUNCTIONAL_STRENGTH_TRAINING":"قوة وظيفية","GARDENING":"بستنة","GOLF":"غولف","GYMNASTICS":"جمباز","HANDBALL":"كرة يد","HAND_CYCLING":"دراجة يدوية","HIIT":"تمرين عالي الشدة","HIKING":"هايكنغ","HIP_HOP":"هيب هوب","HOCKEY":"هوكي","HOEING":"حراثة يدوية","HOUSEHOLD_CHORES":"أعمال منزلية","HUNTING":"صيد بري","ICE_SKATING":"تزلج جليدي","INCLINE_RUN":"ركض مائل","INCLINE_WALK":"مشي مائل","INDOOR_CLIMBING":"تسلق داخلي","INTERVAL_WORKOUT":"تمرين فترات","JAZZ_DANCE":"رقص جاز","JIU_JITSU":"جوجيتسو","JUMPING_ROPE":"نط الحبل","KARATE":"كاراتيه","KAYAKING":"كاياك","KICKBOXING":"كيك بوكسينغ","KITESURFING":"كايت سيرف","LACROSSE":"لاكروس","MARTIAL_ARTS":"فنون قتالية","MEDITATE":"تأمل","MODERN_DANCE":"رقص حديث","MOTOCROSS":"موتوكروس","MOTORCYCLE":"دراجة نارية","MOUNTAIN_BIKE":"دراجة جبلية","MOWING_LAWN":"قص العشب","MUAY_THAI":"مواي تاي","MULTISPORT":"رياضات متعددة","MUSICAL_PERFORMANCE":"أداء موسيقي","NORDIC_WALKING":"مشي نورديك","ORIENTEERING":"توجيه ميداني","OTHER":"نشاط آخر","OUTDOOR_BIKE":"دراجة خارجية","OUTDOOR_WORKOUT":"تمرين خارجي","PADDLEBOARDING":"بادل بورد","PADEL":"بادل","PAINTING":"دهان","PARAGLIDING":"طيران شراعي","PARKOUR":"باركور","PICKELBALL":"بيكل بول","PILATES":"بيلاتس","POLO":"بولو","POWERLIFTING":"باور لفتنغ","POWER_WALKING":"مشي سريع","RACKET_SPORTS":"رياضات مضرب","RACQUETBALL":"راكيت بول","RESISTANCE_BANDS":"أشرطة مقاومة","ROCK_CLIMBING":"تسلق صخور","ROLLERBLADING":"رولر بليد","ROLLER_SKATING":"تزلج بعجلات","ROWING":"تجديف","ROWING_MACHINE":"جهاز تجديف","RUCKING":"مشي بحمل","RUGBY":"رغبي","RUNNING":"ركض","SAILING":"إبحار","SCOOTERING":"سكوتر","SCUBA_DIVING":"غوص سكوبا","SHOOTING":"رماية","SHOVELING":"تجريف","SKATEBOARDING":"سكيت بورد","SKATING":"تزلج","SKIING":"تزلج","SKYDIVING":"قفز مظلي","SNORKELING":"سنوركل","SNOWBOARDING":"سنوبورد","SNOWMOBILING":"دراجة ثلجية","SNOWSHOEING":"مشي ثلجي","SNOW_SPORT":"رياضة ثلجية","SOCCER":"كرة قدم","SOFTBALL":"سوفت بول","SPEED_SKATING":"تزلج سريع","SPINNING":"سبيننغ","SPORT":"رياضة","SQUASH":"سكواش","STAIRCLIMBER":"جهاز الدرج","STATIONARY_BIKE":"دراجة ثابتة","STEP_TRAINING":"تمارين ستيب","STRENGTH_TRAINING":"تمرين قوة","STRETCHING":"إطالات","STROLLER_WALK":"مشي بعربة","SURFING":"ركوب الأمواج","SWIMMING":"سباحة","SWIMMING_OPEN_WATER":"سباحة مياه مفتوحة","SWIMMING_POOL":"سباحة مسبح","SYNCHRONIZED_SWIMMING":"سباحة إيقاعية","TABATA_WORKOUT":"تاباتا","TABLE_TENNIS":"تنس طاولة","TAEKWONDO":"تايكوندو","TAI_CHI":"تاي تشي","TANGO":"تانغو","TENNIS":"تنس","TRACK_AND_FIELD":"ألعاب قوى","TRAIL_RUN":"ركض مسارات","TRAMPOLINE":"ترامبولين","TREADMILL":"جهاز مشي/ركض","TREADMILL_WALK":"مشي على السير","TRX":"TRX","ULTIMATE_FRISBEE":"ألتيميت فريسبي","UNICYCLING":"دراجة بعجلة واحدة","VOLLEYBALL":"كرة طائرة","VOLLEYBALL_BEACH":"طائرة شاطئية","WAKEBOARDING":"ويك بورد","WALKING":"مشي","WALK_WITH_WEIGHTS":"مشي بأوزان","WATER_AEROBICS":"أيروبكس مائي","WATER_JOGGING":"ركض مائي","WATER_POLO":"كرة ماء","WATER_SKIING":"تزلج مائي","WATER_SPORT":"رياضة مائية","WATER_VOLLEYBALL":"طائرة مائية","WEEDING":"إزالة أعشاب","WEIGHTLIFTING":"رفع أثقال","WEIGHT_MACHINES":"أجهزة أوزان","WEIGHTS":"أوزان","WHEELCHAIR":"كرسي متحرك","WINDSURFING":"ويند سيرف","WORKOUT":"تمرين عام","WRESTLING":"مصارعة","YOGA":"يوغا","YOGA_BIKRAM":"يوغا بيكرام","YOGA_HATHA":"هاثا يوغا","YOGA_POWER":"باور يوغا","YOGA_VINYASA":"فينياسا يوغا","ZUMBA":"زومبا"
    ]

    private static let popularTypes: Set<String> = ["RUNNING","WALKING","OUTDOOR_BIKE","BIKING","TREADMILL","STATIONARY_BIKE","ELLIPTICAL","SWIMMING","PADEL","SOCCER","HIIT","CROSSFIT","ROWING_MACHINE","STAIRCLIMBER","YOGA","HIKING","BOXING"]
    private static let gpsTypes: Set<String> = ["RUNNING","WALKING","POWER_WALKING","NORDIC_WALKING","STROLLER_WALK","WALK_WITH_WEIGHTS","INCLINE_RUN","INCLINE_WALK","TRAIL_RUN","HIKING","BACKPACKING","RUCKING","BIKING","OUTDOOR_BIKE","MOUNTAIN_BIKE","ELECTRIC_BIKE","HAND_CYCLING","ROWING","CANOEING","KAYAKING","PADDLEBOARDING","SAILING","SURFING","KITESURFING","WINDSURFING","WAKEBOARDING","WATER_SKIING","SWIMMING_OPEN_WATER","SKIING","CROSS_COUNTRY_SKI","SNOWBOARDING","SNOWSHOEING","ROLLERBLADING","ROLLER_SKATING","SKATEBOARDING","SCOOTERING","ORIENTEERING"]

    static let all: [ActivityDefinition] = officialTypes.map { type in
        ActivityDefinition(
            officialType: type,
            nameAR: arabic[type] ?? humanName(type),
            nameEN: humanName(type),
            icon: icon(for: type),
            category: category(for: type),
            tracksGPS: gpsTypes.contains(type)
        )
    }

    static var popular: [ActivityDefinition] { all.filter { popularTypes.contains($0.officialType) } }

    static func humanName(_ type: String) -> String {
        type.lowercased().split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    static func icon(for type: String) -> String {
        if type.contains("RUN") { return "figure.run" }
        if type.contains("WALK") || type == "HIKING" { return "figure.walk" }
        if type.contains("BIKE") || type == "BIKING" || type == "SPINNING" { return "bicycle" }
        if type.contains("SWIM") || type.contains("WATER") || type == "DIVING" || type == "SNORKELING" { return "figure.pool.swim" }
        if type.contains("ROW") || type == "CANOEING" || type == "KAYAKING" { return "figure.rower" }
        if type.contains("YOGA") || type == "PILATES" || type == "MEDITATE" || type == "STRETCHING" { return "figure.mind.and.body" }
        if type.contains("WEIGHT") || type.contains("STRENGTH") || type == "POWERLIFTING" || type == "FREE_WEIGHTS" { return "dumbbell.fill" }
        if type == "SOCCER" || type.contains("FOOTBALL") { return "soccerball" }
        if type == "BASKETBALL" { return "basketball.fill" }
        if type == "TENNIS" || type == "PADEL" || type.contains("RACKET") || type == "SQUASH" { return "tennis.racket" }
        if type.contains("BOX") || type.contains("MARTIAL") || type == "KARATE" || type == "TAEKWONDO" || type == "WRESTLING" { return "figure.martial.arts" }
        if type.contains("SKI") || type.contains("SNOW") || type == "ICE_SKATING" { return "snowflake" }
        if type.contains("DANCE") || type == "ZUMBA" || type == "BALLET" || type == "TANGO" { return "figure.dance" }
        if type.contains("CLIMB") { return "figure.climbing" }
        if type == "GOLF" { return "figure.golf" }
        return "figure.mixed.cardio"
    }

    static func category(for type: String) -> ActivityCategory {
        if type.contains("WEIGHT") || type.contains("STRENGTH") || ["POWERLIFTING","FREE_WEIGHTS","BODY_WEIGHT","CALISTHENICS","RESISTANCE_BANDS","TRX"].contains(type) { return .strength }
        if type.contains("SWIM") || type.contains("WATER") || ["DIVING","SCUBA_DIVING","SNORKELING","SURFING","KAYAKING","CANOEING","ROWING","SAILING","PADDLEBOARDING","KITESURFING","WINDSURFING","WAKEBOARDING"].contains(type) { return .water }
        if type.contains("SKI") || type.contains("SNOW") || type.contains("SKAT") || type == "CURLING" { return .winter }
        if type.contains("YOGA") || ["PILATES","MEDITATE","STRETCHING","TAI_CHI","BARRE_CLASS"].contains(type) { return .mindBody }
        if ["CLEANING","CARPENTRY","GARDENING","HOEING","HOUSEHOLD_CHORES","MOWING_LAWN","PAINTING","SHOVELING","WEEDING"].contains(type) { return .daily }
        if gpsTypes.contains(type) { return .outdoors }
        if type.contains("WORKOUT") || ["HIIT","ELLIPTICAL","STAIRCLIMBER","STATIONARY_BIKE","TREADMILL","JUMPING_ROPE","SPINNING","AEROBIC_WORKOUT","CARDIO_SCULPT","CARDIO_WORKOUT","CIRCUIT_TRAINING","INTERVAL_WORKOUT","TABATA_WORKOUT","BOOTCAMP"].contains(type) { return .cardio }
        if ["OTHER","SPORT","MULTISPORT","WORKOUT","EXERCISE_CLASS"].contains(type) { return .other }
        return .sports
    }
}

// MARK: - API models

struct ActivitySessionRecord: Codable, Identifiable, Hashable {
    let id: Int
    let clientID: String?
    let source: String
    let exerciseType: String
    let displayName: String
    let startTime: String
    let endTime: String
    let durationSeconds: Int
    let activeSeconds: Int
    let distanceMeters: Double?
    let calories: Double?
    let steps: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let averageSpeedMPS: Double?
    let elevationGainMeters: Double?
    let activeZoneMinutes: Int?
    let hasGPS: Bool
    let notes: String?
    let rpe: Int?
    let syncStatus: String
    let syncError: String?

    enum CodingKeys: String, CodingKey {
        case id, source, calories, steps, notes, rpe
        case clientID = "client_id"; case exerciseType = "exercise_type"; case displayName = "display_name"
        case startTime = "start_time"; case endTime = "end_time"; case durationSeconds = "duration_seconds"
        case activeSeconds = "active_seconds"; case distanceMeters = "distance_meters"
        case averageHeartRate = "average_heart_rate"; case maximumHeartRate = "maximum_heart_rate"
        case averageSpeedMPS = "average_speed_mps"; case elevationGainMeters = "elevation_gain_meters"
        case activeZoneMinutes = "active_zone_minutes"; case hasGPS = "has_gps"
        case syncStatus = "sync_status"; case syncError = "sync_error"
    }
}

struct ActivitySummary: Codable, Hashable {
    let days: Int
    let sessions: Int
    let activeSeconds: Int
    let distanceMeters: Double
    let calories: Double
    let types: [String]
    enum CodingKeys: String, CodingKey {
        case days, sessions, calories, types
        case activeSeconds = "active_seconds"; case distanceMeters = "distance_meters"
    }
}

struct ActivityListResponse: Codable {
    let ok: Bool
    let sessions: [ActivitySessionRecord]
    let summary: ActivitySummary
    let reauthURL: String?
    enum CodingKeys: String, CodingKey { case ok, sessions, summary; case reauthURL = "reauth_url" }
}

struct ActivitySaveResponse: Codable {
    let ok: Bool
    let session: ActivitySessionRecord
    let googleStatus: String
    let message: String
    let needsReauth: Bool
    let reauthURL: String?
    enum CodingKeys: String, CodingKey {
        case ok, session, message
        case googleStatus = "google_status"; case needsReauth = "needs_reauth"; case reauthURL = "reauth_url"
    }
}

struct ActivitySyncResponse: Codable {
    let ok: Bool
    let imported: Int
    let merged: Int
    let uploaded: Int
    let sessions: [ActivitySessionRecord]
    let summary: ActivitySummary
    let message: String
}

struct ActivityRoutePoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: String
}

struct ActivityDraft: Codable, Hashable {
    let clientID: String
    let exerciseType: String
    let displayName: String
    let startTime: String
    let endTime: String
    let durationSeconds: Int
    let activeSeconds: Int
    let distanceMeters: Double
    let averageSpeedMPS: Double?
    let elevationGainMeters: Double?
    let hasGPS: Bool
    let route: [ActivityRoutePoint]
    let notes: String
    let rpe: Int

    enum CodingKeys: String, CodingKey {
        case route, notes, rpe
        case clientID = "client_id"; case exerciseType = "exercise_type"; case displayName = "display_name"
        case startTime = "start_time"; case endTime = "end_time"; case durationSeconds = "duration_seconds"
        case activeSeconds = "active_seconds"; case distanceMeters = "distance_meters"
        case averageSpeedMPS = "average_speed_mps"; case elevationGainMeters = "elevation_gain_meters"
        case hasGPS = "has_gps"
    }
}

enum ActivityPendingStore {
    private static let key = "fitbitair.pending.activities.v1"

    static var all: [ActivityDraft] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let drafts = try? JSONDecoder().decode([ActivityDraft].self, from: data) else { return [] }
        return drafts
    }

    static func enqueue(_ draft: ActivityDraft) {
        var drafts = all.filter { $0.clientID != draft.clientID }
        drafts.append(draft)
        save(drafts)
    }

    static func remove(clientID: String) {
        save(all.filter { $0.clientID != clientID })
    }

    private static func save(_ drafts: [ActivityDraft]) {
        if drafts.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension APIClient {
    func activitySessions(days: Int = 30) async throws -> ActivityListResponse {
        try await request("api/ios/activities?days=\(days)")
    }

    func saveActivity(_ draft: ActivityDraft) async throws -> ActivitySaveResponse {
        let data = try JSONEncoder().encode(draft)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try await request("api/ios/activities/session", method: "POST", body: body, timeout: 45)
    }

    func syncActivities(days: Int = 30) async throws -> ActivitySyncResponse {
        try await request("api/ios/activities/sync", method: "POST", body: ["days": days], timeout: 70)
    }

    func deleteActivity(id: Int, days: Int = 30) async throws -> ActivityListResponse {
        try await request("api/ios/activities/session/delete", method: "POST", body: ["id": id, "days": days])
    }
}

// MARK: - Native tracker

enum ActivityTrackerPhase: String, Codable { case idle, running, paused }

private struct ActivityTrackerSnapshot: Codable {
    let phase: ActivityTrackerPhase
    let activity: ActivityDefinition
    let clientID: String
    let startedAt: Date
    let pausedAt: Date?
    let pausedSeconds: TimeInterval
    let distance: Double
    let elevationGain: Double
    let route: [ActivityRoutePoint]
}

final class ActivityTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ActivityTracker()

    @Published private(set) var phase: ActivityTrackerPhase = .idle
    @Published private(set) var activity: ActivityDefinition?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var activeSeconds = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var currentSpeedMPS = 0.0
    @Published private(set) var elevationGainMeters = 0.0
    @Published private(set) var bpm: Int?
    @Published private(set) var bpmStale = true
    @Published private(set) var locationMessage: String?

    private let locationManager = CLLocationManager()
    private let snapshotKey = "fitbitair.active.activity.v1"
    private var clientID = UUID().uuidString
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedSeconds: TimeInterval = 0
    private var lastLocation: CLLocation?
    private var route: [ActivityRoutePoint] = []
    private var timer: Timer?
    private var heartTask: Task<Void, Never>?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
        locationManager.pausesLocationUpdatesAutomatically = false
        restore()
    }

    var isActive: Bool { phase != .idle }
    var averageSpeedMPS: Double? {
        guard activeSeconds > 0, distanceMeters > 0 else { return nil }
        return distanceMeters / Double(activeSeconds)
    }
    var paceText: String {
        guard distanceMeters >= 50, activeSeconds > 0 else { return "—" }
        let secondsPerKM = Double(activeSeconds) / (distanceMeters / 1000)
        let min = Int(secondsPerKM) / 60
        let sec = Int(secondsPerKM) % 60
        return String(format: "%d:%02d /كم", min, sec)
    }

    func start(_ definition: ActivityDefinition) {
        guard phase == .idle else { return }
        activity = definition
        clientID = UUID().uuidString
        startedAt = Date()
        pausedAt = nil
        pausedSeconds = 0
        elapsedSeconds = 0
        activeSeconds = 0
        distanceMeters = 0
        currentSpeedMPS = 0
        elevationGainMeters = 0
        bpm = nil
        bpmStale = true
        lastLocation = nil
        route = []
        phase = .running
        beginTimer()
        beginHeartPolling()
        beginLocationIfNeeded()
        persist()
    }

    func pause() {
        guard phase == .running else { return }
        pausedAt = Date()
        phase = .paused
        currentSpeedMPS = 0
        updateElapsed()
        locationManager.stopUpdatingLocation()
        persist()
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt { pausedSeconds += Date().timeIntervalSince(pausedAt) }
        self.pausedAt = nil
        phase = .running
        lastLocation = nil
        updateElapsed()
        beginLocationIfNeeded()
        persist()
    }

    func finish(rpe: Int, notes: String) -> ActivityDraft? {
        guard let activity, let startedAt, phase != .idle else { return nil }
        if phase == .paused, let pausedAt { pausedSeconds += Date().timeIntervalSince(pausedAt) }
        let end = Date()
        let duration = max(1, Int(end.timeIntervalSince(startedAt)))
        let active = max(1, Int(end.timeIntervalSince(startedAt) - pausedSeconds))
        let draft = ActivityDraft(
            clientID: clientID,
            exerciseType: activity.officialType,
            displayName: activity.nameAR,
            startTime: Self.iso(startedAt),
            endTime: Self.iso(end),
            durationSeconds: duration,
            activeSeconds: active,
            distanceMeters: distanceMeters,
            averageSpeedMPS: active > 0 && distanceMeters > 0 ? distanceMeters / Double(active) : nil,
            elevationGainMeters: elevationGainMeters > 0 ? elevationGainMeters : nil,
            hasGPS: activity.tracksGPS && !route.isEmpty,
            route: route,
            notes: notes,
            rpe: max(1, min(10, rpe))
        )
        ActivityPendingStore.enqueue(draft)
        reset()
        return draft
    }

    func discard() { reset() }

    private func reset() {
        timer?.invalidate(); timer = nil
        heartTask?.cancel(); heartTask = nil
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        phase = .idle
        activity = nil
        startedAt = nil
        pausedAt = nil
        pausedSeconds = 0
        elapsedSeconds = 0
        activeSeconds = 0
        distanceMeters = 0
        currentSpeedMPS = 0
        elevationGainMeters = 0
        bpm = nil
        lastLocation = nil
        route = []
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.updateElapsed()
                if self.elapsedSeconds % 10 == 0 { self.persist() }
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateElapsed()
    }

    private func updateElapsed() {
        guard let startedAt else {
            elapsedSeconds = 0
            activeSeconds = 0
            return
        }

        let now = Date()
        elapsedSeconds = max(0, Int(now.timeIntervalSince(startedAt)))

        // Keep the displayed timer as a real published value. This avoids a
        // computed-Date timer getting stuck while other metrics continue to move.
        let activeEnd = phase == .paused ? (pausedAt ?? now) : now
        activeSeconds = max(0, Int(activeEnd.timeIntervalSince(startedAt) - pausedSeconds))
    }

    private func beginHeartPolling() {
        heartTask?.cancel()

        // Keep UI state mutations on the main actor. Explicit actor isolation
        // also avoids Swift 6 captured-weak-self concurrency diagnostics.
        heartTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    let response = try await APIClient.shared.liveHeart()
                    if let value = response.bpm {
                        self?.bpm = value
                        self?.bpmStale = response.stale
                    } else if let dashboard = try? await APIClient.shared.dashboard(force: true),
                              let fallback = dashboard.currentHR {
                        // Keep the latest synchronized Fitbit value visible instead
                        // of replacing it with an unavailable label.
                        self?.bpm = fallback
                        self?.bpmStale = true
                    } else {
                        self?.bpmStale = true
                    }
                } catch {
                    // Preserve the last valid BPM and only mark it as stale.
                    self?.bpmStale = true
                }

                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func beginLocationIfNeeded() {
        guard activity?.tracksGPS == true, phase == .running else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            locationMessage = "وافق على الموقع لحساب المسافة والسرعة"
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
            locationManager.startUpdatingLocation()
            locationMessage = nil
        case .denied, .restricted:
            locationMessage = "الموقع غير مسموح؛ سيُحفظ الوقت وتُضاف بيانات Fitbit بعد المزامنة"
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in self?.beginLocationIfNeeded() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.locationMessage = "تعذر تحديث الموقع مؤقتًا" }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .running else { return }
        for location in locations {
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { continue }
            if let last = lastLocation {
                let interval = location.timestamp.timeIntervalSince(last.timestamp)
                let segment = location.distance(from: last)
                if interval > 0, interval <= 120, segment >= 0.5, segment <= 500 {
                    distanceMeters += segment
                    let elevation = location.altitude - last.altitude
                    if elevation > 0, elevation < 30 { elevationGainMeters += elevation }
                }
            }
            currentSpeedMPS = max(0, location.speed)
            lastLocation = location
            if route.count < 2500 {
                route.append(ActivityRoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, altitude: location.altitude, timestamp: Self.iso(location.timestamp)))
            }
        }
        persist()
    }

    private func persist() {
        guard let activity, let startedAt, phase != .idle else { return }
        let snapshot = ActivityTrackerSnapshot(phase: phase, activity: activity, clientID: clientID, startedAt: startedAt, pausedAt: pausedAt, pausedSeconds: pausedSeconds, distance: distanceMeters, elevationGain: elevationGainMeters, route: route)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: snapshotKey) }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey), let snapshot = try? JSONDecoder().decode(ActivityTrackerSnapshot.self, from: data) else { return }
        phase = snapshot.phase
        activity = snapshot.activity
        clientID = snapshot.clientID
        startedAt = snapshot.startedAt
        pausedAt = snapshot.pausedAt
        pausedSeconds = snapshot.pausedSeconds
        distanceMeters = snapshot.distance
        elevationGainMeters = snapshot.elevationGain
        route = snapshot.route
        beginTimer()
        beginHeartPolling()
        if phase == .running { beginLocationIfNeeded() }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Activity hub UI

private enum ActivityHubPage: String, CaseIterable, Identifiable {
    case start = "بدء نشاط"
    case history = "سجل النشاطات"
    var id: String { rawValue }
    var icon: String { self == .start ? "play.circle.fill" : "clock.arrow.circlepath" }
}

struct ActivityHubView: View {
    @StateObject private var tracker = ActivityTracker.shared
    @State private var sessions: [ActivitySessionRecord] = []
    @State private var summary: ActivitySummary?
    @State private var selectedCategory: ActivityCategory = .popular
    @State private var search = ""
    @State private var selectedActivity: ActivityDefinition?
    @State private var loading = false
    @State private var syncing = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var reauthURL: URL?
    @State private var page: ActivityHubPage = .start
    @State private var expandedCategories: Set<ActivityCategory> = [.popular, .cardio, .outdoors]
    @State private var pendingDeleteSession: ActivitySessionRecord?
    @State private var deletingSession = false

    private var searchNeedle: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filtered: [ActivityDefinition] {
        ActivityCatalog.all.filter { item in
            let categoryMatches: Bool
            switch selectedCategory {
            case .all:
                categoryMatches = true
            case .popular:
                categoryMatches = ActivityCatalog.popular.contains(item)
            default:
                categoryMatches = item.category == selectedCategory
            }
            let searchMatches = searchNeedle.isEmpty || item.nameAR.lowercased().contains(searchNeedle) || item.nameEN.lowercased().contains(searchNeedle) || item.officialType.lowercased().contains(searchNeedle)
            return categoryMatches && searchMatches
        }
    }

    private var activityGroups: [(ActivityCategory, [ActivityDefinition])] {
        if selectedCategory == .popular { return [(.popular, filtered)] }
        if selectedCategory != .all { return [(selectedCategory, filtered)] }
        return ActivityCategory.allCases
            .filter { $0 != .all && $0 != .popular }
            .compactMap { category in
                let rows = filtered.filter { $0.category == category }
                return rows.isEmpty ? nil : (category, rows)
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                activityHeader
                activityPagePicker
                if tracker.isActive { activeBanner }

                if page == .start {
                    searchField
                    categoryPicker

                    HStack {
                        Text("اختر النشاط").font(.title3.bold())
                        Spacer()
                        Text("\(filtered.count) نشاط • أقسام قابلة للطي").font(.caption).foregroundStyle(.white.opacity(0.5))
                    }.padding(.horizontal)

                    ForEach(activityGroups, id: \.0) { group in
                        ActivityCategoryDisclosure(
                            category: group.0,
                            activities: group.1,
                            isExpanded: Binding(
                                get: { !searchNeedle.isEmpty || activityGroups.count == 1 || expandedCategories.contains(group.0) },
                                set: { expanded in
                                    if expanded { expandedCategories.insert(group.0) }
                                    else { expandedCategories.remove(group.0) }
                                }
                            ),
                            onSelect: { selectedActivity = $0 }
                        )
                        .padding(.horizontal)
                    }
                } else {
                    summaryCards
                    recentSessions
                }
            }
            .padding(.vertical, 4)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await sync() }
        .task { await load() }
        .sheet(item: $selectedActivity) { activity in
            ActivityStartSheet(activity: activity) {
                tracker.start(activity)
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: Binding(get: { tracker.isActive }, set: { _ in })) {
            ActivityLiveView(tracker: tracker, onSaved: { response in
                notice = response.message
                if response.needsReauth, let value = response.reauthURL { reauthURL = URL(string: value) }
                page = .history
                Task { await load() }
            }, onQueued: { message in
                notice = message
                page = .history
                Task { await load() }
            })
        }
        .alert("FitbitAir", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            if let reauthURL {
                Button("تحديث الصلاحيات") { UIApplication.shared.open(reauthURL) }
            }
            Button("تم", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .confirmationDialog(
            "حذف النشاط من FitbitAir؟",
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { if !$0 { pendingDeleteSession = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف النشاط", role: .destructive) {
                guard let session = pendingDeleteSession else { return }
                Task { await deleteSession(session) }
            }
            Button("إلغاء", role: .cancel) { pendingDeleteSession = nil }
        } message: {
            Text("سيختفي النشاط من سجل FitbitAir وتقاريره. هذا لا يحذف السجل الأصلي من حساب Google/Fitbit.")
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("النشاطات").font(.largeTitle.bold())
                Text(page == .start ? "اختر النشاط وابدأ التتبع" : "كل نشاطاتك المحفوظة في مكان مستقل")
                    .font(.caption).foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
            Button { Task { await sync() } } label: {
                Image(systemName: syncing ? "hourglass" : "arrow.triangle.2.circlepath")
                    .font(.title3.bold()).frame(width: 48, height: 48)
                    .background(FitTheme.cardStrong, in: Circle())
            }.disabled(syncing)
        }.padding(.horizontal)
    }

    private var activityPagePicker: some View {
        HStack(spacing: 8) {
            ForEach(ActivityHubPage.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { page = item }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(page == item ? Color.black : Color.white.opacity(0.65))
                        .background(page == item ? FitTheme.accent : FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(FitTheme.card, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(FitTheme.stroke))
        .padding(.horizontal)
    }

    private var activeBanner: some View {
        Button { } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: tracker.activity?.icon ?? "figure.run")
                        .font(.title2).foregroundStyle(FitTheme.accent)
                        .frame(width: 52, height: 52).background(FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("نشاط جاري").font(.caption).foregroundStyle(.white.opacity(0.5))
                        Text(tracker.activity?.nameAR ?? "نشاط").font(.headline)
                    }
                    Spacer()
                    Text(Self.clock(tracker.activeSeconds)).font(.headline.monospacedDigit()).foregroundStyle(FitTheme.accent)
                }
            }
        }.buttonStyle(.plain).padding(.horizontal)
    }

    @ViewBuilder private var summaryCards: some View {
        if let summary {
            HStack(spacing: 10) {
                ActivityMiniMetric(title: "الجلسات", value: "\(summary.sessions)", icon: "figure.run")
                ActivityMiniMetric(title: "الوقت", value: "\(summary.activeSeconds / 60) د", icon: "clock.fill")
                ActivityMiniMetric(title: "المسافة", value: String(format: "%.1f كم", summary.distanceMeters / 1000), icon: "location.fill")
            }.padding(.horizontal)
        }
        if let errorMessage { ErrorBanner(message: errorMessage).padding(.horizontal) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.45))
            TextField("ابحث عن ركض، بادل، سباحة...", text: $search)
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 15).frame(height: 50)
        .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(FitTheme.stroke))
        .padding(.horizontal)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases) { category in
                    Button { selectedCategory = category } label: {
                        Text(category.title).font(.caption.bold())
                            .foregroundStyle(selectedCategory == category ? .black : .white.opacity(0.65))
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(selectedCategory == category ? FitTheme.accent : FitTheme.cardStrong, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal)
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("سجل النشاطات").font(.title3.bold())
                Spacer()
                if loading { ProgressView().tint(FitTheme.accent) }
            }.padding(.horizontal)
            if sessions.isEmpty {
                Card { Text("ما عندك نشاطات محفوظة إلى الآن").foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading) }.padding(.horizontal)
            } else {
                ForEach(sessions.prefix(100)) { session in
                    ActivitySessionRow(session: session) {
                        pendingDeleteSession = session
                    }
                    .padding(.horizontal)
                }
            }
        }.padding(.top, 8)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        await retryPendingActivities()
        do {
            let response = try await APIClient.shared.activitySessions(days: 30)
            sessions = response.sessions
            summary = response.summary
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func retryPendingActivities() async {
        for draft in ActivityPendingStore.all {
            do {
                let response = try await APIClient.shared.saveActivity(draft)
                ActivityPendingStore.remove(clientID: draft.clientID)
                if response.needsReauth, let value = response.reauthURL {
                    reauthURL = URL(string: value)
                }
            } catch {
                // يبقى محفوظًا محليًا ويُعاد إرساله عند فتح الصفحة أو السحب للتحديث.
                break
            }
        }
    }

    private func sync() async {
        syncing = true
        defer { syncing = false }
        do {
            let response = try await APIClient.shared.syncActivities(days: 30)
            sessions = response.sessions; summary = response.summary
            notice = "\(response.message) — جديد: \(response.imported)، مدمج: \(response.merged)"
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func deleteSession(_ session: ActivitySessionRecord) async {
        guard !deletingSession else { return }
        deletingSession = true
        defer { deletingSession = false }
        let oldSessions = sessions
        sessions.removeAll { $0.id == session.id }
        pendingDeleteSession = nil
        do {
            let response = try await APIClient.shared.deleteActivity(id: session.id, days: 30)
            sessions = response.sessions
            summary = response.summary
            notice = "تم حذف النشاط من FitbitAir."
        } catch {
            sessions = oldSessions
            errorMessage = "تعذر حذف النشاط: \(error.localizedDescription)"
        }
    }

    private static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) }
}

private struct ActivityCategoryDisclosure: View {
    let category: ActivityCategory
    let activities: [ActivityDefinition]
    @Binding var isExpanded: Bool
    let onSelect: (ActivityDefinition) -> Void

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: categoryIcon)
                            .font(.headline)
                            .foregroundStyle(FitTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title).font(.headline).foregroundStyle(.white)
                            Text("\(activities.count) نشاط").font(.caption2).foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(FitTheme.accent)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().overlay(Color.white.opacity(0.08))
                    LazyVStack(spacing: 0) {
                        ForEach(activities) { activity in
                            Button { onSelect(activity) } label: {
                                ActivityCatalogRow(activity: activity, compact: true)
                            }
                            .buttonStyle(.plain)
                            if activity.id != activities.last?.id {
                                Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 82)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var categoryIcon: String {
        switch category {
        case .popular: return "star.fill"
        case .cardio: return "heart.circle.fill"
        case .strength: return "dumbbell.fill"
        case .sports: return "sportscourt.fill"
        case .outdoors: return "mountain.2.fill"
        case .water: return "drop.fill"
        case .mindBody: return "figure.mind.and.body"
        case .winter: return "snowflake"
        case .daily: return "house.fill"
        case .other, .all: return "square.grid.2x2.fill"
        }
    }
}

private struct ActivityCatalogRow: View {
    let activity: ActivityDefinition
    var compact = false

    var body: some View {
        Group {
            if compact { row.padding(.horizontal, 14).padding(.vertical, 10) }
            else { Card { row } }
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
            Image(systemName: activity.icon)
                .font(.system(size: compact ? 21 : 25, weight: .semibold))
                .foregroundStyle(FitTheme.accent)
                .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
                .background(FitTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: compact ? 14 : 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.nameAR).font(.headline)
                Text(activity.nameEN).font(.caption).foregroundStyle(.white.opacity(0.45))
                HStack(spacing: 6) {
                    Text(activity.category.title)
                    if activity.tracksGPS { Label("GPS", systemImage: "location.fill") }
                }.font(.caption2).foregroundStyle(FitTheme.accent)
            }
            Spacer()
            Image(systemName: "play.fill")
                .foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(FitTheme.accent, in: Circle())
        }
    }
}

private struct ActivityMiniMetric: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(FitTheme.accent)
            Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.45))
        }.frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(FitTheme.stroke))
    }
}

private struct ActivitySessionRow: View {
    let session: ActivitySessionRecord
    let onDelete: () -> Void
    var definition: ActivityDefinition? { ActivityCatalog.all.first { $0.officialType == session.exerciseType } }
    var body: some View {
        Card {
            HStack(spacing: 13) {
                Image(systemName: definition?.icon ?? "figure.mixed.cardio").font(.title2).foregroundStyle(FitTheme.accentBlue)
                    .frame(width: 52, height: 52).background(FitTheme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(definition?.nameAR ?? session.displayName).font(.headline)
                    Text(Self.date(session.startTime)).font(.caption2).foregroundStyle(.white.opacity(0.43))
                    HStack(spacing: 10) {
                        Label("\(session.activeSeconds / 60) د", systemImage: "clock")
                        if let distance = session.distanceMeters, distance > 50 { Label(String(format: "%.2f كم", distance / 1000), systemImage: "location") }
                        if let hr = session.averageHeartRate { Label("\(hr)", systemImage: "heart.fill") }
                    }.font(.caption2).foregroundStyle(.white.opacity(0.64))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 9) {
                    Image(systemName: session.syncStatus == "synced" || session.syncStatus == "uploaded" ? "checkmark.icloud.fill" : session.syncStatus == "needs_reauth" ? "exclamationmark.icloud.fill" : "icloud.and.arrow.up")
                        .foregroundStyle(session.syncStatus == "needs_reauth" ? FitTheme.warning : FitTheme.accent)
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("حذف النشاط", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .accessibilityLabel("خيارات النشاط")
                }
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("حذف النشاط", systemImage: "trash")
            }
        }
    }
    private static func date(_ value: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        guard let date = fractional.date(from: value) ?? standard.date(from: value) else { return value }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ar_QA")
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}

private struct ActivityStartSheet: View {
    let activity: ActivityDefinition
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var countdown = 0

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 46, height: 5).padding(.top, 8)
            Image(systemName: activity.icon).font(.system(size: 54, weight: .semibold)).foregroundStyle(FitTheme.accent)
                .frame(width: 112, height: 112).background(FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 32))
            VStack(spacing: 6) {
                Text(activity.nameAR).font(.largeTitle.bold())
                Text(activity.nameEN).foregroundStyle(.white.opacity(0.5))
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label(activity.tracksGPS ? "يستخدم GPS لحساب المسافة والسرعة" : "يسجل الوقت ويضيف بيانات Fitbit بعد المزامنة", systemImage: activity.tracksGPS ? "location.fill" : "clock.fill")
                    Label("تقدر توقف مؤقتًا وتكمل من نفس الشاشة", systemImage: "pause.circle.fill")
                    Label("بعد النهاية يُحفظ في FitbitAir وGoogle Health", systemImage: "arrow.triangle.2.circlepath")
                }.font(.subheadline).foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
            Button {
                countdown = 3
                Task {
                    for value in stride(from: 3, through: 1, by: -1) {
                        await MainActor.run { countdown = value }
                        try? await Task.sleep(for: .seconds(1))
                    }
                    await MainActor.run { onStart(); dismiss() }
                }
            } label: {
                Text(countdown > 0 ? "\(countdown)" : "ابدأ النشاط")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(FitTheme.gradient, in: RoundedRectangle(cornerRadius: 19)).foregroundStyle(.black)
            }.disabled(countdown > 0)
        }.padding().background(AppBackground()).preferredColorScheme(.dark)
    }
}

private struct ActivityLiveView: View {
    @ObservedObject var tracker: ActivityTracker
    let onSaved: (ActivitySaveResponse) -> Void
    let onQueued: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showFinish = false
    @State private var showDiscard = false
    @State private var saving = false
    @State private var rpe = 7.0
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button { showDiscard = true } label: { Image(systemName: "xmark").font(.title2.bold()).frame(width: 48, height: 48).background(FitTheme.cardStrong, in: Circle()) }
                        Spacer()
                        VStack(spacing: 3) {
                            Text(tracker.activity?.nameAR ?? "نشاط").font(.headline)
                            Text(tracker.phase == .paused ? "متوقف مؤقتًا" : "نشاط مباشر").font(.caption).foregroundStyle(tracker.phase == .paused ? FitTheme.warning : FitTheme.accent)
                        }
                        Spacer()
                        Image(systemName: tracker.activity?.icon ?? "figure.run").font(.title2).foregroundStyle(FitTheme.accent).frame(width: 48, height: 48).background(FitTheme.accent.opacity(0.12), in: Circle())
                    }
                    .padding(.horizontal)

                    ZStack {
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 18)
                        Circle().trim(from: 0.04, to: 0.82).stroke(FitTheme.gradient, style: StrokeStyle(lineWidth: 18, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 8) {
                            Text(Self.clock(tracker.activeSeconds)).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("الوقت الفعلي").foregroundStyle(.white.opacity(0.46))
                        }
                    }.frame(width: 250, height: 250)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        LiveMetric(title: "المسافة", value: String(format: "%.2f كم", tracker.distanceMeters / 1000), icon: "location.fill")
                        LiveMetric(title: "الوتيرة", value: tracker.paceText, icon: "speedometer")
                        LiveMetric(title: "السرعة", value: String(format: "%.1f كم/س", tracker.currentSpeedMPS * 3.6), icon: "gauge.with.dots.needle.67percent")
                        LiveMetric(title: "النبض", value: tracker.bpm.map { "\($0) bpm" } ?? "بانتظار Fitbit", icon: "heart.fill", warning: tracker.bpmStale)
                    }.padding(.horizontal)

                    if let message = tracker.locationMessage {
                        ErrorBanner(message: message).padding(.horizontal)
                    }

                    HStack(spacing: 12) {
                        Button {
                            tracker.phase == .paused ? tracker.resume() : tracker.pause()
                        } label: {
                            Label(tracker.phase == .paused ? "متابعة" : "إيقاف مؤقت", systemImage: tracker.phase == .paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 16).background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                        Button { showFinish = true } label: {
                            Label("إنهاء", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 16).background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }.padding(.horizontal)
                }.padding(.vertical, 18)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showFinish) {
            NavigationStack {
                Form {
                    Section("تقييم النشاط") {
                        HStack { Text("الجهد RPE"); Spacer(); Text("\(Int(rpe))/10").foregroundStyle(FitTheme.accent) }
                        Slider(value: $rpe, in: 1...10, step: 1).tint(FitTheme.accent)
                        TextField("ملاحظات اختيارية", text: $note, axis: .vertical).lineLimit(3...6)
                    }
                    if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                    Section {
                        Button {
                            Task { await finishAndSave() }
                        } label: {
                            HStack { Spacer(); if saving { ProgressView() } else { Text("حفظ وإنهاء النشاط").bold() }; Spacer() }
                        }
                        .disabled(saving)

                        Button("إنهاء بدون حفظ", role: .destructive) {
                            tracker.discard()
                            showFinish = false
                            dismiss()
                        }
                        .disabled(saving)
                    } footer: {
                        Text("إنهاء بدون حفظ يلغي الوقت والمسافة نهائيًا.")
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("إنهاء النشاط")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("رجوع") { showFinish = false } }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("تم") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    }
                }
            }.presentationDetents([.medium])
        }
        .confirmationDialog("إلغاء النشاط؟", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("حذف النشاط الجاري", role: .destructive) { tracker.discard(); dismiss() }
            Button("متابعة النشاط", role: .cancel) {}
        } message: { Text("لن يتم حفظ الوقت أو المسافة.") }
    }

    private func finishAndSave() async {
        guard let draft = tracker.finish(rpe: Int(rpe), notes: note) else { return }
        saving = true
        defer { saving = false }
        do {
            let response = try await APIClient.shared.saveActivity(draft)
            ActivityPendingStore.remove(clientID: draft.clientID)
            showFinish = false
            onSaved(response)
            dismiss()
        } catch {
            let message = "تم حفظ النشاط داخل الآيفون، وسيُرسل تلقائيًا عند رجوع الاتصال."
            errorMessage = message
            onQueued(message)
            dismiss()
        }
    }

    private static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60) }
}

private struct LiveMetric: View {
    let title: String; let value: String; let icon: String; var warning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: icon).foregroundStyle(warning ? FitTheme.warning : FitTheme.accent); Spacer() }
            Text(value).font(.title3.bold()).minimumScaleFactor(0.65).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.45))
        }.padding(15).frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
            .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(FitTheme.stroke))
    }
}
