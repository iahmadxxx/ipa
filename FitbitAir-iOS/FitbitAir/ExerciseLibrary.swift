import SwiftUI
import UIKit

// MARK: - Exercise catalogue models

enum ExerciseMuscleGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case all = "الكل"
    case chest = "الصدر"
    case back = "الظهر"
    case shoulders = "الأكتاف"
    case biceps = "البايسبس"
    case triceps = "الترايسبس"
    case legs = "الأرجل"
    case glutes = "المؤخرة"
    case core = "البطن"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .chest: return "heart.fill"
        case .back: return "figure.strengthtraining.traditional"
        case .shoulders: return "figure.arms.open"
        case .biceps: return "dumbbell.fill"
        case .triceps: return "bolt.fill"
        case .legs: return "figure.walk"
        case .glutes: return "figure.stairs"
        case .core: return "circle.hexagongrid.fill"
        }
    }

    var tint: Color {
        switch self {
        case .all: return FitTheme.accent
        case .chest: return .red
        case .back: return FitTheme.accentBlue
        case .shoulders: return .orange
        case .biceps: return .purple
        case .triceps: return .pink
        case .legs: return FitTheme.positive
        case .glutes: return .indigo
        case .core: return .yellow
        }
    }
}

enum ExerciseEquipment: String, CaseIterable, Identifiable, Codable, Hashable {
    case barbell = "بار"
    case dumbbells = "دمبل"
    case cable = "كيبل"
    case machine = "جهاز"
    case bodyweight = "وزن الجسم"
    case bench = "بنش"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .barbell: return "dumbbell.fill"
        case .dumbbells: return "dumbbell"
        case .cable: return "point.3.connected.trianglepath.dotted"
        case .machine: return "gearshape.2.fill"
        case .bodyweight: return "figure.strengthtraining.traditional"
        case .bench: return "rectangle.split.3x1.fill"
        }
    }
}

enum ExerciseDifficulty: String, CaseIterable, Identifiable, Codable, Hashable {
    case beginner = "مبتدئ"
    case intermediate = "متوسط"
    case advanced = "متقدم"
    var id: String { rawValue }
}

enum ExercisePoseKind: String, Codable, Hashable {
    case horizontalPress
    case inclinePress
    case fly
    case pushUp
    case verticalPull
    case row
    case hinge
    case squat
    case lunge
    case legMachine
    case shoulderPress
    case lateralRaise
    case curl
    case triceps
    case dip
    case hipThrust
    case calfRaise
    case core
    case plank
}

struct ExerciseDefinition: Identifiable, Codable, Hashable {
    let id: String
    let nameAR: String
    let nameEN: String
    let primaryMuscle: ExerciseMuscleGroup
    let secondaryMuscles: [ExerciseMuscleGroup]
    let equipment: ExerciseEquipment
    let difficulty: ExerciseDifficulty
    let pose: ExercisePoseKind
    let overview: String
    let steps: [String]
    let mistakes: [String]
    let tips: [String]
    let aliases: [String]
    let defaultSets: Int
    let minReps: Int
    let maxReps: Int
    let restSeconds: Int
    let isCustom: Bool

    var displayName: String { nameAR.isEmpty ? nameEN : nameAR }
    var repRangeText: String { minReps == maxReps ? "\(minReps)" : "\(minReps)–\(maxReps)" }

    static func custom(
        nameAR: String,
        nameEN: String,
        muscle: ExerciseMuscleGroup,
        equipment: ExerciseEquipment,
        overview: String,
        steps: [String]
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: "custom-\(UUID().uuidString)",
            nameAR: nameAR,
            nameEN: nameEN.isEmpty ? nameAR : nameEN,
            primaryMuscle: muscle,
            secondaryMuscles: [],
            equipment: equipment,
            difficulty: .intermediate,
            pose: ExerciseCatalog.defaultPose(for: muscle),
            overview: overview.isEmpty ? "تمرين مخصص أضفته إلى مكتبتك." : overview,
            steps: steps.isEmpty ? ["اضبط وضعية الجسم والجهاز.", "نفذ الحركة بتحكم ومن دون ألم.", "سجّل الوزن والعدات بعد كل جولة."] : steps,
            mistakes: ["استخدام وزن يؤثر على جودة الحركة.", "تجاهل الألم أو فقدان التحكم."],
            tips: ["ابدأ بوزن محافظ وسجّل ملاحظاتك."],
            aliases: [nameAR, nameEN],
            defaultSets: 3,
            minReps: 8,
            maxReps: 12,
            restSeconds: 90,
            isCustom: true
        )
    }
}

struct ExercisePrescription: Codable, Equatable {
    var sets: Int
    var minReps: Int
    var maxReps: Int
    var restSeconds: Int
    var note: String

    var summary: String {
        let reps = minReps == maxReps ? "\(minReps)" : "\(minReps)–\(maxReps)"
        return "\(sets) جولات × \(reps) عدة • راحة \(restSeconds)ث"
    }
}

enum ExercisePrescriptionStore {
    private static let storageKey = "fitbitair.exercise.prescriptions.v1"

    private static func compoundKey(dayKey: String, exerciseName: String) -> String {
        "\(dayKey.lowercased())|\(ExerciseCatalog.normalize(exerciseName))"
    }

    private static func readAll() -> [String: ExercisePrescription] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode([String: ExercisePrescription].self, from: data) else {
            return [:]
        }
        return value
    }

    static func value(dayKey: String, exerciseName: String, fallback: ExerciseDefinition? = nil) -> ExercisePrescription {
        let key = compoundKey(dayKey: dayKey, exerciseName: exerciseName)
        if let value = readAll()[key] { return value }
        let item = fallback ?? ExerciseCatalog.resolved(exerciseName)
        return ExercisePrescription(
            sets: item.defaultSets,
            minReps: item.minReps,
            maxReps: item.maxReps,
            restSeconds: item.restSeconds,
            note: ""
        )
    }

    static func save(_ value: ExercisePrescription, dayKey: String, exerciseName: String) {
        var all = readAll()
        all[compoundKey(dayKey: dayKey, exerciseName: exerciseName)] = value
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

enum CustomExerciseStore {
    private static let storageKey = "fitbitair.exercise.custom.v1"

    static func all() -> [ExerciseDefinition] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([ExerciseDefinition].self, from: data) else {
            return []
        }
        return items
    }

    static func add(_ exercise: ExerciseDefinition) {
        var items = all()
        items.removeAll { ExerciseCatalog.normalize($0.nameEN) == ExerciseCatalog.normalize(exercise.nameEN) }
        items.insert(exercise, at: 0)
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func delete(_ exercise: ExerciseDefinition) {
        let items = all().filter { $0.id != exercise.id }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Built-in exercise catalogue

enum ExerciseCatalog {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "ـ", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func match(_ name: String) -> ExerciseDefinition? {
        let needle = normalize(name)
        let fragments = name
            .components(separatedBy: CharacterSet(charactersIn: "()[]{}"))
            .map(normalize)
            .filter { !$0.isEmpty }
        let variants = Set([needle] + fragments)
        let available = CustomExerciseStore.all() + all

        if let exact = available.first(where: { exercise in
            ([exercise.nameAR, exercise.nameEN] + exercise.aliases).contains {
                variants.contains(normalize($0))
            }
        }) { return exact }

        var best: (exercise: ExerciseDefinition, score: Int)?
        for exercise in available {
            for rawCandidate in [exercise.nameAR, exercise.nameEN] + exercise.aliases {
                let candidate = normalize(rawCandidate)
                guard candidate.count >= 3 else { continue }
                var score = 0
                if needle.contains(candidate) {
                    score = candidate.count
                } else if candidate.contains(needle) {
                    score = needle.count
                }
                if score > (best?.score ?? 0) {
                    best = (exercise, score)
                }
            }
        }
        return best?.exercise
    }

    static func resolved(_ name: String) -> ExerciseDefinition {
        if let item = match(name) { return item }
        return ExerciseDefinition(
            id: "legacy-\(normalize(name))",
            nameAR: name,
            nameEN: name,
            primaryMuscle: .all,
            secondaryMuscles: [],
            equipment: .machine,
            difficulty: .intermediate,
            pose: .horizontalPress,
            overview: "تمرين موجود في برنامجك القديم. تقدر تعدل اسمه أو تنشئ له نسخة مخصصة من المكتبة مع شرح كامل.",
            steps: ["اضبط الجهاز والوضعية قبل البدء.", "نفذ الحركة بمدى مريح وتحكم كامل.", "توقف إذا ظهر ألم حاد وسجّل ملاحظتك."],
            mistakes: ["الاستعجال في الحركة.", "استخدام وزن يمنع التحكم."],
            tips: ["حافظ على التنفس وثبات الجسم."],
            aliases: [name],
            defaultSets: 3,
            minReps: 8,
            maxReps: 12,
            restSeconds: 90,
            isCustom: true
        )
    }

    static func defaultPose(for muscle: ExerciseMuscleGroup) -> ExercisePoseKind {
        switch muscle {
        case .chest: return .horizontalPress
        case .back: return .row
        case .shoulders: return .shoulderPress
        case .biceps: return .curl
        case .triceps: return .triceps
        case .legs: return .squat
        case .glutes: return .hipThrust
        case .core: return .core
        case .all: return .horizontalPress
        }
    }

    private static func item(
        _ id: String,
        _ ar: String,
        _ en: String,
        _ muscle: ExerciseMuscleGroup,
        _ secondary: [ExerciseMuscleGroup],
        _ equipment: ExerciseEquipment,
        _ difficulty: ExerciseDifficulty,
        _ pose: ExercisePoseKind,
        _ overview: String,
        _ steps: [String],
        _ mistakes: [String],
        _ tips: [String],
        aliases: [String] = [],
        sets: Int = 3,
        reps: ClosedRange<Int> = 8...12,
        rest: Int = 90
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            nameAR: ar,
            nameEN: en,
            primaryMuscle: muscle,
            secondaryMuscles: secondary,
            equipment: equipment,
            difficulty: difficulty,
            pose: pose,
            overview: overview,
            steps: steps,
            mistakes: mistakes,
            tips: tips,
            aliases: aliases,
            defaultSets: sets,
            minReps: reps.lowerBound,
            maxReps: reps.upperBound,
            restSeconds: rest,
            isCustom: false
        )
    }

    static let all: [ExerciseDefinition] = [
        item("bench-press", "بنش برس بالبار", "Barbell Bench Press", .chest, [.triceps, .shoulders], .barbell, .intermediate, .horizontalPress,
             "تمرين مركب أساسي لبناء الصدر والقوة في الدفع.",
             ["ثبت القدمين واسحب لوحي الكتف للخلف.", "أنزل البار بتحكم إلى منتصف الصدر.", "ادفع للأعلى مع بقاء الكتفين ثابتين."],
             ["فتح المرفقين بزاوية كبيرة.", "رفع المؤخرة عن المقعد.", "ارتداد البار من الصدر."],
             ["اجعل المعصم فوق المرفق.", "استخدم مساعدًا عند الأوزان العالية."], aliases: ["Bench Press", "Flat Bench Press"], sets: 4, reps: 5...10, rest: 120),
        item("incline-bench", "بنش مائل بالبار", "Incline Bench Press", .chest, [.shoulders, .triceps], .barbell, .intermediate, .inclinePress,
             "يركز على أعلى الصدر مع مشاركة الكتف الأمامي والترايسبس.",
             ["اضبط المقعد على ميل معتدل 20–35 درجة.", "ثبت الكتفين واسحب البار فوق أعلى الصدر.", "انزل بتحكم ثم ادفع في مسار ثابت."],
             ["رفع زاوية المقعد كثيرًا.", "انهيار الكتفين للأمام.", "النزول بسرعة."],
             ["ابدأ بوزن أقل من البنش المستوي.", "لا تقفل المرفق بعنف."], aliases: ["Incline Barbell Press"], sets: 4, reps: 6...10, rest: 120),
        item("dumbbell-bench", "بنش دمبل", "Dumbbell Bench Press", .chest, [.triceps, .shoulders], .dumbbells, .beginner, .horizontalPress,
             "يسمح بمدى حركة جيد ويساعد على موازنة القوة بين الجهتين.",
             ["ثبت القدمين والكتفين على المقعد.", "انزل الدمبل بجانب الصدر.", "ادفع للأعلى حتى يقترب الدمبلان دون اصطدام."],
             ["إنزال الدمبل منخفضًا جدًا.", "تدوير المعصم.", "فقدان ثبات الكتف."],
             ["تحكم في النزول لثانيتين.", "ابدأ بالجهة الأضعف في التركيز."], aliases: ["Flat Dumbbell Press", "Dumbbell Press", "دامبل مستوي"], sets: 4, reps: 8...12, rest: 90),
        item("incline-dumbbell", "بنش مائل دمبل", "Incline Dumbbell Press", .chest, [.shoulders, .triceps], .dumbbells, .intermediate, .inclinePress,
             "ضغط دمبل مائل لتطوير أعلى الصدر بتوازن بين الجهتين.",
             ["اضبط الميل على 20–35 درجة.", "ثبت لوحي الكتف للخلف.", "انزل الدمبل بمحاذاة أعلى الصدر ثم ادفع."],
             ["رفع الكتف للأذن.", "تقريب المرفق من 90 درجة بالكامل.", "استخدام زخم."],
             ["اجعل المرفق تحت الدمبل.", "حافظ على تقوس طبيعي بسيط للظهر."], aliases: ["Incline DB Press"], sets: 3, reps: 8...12, rest: 90),
        item("chest-fly", "تفتيح صدر دمبل", "Dumbbell Chest Fly", .chest, [.shoulders], .dumbbells, .intermediate, .fly,
             "تمرين عزل للصدر يعتمد على ضم الذراعين بقوس واسع.",
             ["اثنِ المرفق قليلًا وثبته.", "افتح الذراعين حتى تشعر بتمدد مريح.", "اضمم الدمبلين باستخدام الصدر."],
             ["تحويل الحركة إلى ضغط.", "تمديد زائد للكتف.", "استخدام وزن ثقيل."],
             ["التحكم أهم من الوزن.", "حافظ على زاوية المرفق ثابتة."], aliases: ["Dumbbell Fly", "Chest Fly", "Machine Chest Fly", "جهاز تفتيح صدر"], sets: 3, reps: 10...15, rest: 75),
        item("cable-crossover", "تفتيح كيبل", "Cable Crossover", .chest, [.shoulders], .cable, .intermediate, .fly,
             "يحافظ على شد مستمر على الصدر خلال كامل الحركة.",
             ["قف في المنتصف بخطوة صغيرة للأمام.", "اجمع المقابض أمام الصدر بقوس.", "ارجع ببطء حتى تمدد مريح."],
             ["تحريك الجذع للأمام والخلف.", "ثني المرفق وتغييره أثناء الحركة.", "تقاطع اليدين بشكل مبالغ."],
             ["اختر ارتفاع البكرات حسب الجزء المستهدف.", "اثبت الصدر مرفوعًا."], aliases: ["Cable Fly"], sets: 3, reps: 12...15, rest: 60),
        item("machine-chest-press", "ضغط صدر جهاز", "Machine Chest Press", .chest, [.triceps, .shoulders], .machine, .beginner, .horizontalPress,
             "ضغط صدر على جهاز بمسار ثابت، مناسب لبناء العضلة والتحكم.",
             ["اضبط المقعد لتكون المقابض بمحاذاة منتصف الصدر.", "ثبت الكتفين وادفع المقابض للأمام.", "ارجع ببطء حتى تمدد مريح."],
             ["رفع الكتف.", "قفل المرفق بعنف.", "إبعاد الظهر عن الوسادة."],
             ["اضبط المقعد قبل زيادة الوزن.", "حافظ على الصدر مرفوعًا."], aliases: ["صدر مستوي جهاز"], sets: 4, reps: 8...12, rest: 90),
        item("decline-chest-press", "ضغط صدر سفلي جهاز", "Decline Chest Press", .chest, [.triceps, .shoulders], .machine, .beginner, .horizontalPress,
             "ضغط بمسار مائل للأسفل يركز نسبيًا على الجزء السفلي من الصدر.",
             ["اضبط المقعد بحيث تكون المقابض أسفل مستوى الصدر قليلًا.", "ثبت الكتفين وادفع للأمام والأسفل.", "ارجع بتحكم دون رفع الكتف."],
             ["المبالغة في نزول المرفق.", "استخدام زخم.", "تقويس الظهر."],
             ["ابدأ بمدى مريح للكتف.", "لا تحتاج قفل المرفق."], aliases: ["جهاز صدر سفلي"], sets: 3, reps: 8...12, rest: 90),
        item("incline-machine-press", "ضغط صدر علوي جهاز", "Incline Chest Press", .chest, [.shoulders, .triceps], .machine, .beginner, .inclinePress,
             "ضغط جهاز مائل يركز على أعلى الصدر مع ثبات جيد.",
             ["اضبط المقعد لتكون المقابض بمحاذاة أعلى الصدر.", "اسحب الكتفين للخلف وادفع للأمام.", "ارجع ببطء حتى تمدد مريح."],
             ["رفع الكتف للأذن.", "المقعد منخفض أو مرتفع جدًا.", "السرعة في الرجوع."],
             ["حافظ على المرفق تحت المقبض.", "اختر وزنًا يسمح بمدى كامل."], aliases: ["جهاز صدر عالي"], sets: 3, reps: 8...12, rest: 90),
        item("push-up", "ضغط أرضي", "Push-Up", .chest, [.triceps, .shoulders, .core], .bodyweight, .beginner, .pushUp,
             "تمرين وزن جسم فعال للصدر والترايسبس مع تثبيت البطن.",
             ["ضع اليدين أوسع قليلًا من الكتفين.", "حافظ على الجسم خطًا مستقيمًا.", "انزل الصدر ثم ادفع الأرض بعيدًا."],
             ["هبوط الحوض.", "تقدم الرأس بدل الصدر.", "نصف مدى الحركة."],
             ["ارفع اليدين على بنش للتسهيل.", "أضف وزنًا للتحدي."], aliases: ["Push Ups"], sets: 3, reps: 8...20, rest: 60),

        item("lat-pulldown", "سحب علوي", "Lat Pulldown", .back, [.biceps], .cable, .beginner, .verticalPull,
             "تمرين أساسي لتوسيع الظهر وتعلم السحب العمودي.",
             ["ثبت الفخذين وارفع الصدر.", "اسحب البار إلى أعلى الصدر بالمرفقين.", "ارجع ببطء حتى تمدد الظهر."],
             ["السحب خلف الرقبة.", "الميل للخلف بشكل كبير.", "استخدام الذراع فقط."],
             ["فكر في إنزال المرفقين للجيب.", "ابدأ الحركة بخفض الكتف."], aliases: ["Lat Pull Down", "Wide Grip Pulldown", "Close Grip Pulldown", "سحب امامي ضيق بالمثلث"], sets: 4, reps: 8...12, rest: 90),
        item("pull-up", "عقلة", "Pull-Up", .back, [.biceps, .core], .bodyweight, .intermediate, .verticalPull,
             "سحب وزن الجسم لتطوير الظهر والقبضة.",
             ["ابدأ بتعليق نشط والكتف منخفض.", "اسحب الصدر نحو البار.", "انزل بتحكم حتى تمدد كامل."],
             ["التأرجح.", "رفع الذقن فقط دون الصدر.", "فقدان ثبات البطن."],
             ["استخدم رباط مساعدة عند الحاجة.", "زد التكرارات قبل إضافة وزن."], aliases: ["Chin Up", "Pull Ups"], sets: 4, reps: 5...10, rest: 120),
        item("seated-row", "سحب كيبل جالس", "Seated Cable Row", .back, [.biceps], .cable, .beginner, .row,
             "سحب أفقي لتقوية منتصف الظهر وتحسين ثبات لوح الكتف.",
             ["اجلس بصدر مرفوع وظهر محايد.", "اسحب المقبض نحو البطن.", "اضمم لوحي الكتف ثم ارجع ببطء."],
             ["تحريك الجذع كثيرًا.", "رفع الكتفين.", "تقصير مدى الرجوع."],
             ["ابدأ بخفض الكتف قبل ثني المرفق.", "ثبت المعصم."], aliases: ["Cable Row", "Seated Row Machine", "سحب ارضي ضيق بالمثلث", "منشار جهاز"], sets: 4, reps: 8...12, rest: 90),
        item("barbell-row", "تجديف بالبار", "Barbell Row", .back, [.biceps, .core], .barbell, .advanced, .row,
             "تمرين مركب قوي لسمك الظهر ويتطلب تثبيتًا جيدًا للجذع.",
             ["اثنِ الورك وحافظ على ظهر محايد.", "اسحب البار نحو أسفل البطن.", "انزل البار دون فقدان الوضعية."],
             ["تقويس أسفل الظهر.", "رفع الجذع مع كل عدة.", "السحب بالزخم."],
             ["اختر وزنًا يسمح بثبات كامل.", "شد البطن طوال الجولة."], aliases: ["Bent Over Row"], sets: 4, reps: 6...10, rest: 120),
        item("one-arm-row", "تجديف دمبل يد واحدة", "One Arm Dumbbell Row", .back, [.biceps], .dumbbells, .beginner, .row,
             "يسمح بالتركيز على كل جهة وتصحيح فروقات القوة.",
             ["ثبت يدًا وركبة على البنش.", "اسحب الدمبل نحو الورك.", "انزل حتى تمدد دون تدوير الجذع."],
             ["فتح الجذع للأعلى.", "سحب الدمبل للصدر بدل الورك.", "رفع الكتف."],
             ["ابدأ بالجهة الأضعف.", "توقف لحظة عند أعلى الحركة."], aliases: ["Dumbbell Row", "منشار دامبل"], sets: 3, reps: 8...12, rest: 75),
        item("chest-supported-row", "تجديف مدعوم للصدر", "Chest Supported Row", .back, [.biceps], .machine, .beginner, .row,
             "يعزل الظهر ويقلل الضغط على أسفل الظهر.",
             ["ثبت الصدر على الوسادة.", "اسحب المرفقين للخلف.", "ارجع بتحكم دون فقدان اتصال الصدر."],
             ["رفع الصدر عن الوسادة.", "قصر المدى.", "شد الرقبة."],
             ["غير القبضة لتغيير التركيز.", "لا تحتاج وزنًا مبالغًا."], aliases: ["Machine Row"], sets: 3, reps: 8...12, rest: 90),
        item("straight-arm-pulldown", "سحب كيبل بذراع مستقيمة", "Straight Arm Pulldown", .back, [.triceps], .cable, .intermediate, .verticalPull,
             "عزل للاتس مع حركة كتف أكبر ومشاركة قليلة للبايسبس.",
             ["اثنِ الركبة قليلًا واثبت الجذع.", "اسحب البار نحو الفخذين بذراع شبه مستقيمة.", "ارجع حتى تمدد الظهر."],
             ["ثني المرفق كثيرًا.", "التأرجح بالجذع.", "رفع الكتف."],
             ["فكر في دفع البار بقوس.", "استخدم وزنًا متوسطًا."], aliases: ["Cable Pullover"], sets: 3, reps: 12...15, rest: 60),
        item("tbar-row", "تي بار رو", "T-Bar Row", .back, [.biceps], .machine, .intermediate, .row,
             "تجديف محمل يسمح بزيادة الحمل مع تركيز على سمك الظهر.",
             ["ثبت الصدر أو الجذع حسب الجهاز.", "اسحب المقبض نحو أسفل الصدر.", "ارجع حتى تمدد لوح الكتف."],
             ["رفع الكتف.", "تقصير المدى.", "استخدام زخم الجذع."],
             ["قد الحركة بالمرفق.", "اختر قبضة مريحة."], aliases: ["تي بار"], sets: 4, reps: 6...12, rest: 100),
        item("back-extension", "تمديد أسفل الظهر", "Back Extension", .back, [.glutes, .legs], .machine, .beginner, .hinge,
             "تقوية السلسلة الخلفية بحركة مفصل الورك على جهاز التمديد.",
             ["اضبط الوسادة أسفل عظم الحوض.", "انزل بالجذع مع ظهر محايد.", "اصعد حتى يصبح الجسم خطًا مستقيمًا."],
             ["التمدد الزائد عند القمة.", "تقويس الظهر.", "الصعود بالزخم."],
             ["اعصر المؤخرة عند الصعود.", "ابدأ بوزن الجسم."], aliases: ["اسفل الظهر جهاز"], sets: 3, reps: 10...15, rest: 60),
        item("deadlift", "ديدلفت", "Deadlift", .back, [.legs, .glutes, .core], .barbell, .advanced, .hinge,
             "تمرين مركب للقوة الخلفية يتطلب تقنية دقيقة.",
             ["ضع البار فوق منتصف القدم.", "ثبت الظهر واسحب الشد من البار.", "ادفع الأرض وقف بالورك والركبة معًا."],
             ["تقويس الظهر.", "ابتعاد البار عن الجسم.", "سحب البار بالذراع."],
             ["ابدأ بأوزان تقنية.", "لا تبالغ في إرجاع الظهر عند القمة."], aliases: ["Conventional Deadlift"], sets: 3, reps: 3...6, rest: 180),

        item("overhead-press", "ضغط كتف بالبار", "Barbell Overhead Press", .shoulders, [.triceps, .core], .barbell, .intermediate, .shoulderPress,
             "ضغط رأسي لبناء قوة الكتف والترايسبس وثبات الجذع.",
             ["ثبت البار على أعلى الصدر.", "شد البطن واضغط البار فوق الرأس.", "أدخل الرأس قليلًا تحت البار عند القمة."],
             ["تقوس أسفل الظهر.", "مسار بعيد عن الوجه.", "قبضة واسعة جدًا."],
             ["اضغط المؤخرة والبطن.", "استخدم قبضة أعلى المرفق مباشرة."], aliases: ["Military Press", "OHP"], sets: 4, reps: 5...10, rest: 120),
        item("dumbbell-shoulder", "ضغط كتف دمبل", "Dumbbell Shoulder Press", .shoulders, [.triceps], .dumbbells, .beginner, .shoulderPress,
             "ضغط كتف متوازن يسمح لكل جهة بالعمل بشكل مستقل.",
             ["اجلس بظهر ثابت.", "ابدأ الدمبل بمحاذاة الأذن.", "اضغط للأعلى ثم انزل بتحكم."],
             ["اصطدام الدمبلين.", "تقوس الظهر.", "نزول المرفق خلف الجسم."],
             ["حافظ على الساعد عموديًا.", "استخدم ظهر المقعد للدعم."], aliases: ["DB Shoulder Press", "Shoulder Press Machine", "جهاز اكتاف", "دامبل بريس اكتاف"], sets: 3, reps: 8...12, rest: 90),
        item("lateral-raise", "رفرفة جانبية", "Lateral Raise", .shoulders, [], .dumbbells, .beginner, .lateralRaise,
             "عزل للكتف الجانبي لزيادة عرض الكتف.",
             ["اثنِ المرفق قليلًا.", "ارفع الذراعين حتى مستوى الكتف.", "انزل ببطء مع بقاء الشد."],
             ["رفع الكتف للأذن.", "استخدام زخم.", "رفع اليد أعلى من المرفق بكثير."],
             ["قد اليد بالمرفق.", "الوزن الخفيف المتحكم أفضل."], aliases: ["Side Lateral Raise"], sets: 4, reps: 12...20, rest: 60),
        item("front-raise", "رفرفة أمامية", "Front Raise", .shoulders, [], .dumbbells, .beginner, .lateralRaise,
             "عزل للكتف الأمامي بحركة رفع أمامية.",
             ["ثبت الجذع والركبة مرتخية قليلًا.", "ارفع الدمبل حتى مستوى الكتف.", "انزل ببطء دون التأرجح."],
             ["رفع الوزن فوق الرأس.", "دفع الورك للأمام.", "قبض الكتف للأعلى."],
             ["يمكن التبديل بين الذراعين.", "لا تحتاج وزنًا عاليًا."], aliases: ["Dumbbell Front Raise", "Front Raises", "Plate Front Raise", "رفرفة امامي", "امامي بالقرص"], sets: 3, reps: 10...15, rest: 60),
        item("reverse-fly", "رفرفة خلفية", "Reverse Fly", .shoulders, [.back], .dumbbells, .intermediate, .fly,
             "يستهدف الكتف الخلفي ويساعد على توازن وضع الكتف.",
             ["اثنِ الورك مع ظهر محايد.", "افتح الذراعين للخارج.", "اضمم لوحي الكتف بخفة ثم ارجع."],
             ["رفع الكتف.", "تحويلها إلى تجديف.", "استخدام زخم."],
             ["استخدم دمبل خفيفًا.", "ثبت زاوية المرفق."], aliases: ["Rear Delt Fly", "Rear Delt Machine", "كتف خلفي جهاز"], sets: 3, reps: 12...20, rest: 60),
        item("face-pull", "فيس بول", "Face Pull", .shoulders, [.back], .cable, .beginner, .row,
             "تمرين للكتف الخلفي ودوران الكتف الخارجي وتحسين وضعية أعلى الجسم.",
             ["ثبت الحبل بارتفاع الوجه.", "اسحب نحو الجبهة وافتح اليدين.", "توقف لحظة ثم ارجع ببطء."],
             ["السحب للصدر.", "رفع الكتف.", "استخدام وزن ثقيل."],
             ["اجعل المرفق عاليًا ومريحًا.", "ركز على دوران الكتف للخارج."], aliases: ["Rope Face Pull"], sets: 3, reps: 12...20, rest: 60),

        item("shrug", "ترابيس", "Shrug", .shoulders, [.back], .dumbbells, .beginner, .lateralRaise,
             "رفع الكتفين لتدريب عضلة الترابيس العلوية.",
             ["قف مستقيمًا والذراع ممدودة.", "ارفع الكتفين للأعلى مباشرة.", "توقف لحظة ثم انزل بتحكم."],
             ["تدوير الكتفين.", "ثني المرفق.", "استخدام زخم الركبة."],
             ["المسار عمودي فقط.", "استخدم بارًا أو دمبل حسب الراحة."], aliases: ["Barbell Shrugs", "Dumbbell Shrugs", "ترابيس بار", "ترابيس دامبل"], sets: 4, reps: 10...15, rest: 75),
        item("barbell-curl", "بايسبس بار", "Barbell Curl", .biceps, [], .barbell, .beginner, .curl,
             "تمرين أساسي للبايسبس يسمح بتحميل جيد.",
             ["ثبت المرفق بجانب الجسم.", "ارفع البار دون تحريك الكتف.", "انزل حتى تمدد متحكم."],
             ["التأرجح بالظهر.", "تقدم المرفق.", "إسقاط البار بسرعة."],
             ["استخدم EZ Bar إذا أزعجك المعصم.", "حافظ على قبضة ثابتة."], aliases: ["EZ Bar Curl", "Barbell Biceps Curl", "بار واسع باي"], sets: 3, reps: 8...12, rest: 75),
        item("dumbbell-curl", "بايسبس دمبل", "Dumbbell Curl", .biceps, [], .dumbbells, .beginner, .curl,
             "تدريب مستقل لكل ذراع مع حرية تدوير المعصم.",
             ["ابدأ والذراع بجانب الجسم.", "لف الكف للأعلى أثناء الرفع.", "انزل ببطء حتى الاستقامة."],
             ["رفع الكتف.", "التأرجح.", "قصر المدى."],
             ["ابدأ بالذراع الأضعف.", "ثبت المرفق."], aliases: ["DB Curl", "Alternating DB Curl", "تبادل دامبل باي"], sets: 3, reps: 8...12, rest: 60),
        item("hammer-curl", "هامر كيرل", "Hammer Curl", .biceps, [], .dumbbells, .beginner, .curl,
             "يستهدف البراكيالس والساعد مع قبضة محايدة.",
             ["اجعل الكفين متقابلين.", "ارفع الدمبل مع ثبات المرفق.", "انزل بتحكم كامل."],
             ["تحويل القبضة أثناء الحركة.", "اندفاع المرفق للأمام.", "استخدام زخم."],
             ["يمكن تنفيذه بالتبادل.", "لا تضغط المعصم."], aliases: ["Dumbbell Hammer Curl"], sets: 3, reps: 10...15, rest: 60),
        item("preacher-curl", "بايسبس بريتشر", "Preacher Curl", .biceps, [], .machine, .intermediate, .curl,
             "يثبت الذراع ويقلل الغش أثناء تمرين البايسبس.",
             ["ثبت العضد كاملًا على الوسادة.", "ارفع الوزن دون رفع الكتف.", "انزل قرب الاستقامة من دون قفل مؤلم."],
             ["رفع المرفق عن الوسادة.", "السقوط في أسفل الحركة.", "وزن ثقيل."],
             ["توقف قبل القفل الكامل إذا شعرت بضغط.", "استخدم تحكمًا أبطأ."], aliases: ["Preacher Machine Curl"], sets: 3, reps: 8...12, rest: 75),
        item("concentration-curl", "تركيز بايسبس", "Concentration Curl", .biceps, [], .dumbbells, .beginner, .curl,
             "عزل للبايسبس مع تثبيت العضد على الفخذ.",
             ["اجلس وثبت العضد داخل الفخذ.", "ارفع الدمبل مع ثبات الكتف.", "انزل ببطء حتى تمدد الذراع."],
             ["رفع المرفق عن الفخذ.", "التفاف الجذع.", "إسقاط الوزن."],
             ["ابدأ بالذراع الأضعف.", "ركز على الانقباض لا الوزن."], aliases: ["Concentrated Curl", "تكوير باي"], sets: 3, reps: 10...15, rest: 60),
        item("cable-curl", "بايسبس كيبل", "Cable Curl", .biceps, [], .cable, .beginner, .curl,
             "شد مستمر للبايسبس ومناسب للتكرارات المتوسطة والعالية.",
             ["قف قريبًا من البكرة.", "ثبت المرفق وارفع المقبض.", "ارجع ببطء حتى تمدد كامل."],
             ["الميل للخلف.", "تحريك الكتف.", "سحب المعصم."],
             ["جرب الحبل أو البار المستقيم.", "ثبت الجذع."], aliases: ["Cable Biceps Curl"], sets: 3, reps: 10...15, rest: 60),

        item("pushdown", "دفع ترايسبس كيبل", "Cable Pushdown", .triceps, [], .cable, .beginner, .triceps,
             "عزل للترايسبس مع تحكم سهل في المقاومة.",
             ["ثبت المرفق بجانب الجسم.", "ادفع المقبض للأسفل حتى تمدد الذراع.", "ارجع دون تقدم المرفق."],
             ["فتح المرفق للخارج.", "الميل فوق الوزن.", "تحريك الكتف."],
             ["استخدم الحبل لمدى مريح.", "اعصر الترايسبس في الأسفل."], aliases: ["Tricep Pushdown", "Cable Push Down", "Rope Pushdown", "Straight Bar Pushdown", "Reverse Grip Pushdown", "تراي حبل", "مسطرة ضيق تراي", "مسطرة عكس تراي"], sets: 3, reps: 10...15, rest: 60),
        item("overhead-triceps", "تمديد ترايسبس فوق الرأس", "Overhead Triceps Extension", .triceps, [], .dumbbells, .intermediate, .triceps,
             "يركز على الرأس الطويل للترايسبس في وضعية فوق الرأس.",
             ["ثبت المرفقين قرب الرأس.", "انزل الوزن خلف الرأس بتحكم.", "مد الذراع دون تحريك الكتف."],
             ["فتح المرفق كثيرًا.", "تقوس الظهر.", "نزول سريع."],
             ["يمكن استخدام كيبل أو دمبل.", "شد البطن."], aliases: ["One Arm Lying Dumbbell Tricep Extension", "French Press", "Overhead Extension", "تراي من فوق الراس"], sets: 3, reps: 10...15, rest: 75),
        item("skull-crusher", "سكُل كراشر", "Skull Crusher", .triceps, [], .barbell, .intermediate, .triceps,
             "تمديد ترايسبس مستلقٍ باستخدام بار أو دمبل.",
             ["ثبت العضد مائلًا قليلًا للخلف.", "اثنِ المرفق وأنزل الوزن قرب الجبهة.", "مد المرفق مع بقاء العضد ثابتًا."],
             ["تحريك الكتف.", "فتح المرفق.", "إنزال الوزن بسرعة."],
             ["استخدم EZ Bar لراحة المعصم.", "ابدأ بوزن متوسط."], aliases: ["Lying Triceps Extension"], sets: 3, reps: 8...12, rest: 75),
        item("dips", "متوازي", "Dips", .triceps, [.chest, .shoulders], .bodyweight, .intermediate, .dip,
             "تمرين وزن جسم قوي للترايسبس والصدر حسب ميل الجذع.",
             ["ثبت الكتفين للأسفل.", "انزل حتى زاوية مريحة للمرفق.", "ادفع للأعلى دون قفل عنيف."],
             ["هبوط عميق مؤلم.", "رفع الكتف.", "التأرجح."],
             ["استخدم مساعدة إذا لزم.", "ميل أقل يركز أكثر على الترايسبس."], aliases: ["Parallel Bar Dips", "Seated Dips Machine", "جهاز تراي غطس"], sets: 3, reps: 6...12, rest: 120),

        item("back-squat", "سكوات بالبار", "Back Squat", .legs, [.glutes, .core], .barbell, .advanced, .squat,
             "تمرين مركب رئيسي للأرجل والقوة العامة.",
             ["ثبت البار أعلى الظهر وخذ وقفة مناسبة.", "انزل بالورك والركبة مع بقاء القدم ثابتة.", "ادفع الأرض واصعد مع الحفاظ على الجذع."],
             ["انهيار الركبة للداخل.", "رفع الكعب.", "تقويس الظهر."],
             ["اختر عمقًا تستطيع التحكم به.", "استخدم حواجز أمان."], aliases: ["Barbell Squat", "Squat", "Squats", "سكوات"], sets: 4, reps: 5...10, rest: 150),
        item("leg-press", "ضغط أرجل", "Leg Press", .legs, [.glutes], .machine, .beginner, .legMachine,
             "تمرين جهاز يسمح بتحميل الأرجل مع دعم الظهر.",
             ["ضع القدمين بثبات على المنصة.", "انزل حتى مدى مريح دون التفاف الحوض.", "ادفع بالقدم كاملة دون قفل الركبة."],
             ["قفل الركبة.", "نزول الحوض عن المقعد.", "دفع الكعب بعيدًا عن المنصة."],
             ["غير موضع القدم حسب راحتك.", "لا تنزل أعمق من قدرتك."], aliases: ["45 Degree Leg Press"], sets: 4, reps: 8...15, rest: 120),
        item("romanian-deadlift", "رومانيان ديدلفت", "Romanian Deadlift", .legs, [.glutes, .back], .barbell, .intermediate, .hinge,
             "يركز على أوتار الركبة والمؤخرة من خلال حركة مفصل الورك.",
             ["ابدأ واقفًا والبار قريب من الفخذ.", "ادفع الورك للخلف مع انثناء بسيط للركبة.", "توقف عند تمدد أوتار الركبة ثم ادفع الورك للأمام."],
             ["تحويلها إلى سكوات.", "ابتعاد البار عن الساق.", "تقويس الظهر."],
             ["المدى يعتمد على مرونتك.", "حافظ على ضغط القدم كاملة."], aliases: ["RDL"], sets: 4, reps: 6...12, rest: 120),
        item("leg-extension", "تمديد الأرجل", "Leg Extension", .legs, [], .machine, .beginner, .legMachine,
             "عزل للعضلة الأمامية للفخذ.",
             ["اضبط محور الجهاز مع الركبة.", "مد الساق حتى انقباض قوي.", "انزل ببطء دون سقوط الوزن."],
             ["قفل الركبة بعنف.", "رفع الورك.", "السرعة العالية."],
             ["توقف لحظة في الأعلى.", "استخدم مدى غير مؤلم."], aliases: ["Leg Extensions"], sets: 3, reps: 10...15, rest: 60),
        item("leg-curl", "ثني الأرجل", "Leg Curl", .legs, [], .machine, .beginner, .legMachine,
             "عزل لأوتار الركبة باستخدام جهاز الثني.",
             ["اضبط الوسادة فوق الكاحل.", "اثنِ الركبة حتى انقباض مريح.", "ارجع ببطء حتى التمدد."],
             ["رفع الحوض.", "استخدام زخم.", "قصر المدى."],
             ["اضغط الحوض على المقعد.", "تحكم في الرجوع."], aliases: ["Lying Leg Curl", "Seated Leg Curl", "Leg Curls", "رفرفة خلفي ارجل"], sets: 3, reps: 10...15, rest: 60),
        item("bulgarian-split", "بلغاريان سبليت سكوات", "Bulgarian Split Squat", .legs, [.glutes, .core], .dumbbells, .intermediate, .lunge,
             "تمرين رجل واحدة لتطوير القوة والتوازن.",
             ["ضع القدم الخلفية على بنش.", "انزل بالركبة الخلفية نحو الأرض.", "ادفع بالقدم الأمامية واثبت الركبة."],
             ["وقفة قصيرة جدًا.", "انهيار الركبة للداخل.", "دفع القدم الخلفية."],
             ["ابدأ بوزن الجسم.", "اضبط المسافة قبل حمل الدمبل."], aliases: ["Rear Foot Elevated Split Squat"], sets: 3, reps: 8...12, rest: 90),
        item("walking-lunge", "لانجز مشي", "Walking Lunge", .legs, [.glutes, .core], .dumbbells, .intermediate, .lunge,
             "تمرين ديناميكي للأرجل والمؤخرة والتوازن.",
             ["خذ خطوة مستقرة للأمام.", "انزل الركبة الخلفية قرب الأرض.", "ادفع بالقدم الأمامية وانتقل للخطوة التالية."],
             ["خطوة قصيرة جدًا.", "ميل الجذع المبالغ.", "اصطدام الركبة بالأرض."],
             ["ثبت النظر أمامك.", "استخدم مساحة آمنة."], aliases: ["Dumbbell Lunges", "Lunges", "طعن"], sets: 3, reps: 10...16, rest: 90),
        item("hack-squat", "هاك سكوات", "Hack Squat", .legs, [.glutes], .machine, .intermediate, .squat,
             "سكوات على جهاز بمسار ثابت يركز على عضلات الفخذ.",
             ["ثبت الظهر والكتف على الوسادات.", "انزل حتى عمق متحكم.", "ادفع بالقدم كاملة دون قفل الركبة."],
             ["رفع الكعب.", "انهيار الركبة للداخل.", "نزول الحوض عن الوسادة."],
             ["ضع القدم بما يناسب طولك.", "ابدأ بوزن محافظ."], aliases: ["Hack Squats"], sets: 4, reps: 8...12, rest: 120),
        item("hip-adductor", "جهاز ضم الفخذ", "Hip Adductor", .legs, [.glutes], .machine, .beginner, .legMachine,
             "عزل للعضلات الداخلية للفخذ باستخدام جهاز الضم.",
             ["اضبط مدى فتح الجهاز بشكل مريح.", "اضمم الرجلين بتحكم.", "ارجع ببطء دون ارتداد."],
             ["مدى فتح مؤلم.", "إغلاق الوزن بالزخم.", "رفع الحوض."],
             ["ثبت الظهر على المقعد.", "استخدم تكرارات متحكم بها."], aliases: ["جهاز داخلي"], sets: 3, reps: 12...20, rest: 60),
        item("hip-thrust", "هيب ثرست", "Hip Thrust", .glutes, [.legs, .core], .barbell, .intermediate, .hipThrust,
             "تمرين قوي للمؤخرة مع قمة انقباض واضحة.",
             ["ثبت أعلى الظهر على البنش.", "ضع القدمين بحيث تصبح الساق عمودية عند القمة.", "ارفع الورك واعصر المؤخرة دون تقوس الظهر."],
             ["رفع الوزن بأسفل الظهر.", "وضع القدم بعيد أو قريب جدًا.", "دفع الرأس للخلف."],
             ["استخدم وسادة للبار.", "اجعل الذقن للداخل."], aliases: ["Barbell Hip Thrust"], sets: 4, reps: 8...15, rest: 120),
        item("calf-raise", "رفع السمانة", "Calf Raise", .legs, [], .machine, .beginner, .calfRaise,
             "عزل لعضلات السمانة من خلال رفع الكعب.",
             ["ضع مقدمة القدم على الحافة.", "انزل الكعب حتى تمدد مريح.", "ارفع لأعلى نقطة وتوقف لحظة."],
             ["الحركة السريعة.", "ثني الركبة بلا قصد.", "مدى قصير."],
             ["استخدم وقفة في الأعلى والأسفل.", "تجنب الارتداد."], aliases: ["Standing Calf Raise", "Seated Calf Raise", "بطات جهاز"], sets: 4, reps: 10...20, rest: 60),

        item("plank", "بلانك", "Plank", .core, [.glutes], .bodyweight, .beginner, .plank,
             "تثبيت للبطن والجذع بوضعية مستقيمة.",
             ["ضع المرفق تحت الكتف.", "شد البطن والمؤخرة.", "حافظ على خط مستقيم من الرأس للكعب."],
             ["هبوط الحوض.", "رفع المؤخرة عاليًا.", "حبس النفس."],
             ["ابدأ بمدد قصيرة متقنة.", "تنفس بهدوء."], aliases: ["Forearm Plank"], sets: 3, reps: 30...60, rest: 60),
        item("cable-crunch", "كرنش كيبل", "Cable Crunch", .core, [], .cable, .intermediate, .core,
             "كرنش بمقاومة كيبل لتطوير عضلات البطن.",
             ["اثبت على الركبتين والحبل قرب الرأس.", "اثنِ الجذع باستخدام البطن.", "ارجع ببطء دون تحريك الورك كثيرًا."],
             ["سحب الحبل بالذراع.", "الجلوس على الكعب.", "تحريك الورك بدل الجذع."],
             ["فكر في تقريب الضلوع من الحوض.", "استخدم وزنًا يسمح بالتحكم."], aliases: ["Kneeling Cable Crunch"], sets: 3, reps: 10...15, rest: 60),
        item("hanging-leg-raise", "رفع الرجلين معلق", "Hanging Leg Raise", .core, [], .bodyweight, .advanced, .core,
             "تمرين بطن متقدم يتطلب قبضة وثباتًا جيدًا.",
             ["ابدأ بتعليق ثابت دون تأرجح.", "لف الحوض وارفع الركبتين أو الرجلين.", "انزل ببطء حتى توقف كامل."],
             ["التأرجح.", "رفع الفخذ دون لف الحوض.", "هبوط سريع."],
             ["ابدأ برفع الركبتين.", "استخدم كرسي الكابتن للتسهيل."], aliases: ["Hanging Knee Raise"], sets: 3, reps: 8...15, rest: 75)
    ]
}

// MARK: - Exercise artwork

struct ExerciseArtworkView: View {
    let exercise: ExerciseDefinition
    var compact = false
    var stage: Int = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [FitTheme.backgroundSoft, exercise.primaryMuscle.tint.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            ExercisePoseCanvas(exercise: exercise, stage: stage)
                .padding(compact ? 8 : 14)
            VStack {
                HStack {
                    Label(exercise.primaryMuscle.rawValue, systemImage: exercise.primaryMuscle.systemImage)
                        .font(compact ? .caption2.bold() : .caption.bold())
                        .foregroundStyle(exercise.primaryMuscle.tint)
                        .padding(.horizontal, compact ? 7 : 10)
                        .padding(.vertical, compact ? 4 : 6)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                }
                Spacer()
                if !compact {
                    HStack {
                        Text(stage == 0 ? "وضع البداية" : "نهاية الحركة")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Label(exercise.equipment.rawValue, systemImage: exercise.equipment.systemImage)
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            .padding(compact ? 7 : 13)
        }
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("رسم توضيحي لتمرين \(exercise.displayName)")
    }
}

private struct ExercisePoseCanvas: View {
    let exercise: ExerciseDefinition
    let stage: Int

    var body: some View {
        Canvas { context, size in
            let pose = PoseLibrary.pose(exercise.pose, stage: stage)
            let scale = min(size.width, size.height)
            func point(_ value: CGPoint) -> CGPoint {
                CGPoint(x: value.x * size.width, y: value.y * size.height)
            }
            func line(_ a: CGPoint, _ b: CGPoint, color: Color = .white.opacity(0.78), width: CGFloat = 0.055) {
                var path = Path()
                path.move(to: point(a))
                path.addLine(to: point(b))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(3, scale * width), lineCap: .round, lineJoin: .round))
            }
            func circle(_ center: CGPoint, radius: CGFloat, color: Color) {
                let p = point(center)
                let r = radius * scale
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }

            drawEquipment(context: &context, size: size, pose: pose, kind: exercise.pose, stage: stage)

            let bodyColor = Color.white.opacity(0.76)
            line(pose.neck, pose.hip, color: bodyColor, width: 0.07)
            line(pose.leftShoulder, pose.rightShoulder, color: bodyColor, width: 0.065)
            line(pose.leftShoulder, pose.leftElbow, color: bodyColor)
            line(pose.leftElbow, pose.leftHand, color: bodyColor)
            line(pose.rightShoulder, pose.rightElbow, color: bodyColor)
            line(pose.rightElbow, pose.rightHand, color: bodyColor)
            line(pose.hip, pose.leftKnee, color: bodyColor, width: 0.065)
            line(pose.leftKnee, pose.leftFoot, color: bodyColor, width: 0.06)
            line(pose.hip, pose.rightKnee, color: bodyColor, width: 0.065)
            line(pose.rightKnee, pose.rightFoot, color: bodyColor, width: 0.06)
            circle(pose.head, radius: 0.07, color: Color.white.opacity(0.88))
            circle(pose.neck, radius: 0.04, color: bodyColor)
            circle(pose.hip, radius: 0.055, color: bodyColor)

            let target = exercise.primaryMuscle.tint
            switch exercise.primaryMuscle {
            case .chest:
                circle(CGPoint(x: (pose.leftShoulder.x + pose.rightShoulder.x) / 2, y: (pose.neck.y + pose.hip.y) / 2 - 0.03), radius: 0.075, color: target.opacity(0.9))
            case .back:
                line(pose.neck, pose.hip, color: target, width: 0.09)
            case .shoulders:
                circle(pose.leftShoulder, radius: 0.055, color: target)
                circle(pose.rightShoulder, radius: 0.055, color: target)
            case .biceps:
                line(pose.leftShoulder, pose.leftElbow, color: target, width: 0.075)
                line(pose.rightShoulder, pose.rightElbow, color: target, width: 0.075)
            case .triceps:
                line(pose.leftElbow, pose.leftHand, color: target, width: 0.075)
                line(pose.rightElbow, pose.rightHand, color: target, width: 0.075)
            case .legs:
                line(pose.hip, pose.leftKnee, color: target, width: 0.085)
                line(pose.hip, pose.rightKnee, color: target, width: 0.085)
            case .glutes:
                circle(pose.hip, radius: 0.085, color: target.opacity(0.95))
            case .core:
                line(pose.neck, pose.hip, color: target, width: 0.105)
            case .all:
                circle(pose.hip, radius: 0.055, color: FitTheme.accent)
            }
        }
    }

    private func drawEquipment(context: inout GraphicsContext, size: CGSize, pose: BodyPose, kind: ExercisePoseKind, stage: Int) {
        let scale = min(size.width, size.height)
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * size.width, y: q.y * size.height) }
        func stroke(_ points: [CGPoint], color: Color = .white.opacity(0.25), width: CGFloat = 0.025) {
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: p(first))
            for point in points.dropFirst() { path.addLine(to: p(point)) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(2, scale * width), lineCap: .round, lineJoin: .round))
        }
        func disk(_ q: CGPoint, radius: CGFloat) {
            let center = p(q); let r = radius * scale
            context.fill(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)), with: .color(Color.white.opacity(0.28)))
        }

        switch kind {
        case .horizontalPress, .inclinePress, .fly:
            stroke([CGPoint(x: 0.18, y: 0.68), CGPoint(x: 0.78, y: kind == .inclinePress ? 0.42 : 0.68)], width: 0.035)
            if kind != .fly {
                stroke([pose.leftHand, pose.rightHand], color: .white.opacity(0.55), width: 0.025)
                disk(CGPoint(x: pose.leftHand.x - 0.05, y: pose.leftHand.y), radius: 0.045)
                disk(CGPoint(x: pose.rightHand.x + 0.05, y: pose.rightHand.y), radius: 0.045)
            } else {
                disk(pose.leftHand, radius: 0.04); disk(pose.rightHand, radius: 0.04)
            }
        case .verticalPull:
            stroke([CGPoint(x: 0.16, y: 0.13), CGPoint(x: 0.84, y: 0.13)], color: .white.opacity(0.45), width: 0.025)
            stroke([CGPoint(x: 0.50, y: 0.13), CGPoint(x: 0.50, y: 0.28)], width: 0.015)
        case .row:
            stroke([CGPoint(x: 0.12, y: 0.76), CGPoint(x: 0.88, y: 0.76)], width: 0.02)
            disk(pose.leftHand, radius: 0.035); disk(pose.rightHand, radius: 0.035)
        case .hinge, .squat:
            stroke([pose.leftHand, pose.rightHand], color: .white.opacity(0.5), width: 0.025)
            disk(CGPoint(x: pose.leftHand.x - 0.05, y: pose.leftHand.y), radius: 0.045)
            disk(CGPoint(x: pose.rightHand.x + 0.05, y: pose.rightHand.y), radius: 0.045)
            stroke([CGPoint(x: 0.12, y: 0.86), CGPoint(x: 0.88, y: 0.86)], width: 0.018)
        case .lunge, .curl, .shoulderPress, .lateralRaise:
            disk(pose.leftHand, radius: 0.04); disk(pose.rightHand, radius: 0.04)
            stroke([CGPoint(x: 0.12, y: 0.86), CGPoint(x: 0.88, y: 0.86)], width: 0.018)
        case .triceps:
            stroke([CGPoint(x: 0.78, y: 0.12), CGPoint(x: 0.78, y: 0.82)], width: 0.018)
            stroke([CGPoint(x: 0.78, y: 0.12), pose.rightHand], width: 0.012)
        case .dip:
            stroke([CGPoint(x: 0.20, y: 0.55), CGPoint(x: 0.42, y: 0.55)], width: 0.025)
            stroke([CGPoint(x: 0.58, y: 0.55), CGPoint(x: 0.80, y: 0.55)], width: 0.025)
        case .legMachine:
            stroke([CGPoint(x: 0.18, y: 0.72), CGPoint(x: 0.68, y: 0.72)], width: 0.035)
            stroke([CGPoint(x: 0.68, y: 0.72), CGPoint(x: 0.82, y: 0.48)], width: 0.03)
        case .hipThrust:
            stroke([CGPoint(x: 0.16, y: 0.58), CGPoint(x: 0.43, y: 0.58)], width: 0.04)
            stroke([CGPoint(x: 0.12, y: 0.86), CGPoint(x: 0.88, y: 0.86)], width: 0.018)
        case .calfRaise:
            stroke([CGPoint(x: 0.30, y: 0.84), CGPoint(x: 0.70, y: 0.84)], width: 0.035)
        case .core, .plank, .pushUp:
            stroke([CGPoint(x: 0.10, y: 0.82), CGPoint(x: 0.90, y: 0.82)], width: 0.018)
        }
    }
}

private struct BodyPose {
    let head: CGPoint
    let neck: CGPoint
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftElbow: CGPoint
    let rightElbow: CGPoint
    let leftHand: CGPoint
    let rightHand: CGPoint
    let hip: CGPoint
    let leftKnee: CGPoint
    let rightKnee: CGPoint
    let leftFoot: CGPoint
    let rightFoot: CGPoint
}

private enum PoseLibrary {
    static func pose(_ kind: ExercisePoseKind, stage: Int) -> BodyPose {
        let end = stage % 2 == 1
        switch kind {
        case .horizontalPress:
            return BodyPose(head: .init(x: 0.28, y: 0.58), neck: .init(x: 0.35, y: 0.56), leftShoulder: .init(x: 0.41, y: 0.52), rightShoulder: .init(x: 0.48, y: 0.49), leftElbow: .init(x: end ? 0.41 : 0.30, y: end ? 0.30 : 0.43), rightElbow: .init(x: end ? 0.58 : 0.64, y: end ? 0.27 : 0.40), leftHand: .init(x: 0.46, y: end ? 0.16 : 0.30), rightHand: .init(x: 0.61, y: end ? 0.16 : 0.29), hip: .init(x: 0.62, y: 0.61), leftKnee: .init(x: 0.74, y: 0.72), rightKnee: .init(x: 0.68, y: 0.78), leftFoot: .init(x: 0.85, y: 0.78), rightFoot: .init(x: 0.76, y: 0.85))
        case .inclinePress:
            return BodyPose(head: .init(x: 0.31, y: 0.47), neck: .init(x: 0.37, y: 0.49), leftShoulder: .init(x: 0.42, y: 0.46), rightShoulder: .init(x: 0.50, y: 0.44), leftElbow: .init(x: end ? 0.43 : 0.32, y: end ? 0.25 : 0.38), rightElbow: .init(x: end ? 0.61 : 0.66, y: end ? 0.22 : 0.36), leftHand: .init(x: 0.47, y: end ? 0.12 : 0.27), rightHand: .init(x: 0.63, y: end ? 0.12 : 0.26), hip: .init(x: 0.62, y: 0.63), leftKnee: .init(x: 0.73, y: 0.74), rightKnee: .init(x: 0.67, y: 0.79), leftFoot: .init(x: 0.84, y: 0.80), rightFoot: .init(x: 0.76, y: 0.86))
        case .fly:
            return BodyPose(head: .init(x: 0.28, y: 0.58), neck: .init(x: 0.35, y: 0.56), leftShoulder: .init(x: 0.42, y: 0.51), rightShoulder: .init(x: 0.50, y: 0.49), leftElbow: .init(x: end ? 0.45 : 0.23, y: end ? 0.30 : 0.36), rightElbow: .init(x: end ? 0.58 : 0.77, y: end ? 0.28 : 0.34), leftHand: .init(x: end ? 0.50 : 0.16, y: end ? 0.20 : 0.30), rightHand: .init(x: end ? 0.55 : 0.84, y: end ? 0.19 : 0.29), hip: .init(x: 0.63, y: 0.62), leftKnee: .init(x: 0.74, y: 0.73), rightKnee: .init(x: 0.68, y: 0.79), leftFoot: .init(x: 0.84, y: 0.80), rightFoot: .init(x: 0.76, y: 0.86))
        case .pushUp, .plank:
            return BodyPose(head: .init(x: 0.20, y: end ? 0.62 : 0.48), neck: .init(x: 0.27, y: end ? 0.62 : 0.50), leftShoulder: .init(x: 0.34, y: end ? 0.60 : 0.52), rightShoulder: .init(x: 0.38, y: end ? 0.61 : 0.53), leftElbow: .init(x: 0.30, y: end ? 0.73 : 0.68), rightElbow: .init(x: 0.40, y: end ? 0.73 : 0.68), leftHand: .init(x: 0.27, y: 0.81), rightHand: .init(x: 0.43, y: 0.81), hip: .init(x: 0.58, y: end ? 0.64 : 0.58), leftKnee: .init(x: 0.72, y: end ? 0.68 : 0.63), rightKnee: .init(x: 0.71, y: end ? 0.71 : 0.66), leftFoot: .init(x: 0.87, y: 0.79), rightFoot: .init(x: 0.86, y: 0.82))
        case .verticalPull:
            return BodyPose(head: .init(x: 0.50, y: 0.35), neck: .init(x: 0.50, y: 0.42), leftShoulder: .init(x: 0.43, y: 0.45), rightShoulder: .init(x: 0.57, y: 0.45), leftElbow: .init(x: end ? 0.35 : 0.30, y: end ? 0.45 : 0.27), rightElbow: .init(x: end ? 0.65 : 0.70, y: end ? 0.45 : 0.27), leftHand: .init(x: end ? 0.42 : 0.25, y: end ? 0.35 : 0.13), rightHand: .init(x: end ? 0.58 : 0.75, y: end ? 0.35 : 0.13), hip: .init(x: 0.50, y: 0.65), leftKnee: .init(x: 0.42, y: 0.76), rightKnee: .init(x: 0.58, y: 0.76), leftFoot: .init(x: 0.40, y: 0.88), rightFoot: .init(x: 0.60, y: 0.88))
        case .row:
            return BodyPose(head: .init(x: 0.33, y: 0.35), neck: .init(x: 0.39, y: 0.41), leftShoulder: .init(x: 0.43, y: 0.43), rightShoulder: .init(x: 0.49, y: 0.46), leftElbow: .init(x: end ? 0.40 : 0.58, y: end ? 0.55 : 0.50), rightElbow: .init(x: end ? 0.49 : 0.67, y: end ? 0.57 : 0.53), leftHand: .init(x: end ? 0.51 : 0.72, y: end ? 0.60 : 0.55), rightHand: .init(x: end ? 0.58 : 0.79, y: end ? 0.62 : 0.58), hip: .init(x: 0.57, y: 0.62), leftKnee: .init(x: 0.48, y: 0.76), rightKnee: .init(x: 0.66, y: 0.75), leftFoot: .init(x: 0.43, y: 0.87), rightFoot: .init(x: 0.73, y: 0.87))
        case .hinge:
            return BodyPose(head: .init(x: 0.31, y: end ? 0.24 : 0.42), neck: .init(x: 0.38, y: end ? 0.31 : 0.46), leftShoulder: .init(x: 0.42, y: end ? 0.34 : 0.49), rightShoulder: .init(x: 0.48, y: end ? 0.35 : 0.50), leftElbow: .init(x: 0.45, y: end ? 0.50 : 0.61), rightElbow: .init(x: 0.54, y: end ? 0.50 : 0.61), leftHand: .init(x: 0.47, y: end ? 0.64 : 0.72), rightHand: .init(x: 0.57, y: end ? 0.64 : 0.72), hip: .init(x: 0.55, y: end ? 0.52 : 0.57), leftKnee: .init(x: 0.45, y: 0.72), rightKnee: .init(x: 0.63, y: 0.72), leftFoot: .init(x: 0.43, y: 0.88), rightFoot: .init(x: 0.66, y: 0.88))
        case .squat:
            return BodyPose(head: .init(x: 0.50, y: end ? 0.38 : 0.22), neck: .init(x: 0.50, y: end ? 0.45 : 0.30), leftShoulder: .init(x: 0.42, y: end ? 0.47 : 0.34), rightShoulder: .init(x: 0.58, y: end ? 0.47 : 0.34), leftElbow: .init(x: 0.37, y: end ? 0.55 : 0.42), rightElbow: .init(x: 0.63, y: end ? 0.55 : 0.42), leftHand: .init(x: 0.45, y: end ? 0.47 : 0.34), rightHand: .init(x: 0.55, y: end ? 0.47 : 0.34), hip: .init(x: 0.50, y: end ? 0.64 : 0.54), leftKnee: .init(x: 0.37, y: end ? 0.75 : 0.70), rightKnee: .init(x: 0.63, y: end ? 0.75 : 0.70), leftFoot: .init(x: 0.31, y: 0.88), rightFoot: .init(x: 0.69, y: 0.88))
        case .lunge:
            return BodyPose(head: .init(x: 0.48, y: 0.20), neck: .init(x: 0.48, y: 0.28), leftShoulder: .init(x: 0.41, y: 0.32), rightShoulder: .init(x: 0.55, y: 0.32), leftElbow: .init(x: 0.37, y: 0.48), rightElbow: .init(x: 0.59, y: 0.48), leftHand: .init(x: 0.36, y: 0.62), rightHand: .init(x: 0.60, y: 0.62), hip: .init(x: 0.49, y: 0.53), leftKnee: .init(x: end ? 0.31 : 0.38, y: end ? 0.70 : 0.66), rightKnee: .init(x: end ? 0.68 : 0.61, y: end ? 0.76 : 0.69), leftFoot: .init(x: 0.21, y: 0.87), rightFoot: .init(x: 0.80, y: 0.87))
        case .legMachine:
            return BodyPose(head: .init(x: 0.30, y: 0.37), neck: .init(x: 0.36, y: 0.43), leftShoulder: .init(x: 0.40, y: 0.46), rightShoulder: .init(x: 0.46, y: 0.48), leftElbow: .init(x: 0.34, y: 0.59), rightElbow: .init(x: 0.51, y: 0.60), leftHand: .init(x: 0.28, y: 0.68), rightHand: .init(x: 0.56, y: 0.68), hip: .init(x: 0.57, y: 0.64), leftKnee: .init(x: end ? 0.72 : 0.68, y: end ? 0.63 : 0.75), rightKnee: .init(x: end ? 0.73 : 0.70, y: end ? 0.66 : 0.78), leftFoot: .init(x: end ? 0.87 : 0.75, y: end ? 0.62 : 0.86), rightFoot: .init(x: end ? 0.88 : 0.78, y: end ? 0.66 : 0.88))
        case .shoulderPress:
            return BodyPose(head: .init(x: 0.50, y: 0.28), neck: .init(x: 0.50, y: 0.36), leftShoulder: .init(x: 0.42, y: 0.40), rightShoulder: .init(x: 0.58, y: 0.40), leftElbow: .init(x: end ? 0.42 : 0.32, y: end ? 0.23 : 0.45), rightElbow: .init(x: end ? 0.58 : 0.68, y: end ? 0.23 : 0.45), leftHand: .init(x: end ? 0.45 : 0.36, y: end ? 0.10 : 0.32), rightHand: .init(x: end ? 0.55 : 0.64, y: end ? 0.10 : 0.32), hip: .init(x: 0.50, y: 0.62), leftKnee: .init(x: 0.42, y: 0.76), rightKnee: .init(x: 0.58, y: 0.76), leftFoot: .init(x: 0.38, y: 0.88), rightFoot: .init(x: 0.62, y: 0.88))
        case .lateralRaise:
            return BodyPose(head: .init(x: 0.50, y: 0.22), neck: .init(x: 0.50, y: 0.30), leftShoulder: .init(x: 0.43, y: 0.34), rightShoulder: .init(x: 0.57, y: 0.34), leftElbow: .init(x: end ? 0.24 : 0.39, y: end ? 0.36 : 0.52), rightElbow: .init(x: end ? 0.76 : 0.61, y: end ? 0.36 : 0.52), leftHand: .init(x: end ? 0.10 : 0.37, y: end ? 0.37 : 0.68), rightHand: .init(x: end ? 0.90 : 0.63, y: end ? 0.37 : 0.68), hip: .init(x: 0.50, y: 0.58), leftKnee: .init(x: 0.43, y: 0.74), rightKnee: .init(x: 0.57, y: 0.74), leftFoot: .init(x: 0.40, y: 0.88), rightFoot: .init(x: 0.60, y: 0.88))
        case .curl:
            return BodyPose(head: .init(x: 0.50, y: 0.22), neck: .init(x: 0.50, y: 0.30), leftShoulder: .init(x: 0.43, y: 0.34), rightShoulder: .init(x: 0.57, y: 0.34), leftElbow: .init(x: 0.40, y: 0.52), rightElbow: .init(x: 0.60, y: 0.52), leftHand: .init(x: end ? 0.36 : 0.39, y: end ? 0.39 : 0.70), rightHand: .init(x: end ? 0.64 : 0.61, y: end ? 0.39 : 0.70), hip: .init(x: 0.50, y: 0.58), leftKnee: .init(x: 0.43, y: 0.74), rightKnee: .init(x: 0.57, y: 0.74), leftFoot: .init(x: 0.40, y: 0.88), rightFoot: .init(x: 0.60, y: 0.88))
        case .triceps:
            return BodyPose(head: .init(x: 0.50, y: 0.22), neck: .init(x: 0.50, y: 0.30), leftShoulder: .init(x: 0.43, y: 0.34), rightShoulder: .init(x: 0.57, y: 0.34), leftElbow: .init(x: 0.42, y: 0.50), rightElbow: .init(x: 0.58, y: 0.50), leftHand: .init(x: end ? 0.42 : 0.38, y: end ? 0.72 : 0.55), rightHand: .init(x: end ? 0.58 : 0.62, y: end ? 0.72 : 0.55), hip: .init(x: 0.50, y: 0.58), leftKnee: .init(x: 0.43, y: 0.74), rightKnee: .init(x: 0.57, y: 0.74), leftFoot: .init(x: 0.40, y: 0.88), rightFoot: .init(x: 0.60, y: 0.88))
        case .dip:
            return BodyPose(head: .init(x: 0.50, y: end ? 0.40 : 0.26), neck: .init(x: 0.50, y: end ? 0.47 : 0.34), leftShoulder: .init(x: 0.42, y: end ? 0.50 : 0.38), rightShoulder: .init(x: 0.58, y: end ? 0.50 : 0.38), leftElbow: .init(x: 0.34, y: end ? 0.54 : 0.58), rightElbow: .init(x: 0.66, y: end ? 0.54 : 0.58), leftHand: .init(x: 0.30, y: 0.55), rightHand: .init(x: 0.70, y: 0.55), hip: .init(x: 0.50, y: end ? 0.66 : 0.58), leftKnee: .init(x: 0.43, y: 0.76), rightKnee: .init(x: 0.57, y: 0.76), leftFoot: .init(x: 0.47, y: 0.88), rightFoot: .init(x: 0.53, y: 0.88))
        case .hipThrust:
            return BodyPose(head: .init(x: 0.23, y: 0.50), neck: .init(x: 0.30, y: 0.54), leftShoulder: .init(x: 0.36, y: 0.54), rightShoulder: .init(x: 0.41, y: 0.56), leftElbow: .init(x: 0.35, y: 0.67), rightElbow: .init(x: 0.46, y: 0.68), leftHand: .init(x: 0.45, y: 0.64), rightHand: .init(x: 0.54, y: 0.65), hip: .init(x: 0.58, y: end ? 0.49 : 0.68), leftKnee: .init(x: 0.70, y: 0.70), rightKnee: .init(x: 0.74, y: 0.73), leftFoot: .init(x: 0.83, y: 0.84), rightFoot: .init(x: 0.87, y: 0.86))
        case .calfRaise:
            return BodyPose(head: .init(x: 0.50, y: 0.20), neck: .init(x: 0.50, y: 0.28), leftShoulder: .init(x: 0.43, y: 0.32), rightShoulder: .init(x: 0.57, y: 0.32), leftElbow: .init(x: 0.40, y: 0.49), rightElbow: .init(x: 0.60, y: 0.49), leftHand: .init(x: 0.40, y: 0.63), rightHand: .init(x: 0.60, y: 0.63), hip: .init(x: 0.50, y: 0.55), leftKnee: .init(x: 0.44, y: 0.71), rightKnee: .init(x: 0.56, y: 0.71), leftFoot: .init(x: end ? 0.43 : 0.41, y: end ? 0.82 : 0.88), rightFoot: .init(x: end ? 0.57 : 0.59, y: end ? 0.82 : 0.88))
        case .core:
            return BodyPose(head: .init(x: end ? 0.37 : 0.22, y: end ? 0.45 : 0.64), neck: .init(x: end ? 0.42 : 0.30, y: end ? 0.50 : 0.62), leftShoulder: .init(x: end ? 0.46 : 0.36, y: end ? 0.53 : 0.60), rightShoulder: .init(x: end ? 0.50 : 0.41, y: end ? 0.55 : 0.61), leftElbow: .init(x: end ? 0.37 : 0.30, y: end ? 0.62 : 0.70), rightElbow: .init(x: end ? 0.47 : 0.40, y: end ? 0.64 : 0.71), leftHand: .init(x: 0.34, y: 0.72), rightHand: .init(x: 0.45, y: 0.73), hip: .init(x: 0.61, y: 0.68), leftKnee: .init(x: 0.72, y: 0.62), rightKnee: .init(x: 0.75, y: 0.66), leftFoot: .init(x: 0.83, y: 0.78), rightFoot: .init(x: 0.86, y: 0.81))
        }
    }
}
