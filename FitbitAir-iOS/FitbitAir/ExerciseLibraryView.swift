import SwiftUI
import UIKit

// MARK: - Workout hub

enum WorkoutHubTab: String, CaseIterable, Identifiable {
    case plan = "جدولي"
    case library = "المكتبة"
    case activities = "النشاطات"
    case history = "السجل"
    case records = "الأرقام"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .plan: return "list.bullet.rectangle.portrait.fill"
        case .library: return "square.grid.2x2.fill"
        case .activities: return "figure.run"
        case .history: return "clock.arrow.circlepath"
        case .records: return "trophy.fill"
        }
    }
}

struct WorkoutHubPicker: View {
    @Binding var selection: WorkoutHubTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorkoutHubTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.caption2.bold())
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? Color.black.opacity(0.85) : Color.white.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selection == tab ? FitTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
        }
        .padding(5)
        .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FitTheme.stroke))
        .padding(.horizontal)
    }
}

// MARK: - Exercise library

struct ExerciseLibraryRootView: View {
    let days: [WorkoutDay]
    let onPlanChanged: () -> Void

    @State private var search = ""
    @State private var selectedMuscle: ExerciseMuscleGroup = .all
    @State private var selectedEquipment: ExerciseEquipment?
    @State private var addTarget: ExerciseDefinition?
    @State private var showCustomExercise = false
    @State private var customRevision = 0
    @State private var selectedExercise: ExerciseDefinition?
    @State private var pendingDeleteCustom: ExerciseDefinition?

    private var allExercises: [ExerciseDefinition] {
        _ = customRevision
        return CustomExerciseStore.all() + ExerciseCatalog.all
    }

    private var filteredExercises: [ExerciseDefinition] {
        allExercises.filter { exercise in
            let matchesMuscle = selectedMuscle == .all || exercise.primaryMuscle == selectedMuscle || exercise.secondaryMuscles.contains(selectedMuscle)
            let matchesEquipment = selectedEquipment == nil || exercise.equipment == selectedEquipment
            let normalizedSearch = ExerciseCatalog.normalize(search)
            let matchesSearch = normalizedSearch.isEmpty || [exercise.nameAR, exercise.nameEN, exercise.primaryMuscle.rawValue, exercise.equipment.rawValue]
                .contains { ExerciseCatalog.normalize($0).contains(normalizedSearch) }
            return matchesMuscle && matchesEquipment && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                libraryHeader
                muscleFilters
                equipmentFilters

                HStack {
                    Text("\(filteredExercises.count) تمرين")
                        .font(.headline)
                    Spacer()
                    Text("اضغط على التمرين للشرح")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal)

                ForEach(filteredExercises) { exercise in
                    ExerciseLibraryCard(
                        exercise: exercise,
                        onOpen: { selectedExercise = exercise },
                        onAdd: { addTarget = exercise },
                        onDeleteCustom: exercise.isCustom ? {
                            pendingDeleteCustom = exercise
                        } : nil
                    )
                    .padding(.horizontal)
                }

                if filteredExercises.isEmpty {
                    Card {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 34))
                                .foregroundStyle(FitTheme.accent)
                            Text("ما لقينا تمرين مطابق")
                                .font(.headline)
                            Text("غيّر الفلاتر أو أضف تمرينًا مخصصًا.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 10)
        }
        .searchable(text: $search, prompt: "ابحث بالعربي أو الإنجليزي")
        .sheet(item: $addTarget) { exercise in
            AddExerciseToPlanView(exercise: exercise, days: days) {
                onPlanChanged()
            }
        }
        .sheet(isPresented: $showCustomExercise) {
            CustomExerciseFormView {
                customRevision += 1
            }
        }
        .navigationDestination(item: $selectedExercise) { exercise in
            ExerciseDetailView(exercise: exercise, days: days, onPlanChanged: onPlanChanged)
        }
        .confirmationDialog(
            "حذف التمرين المخصص؟",
            isPresented: Binding(
                get: { pendingDeleteCustom != nil },
                set: { if !$0 { pendingDeleteCustom = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("حذف من المكتبة", role: .destructive) {
                guard let exercise = pendingDeleteCustom else { return }
                CustomExerciseStore.delete(exercise)
                pendingDeleteCustom = nil
                customRevision += 1
            }
            Button("إلغاء", role: .cancel) { pendingDeleteCustom = nil }
        } message: {
            Text("سيُحذف تعريف التمرين المخصص من مكتبتك. سجلات الجولات القديمة لن تُحذف.")
        }
    }

    private var libraryHeader: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FitTheme.gradient)
                        .frame(width: 58, height: 58)
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title2.bold())
                        .foregroundStyle(.black.opacity(0.82))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("مكتبة التمارين")
                        .font(.title3.bold())
                    Text("صور توضيحية، شرح الحركة، الأخطاء والبدائل")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button {
                    showCustomExercise = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(FitTheme.cardStrong, in: Circle())
                }
                .accessibilityLabel("إضافة تمرين مخصص")
            }
        }
        .padding(.horizontal)
    }

    private var muscleFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExerciseMuscleGroup.allCases) { muscle in
                    Button {
                        selectedMuscle = muscle
                    } label: {
                        Label(muscle.rawValue, systemImage: muscle.systemImage)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedMuscle == muscle ? Color.black.opacity(0.85) : Color.white.opacity(0.72))
                            .background(selectedMuscle == muscle ? muscle.tint : FitTheme.cardStrong, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var equipmentFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedEquipment = nil
                } label: {
                    Text("كل الأجهزة")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedEquipment == nil ? Color.black.opacity(0.85) : Color.white.opacity(0.68))
                        .background(selectedEquipment == nil ? FitTheme.accent : FitTheme.card, in: Capsule())
                }
                .buttonStyle(.plain)

                ForEach(ExerciseEquipment.allCases) { equipment in
                    Button {
                        selectedEquipment = equipment
                    } label: {
                        Label(equipment.rawValue, systemImage: equipment.systemImage)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedEquipment == equipment ? Color.black.opacity(0.85) : Color.white.opacity(0.68))
                            .background(selectedEquipment == equipment ? FitTheme.accent : FitTheme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ExerciseLibraryCard: View {
    let exercise: ExerciseDefinition
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onDeleteCustom: (() -> Void)?

    var body: some View {
        Card {
            HStack(spacing: 13) {
                ExerciseArtworkView(exercise: exercise, compact: true)
                    .frame(width: 104, height: 92)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpen)

                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.nameAR)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(exercise.nameEN)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        InfoChip(text: exercise.primaryMuscle.rawValue, tint: exercise.primaryMuscle.tint)
                        InfoChip(text: exercise.equipment.rawValue, tint: FitTheme.accentBlue)
                    }
                    Text("\(exercise.defaultSets) × \(exercise.repRangeText) • راحة \(exercise.restSeconds)ث")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                Spacer(minLength: 4)

                VStack(spacing: 10) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.black.opacity(0.82))
                            .frame(width: 42, height: 42)
                            .background(FitTheme.accent, in: Circle())
                    }
                    .accessibilityLabel("إضافة \(exercise.displayName)")

                    if let onDeleteCustom {
                        Button(role: .destructive, action: onDeleteCustom) {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(FitTheme.danger)
                        }
                        .accessibilityLabel("حذف التمرين المخصص")
                    } else {
                        Button(action: onOpen) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
        }
    }
}

struct InfoChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Exercise details

struct ExerciseDetailView: View {
    let exercise: ExerciseDefinition
    let days: [WorkoutDay]
    let onPlanChanged: () -> Void

    @State private var artworkStage = 0
    @State private var showAdd = false
    @State private var historyStats: ExerciseHistoryStats?
    @State private var historyLoading = false
    @State private var motionPlaying = true
    @State private var aboutExpanded = true
    @State private var stepsExpanded = true
    @State private var mistakesExpanded = false
    @State private var tipsExpanded = false
    @State private var statsExpanded = false
    @State private var musclesExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ExerciseArtworkView(
                    exercise: exercise,
                    stage: artworkStage,
                    animated: motionPlaying
                )
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        motionPlaying = true
                    } label: {
                        Label("تشغيل الحركة", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(motionPlaying ? FitTheme.accent : FitTheme.cardStrong)
                    .foregroundStyle(motionPlaying ? .black : .white)

                    Button("البداية") {
                        motionPlaying = false
                        artworkStage = 0
                    }
                    .buttonStyle(.bordered)

                    Button("النهاية") {
                        motionPlaying = false
                        artworkStage = 1
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.bold())

                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.nameAR)
                        .font(.largeTitle.bold())
                    Text(exercise.nameEN)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.52))
                    HStack(spacing: 7) {
                        InfoChip(text: exercise.primaryMuscle.rawValue, tint: exercise.primaryMuscle.tint)
                        InfoChip(text: exercise.equipment.rawValue, tint: FitTheme.accentBlue)
                        InfoChip(text: exercise.difficulty.rawValue, tint: FitTheme.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CollapsibleDetailCard(title: "العضلات المستهدفة", icon: "figure.strengthtraining.traditional", tint: FitTheme.accent, isExpanded: $musclesExpanded) {
                    MuscleAnatomyMapView(primary: exercise.primaryMuscle, secondary: exercise.secondaryMuscles)
                }

                if historyLoading {
                    Card {
                        HStack {
                            ProgressView().tint(FitTheme.accent)
                            Text("جاري قراءة تاريخك في هذا التمرين...")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                } else if let historyStats {
                    CollapsibleDetailCard(title: "أداؤك السابق", icon: "chart.line.uptrend.xyaxis", tint: FitTheme.accent, isExpanded: $statsExpanded) {
                        ExerciseStatsCard(stats: historyStats, embedded: true)
                    }
                }

                CollapsibleDetailCard(title: "عن التمرين", icon: "info.circle.fill", tint: FitTheme.accent, isExpanded: $aboutExpanded) {
                    Text(exercise.overview)
                        .foregroundStyle(.white.opacity(0.78))
                }

                CollapsibleDetailCard(title: "طريقة التنفيذ", icon: "list.number", tint: FitTheme.positive, isExpanded: $stepsExpanded) {
                    NumberedStepsView(items: exercise.steps)
                }

                CollapsibleDetailCard(title: "الأخطاء الشائعة", icon: "exclamationmark.triangle.fill", tint: FitTheme.danger, isExpanded: $mistakesExpanded) {
                    BulletListView(items: exercise.mistakes, tint: FitTheme.danger)
                }

                CollapsibleDetailCard(title: "نصائح مهمة", icon: "lightbulb.fill", tint: FitTheme.warning, isExpanded: $tipsExpanded) {
                    BulletListView(items: exercise.tips, tint: FitTheme.warning)
                }

                if !days.isEmpty {
                    Button {
                        showAdd = true
                    } label: {
                        Label("إضافة إلى جدولي", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("شرح التمرين")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
        .sheet(isPresented: $showAdd) {
            AddExerciseToPlanView(exercise: exercise, days: days) {
                onPlanChanged()
            }
        }
    }

    private func loadStats() async {
        historyLoading = true
        defer { historyLoading = false }
        do {
            let history = try await APIClient.shared.history()
            historyStats = ExerciseHistoryStats.make(for: exercise, history: history)
        } catch {
            historyStats = nil
        }
    }
}

private struct DetailTextCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    init(title: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                content
            }
        }
    }
}

private struct CollapsibleDetailCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    init(title: String, icon: String, tint: Color, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Label(title, systemImage: icon)
                            .font(.headline)
                            .foregroundStyle(tint)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .foregroundStyle(tint)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}

private struct NumberedStepsView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(FitTheme.positive, in: Circle())
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
    }
}

private struct BulletListView: View {
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
    }
}

private struct ExerciseStatsCard: View {
    let stats: ExerciseHistoryStats
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                statsContent
            } else {
                Card { statsContent }
            }
        }
    }

    private var statsContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("أداؤك", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundStyle(FitTheme.accent)
                    Spacer()
                    Text(stats.lastDate)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                HStack(spacing: 9) {
                    StatMiniCard(title: "أفضل وزن", value: "\(stats.maxWeight.gymFormatted) كجم", tint: FitTheme.accent)
                    StatMiniCard(title: "أفضل عدات", value: "\(stats.maxReps)", tint: FitTheme.positive)
                    StatMiniCard(title: "1RM تقديري", value: "\(stats.estimatedOneRM.gymFormatted)", tint: FitTheme.warning)
                }
                Text(stats.suggestion)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))
            }
    }
}

private struct StatMiniCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ExerciseHistoryStats {
    let maxWeight: Double
    let maxReps: Int
    let estimatedOneRM: Double
    let lastDate: String
    let suggestion: String

    static func make(for exercise: ExerciseDefinition, history: [HistoryDay]) -> ExerciseHistoryStats? {
        let names = Set(([exercise.nameAR, exercise.nameEN] + exercise.aliases).map(ExerciseCatalog.normalize))
        var matched: [(date: String, set: GymSet)] = []
        for day in history {
            for item in day.exercises where names.contains(ExerciseCatalog.normalize(item.exercise)) {
                for set in item.sets { matched.append((day.date, set)) }
            }
        }
        guard !matched.isEmpty else { return nil }
        let maxWeight = matched.map { $0.set.weight }.max() ?? 0
        let maxReps = matched.map { $0.set.reps }.max() ?? 0
        let bestOneRM = matched.map { $0.set.weight * (1 + Double($0.set.reps) / 30) }.max() ?? 0
        let last = matched.first ?? matched[0]
        let topAtWeight = matched.filter { $0.set.weight == maxWeight }.map { $0.set.reps }.max() ?? 0
        let suggestion: String
        if topAtWeight >= exercise.maxReps {
            suggestion = "وصلت أعلى نطاق العدات على أفضل وزن؛ جرب زيادة صغيرة 1–2.5 كجم مع الحفاظ على التقنية."
        } else {
            suggestion = "ثبت أفضل وزن وحاول رفع مجموع العدات تدريجيًا قبل زيادة الحمل."
        }
        return ExerciseHistoryStats(maxWeight: maxWeight, maxReps: maxReps, estimatedOneRM: bestOneRM, lastDate: last.date, suggestion: suggestion)
    }
}

// MARK: - Add to plan

struct AddExerciseToPlanView: View {
    let exercise: ExerciseDefinition
    let days: [WorkoutDay]
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDayKey: String
    @State private var sets: Int
    @State private var minReps: Int
    @State private var maxReps: Int
    @State private var restSeconds: Int
    @State private var note = ""
    @State private var saving = false
    @State private var errorMessage: String?

    init(exercise: ExerciseDefinition, days: [WorkoutDay], onAdded: @escaping () -> Void) {
        self.exercise = exercise
        self.days = days
        self.onAdded = onAdded
        _selectedDayKey = State(initialValue: days.first?.key ?? "")
        _sets = State(initialValue: exercise.defaultSets)
        _minReps = State(initialValue: exercise.minReps)
        _maxReps = State(initialValue: exercise.maxReps)
        _restSeconds = State(initialValue: exercise.restSeconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ExerciseArtworkView(exercise: exercise, compact: true)
                            .frame(width: 92, height: 82)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(exercise.nameAR).font(.headline)
                            Text(exercise.nameEN).font(.caption).foregroundStyle(.secondary)
                            Text(exercise.primaryMuscle.rawValue + " • " + exercise.equipment.rawValue)
                                .font(.caption2)
                                .foregroundStyle(FitTheme.accent)
                        }
                    }
                }

                Section("مكان التمرين") {
                    if days.isEmpty {
                        Text("أضف قسمًا للتمارين أولًا من إدارة البرنامج.")
                            .foregroundStyle(.orange)
                    } else {
                        Picker("القسم", selection: $selectedDayKey) {
                            ForEach(days) { day in
                                Text(day.label).tag(day.key)
                            }
                        }
                    }
                }

                Section("الخطة الافتراضية") {
                    Stepper("الجولات: \(sets)", value: $sets, in: 1...10)
                    Stepper("أقل عدات: \(minReps)", value: $minReps, in: 1...50)
                    Stepper("أعلى عدات: \(maxReps)", value: $maxReps, in: minReps...60)
                    Stepper("الراحة: \(restSeconds) ثانية", value: $restSeconds, in: 30...300, step: 15)
                    TextField("ملاحظة اختيارية", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("إضافة إلى الجدول")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "جاري الحفظ" : "إضافة") {
                        Task { await save() }
                    }
                    .disabled(days.isEmpty || selectedDayKey.isEmpty || saving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await APIClient.shared.addExercise(day: selectedDayKey, name: exercise.nameEN)
            ExercisePrescriptionStore.save(
                ExercisePrescription(sets: sets, minReps: minReps, maxReps: max(maxReps, minReps), restSeconds: restSeconds, note: note),
                dayKey: selectedDayKey,
                exerciseName: exercise.nameEN
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Custom exercise

struct CustomExerciseFormView: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameAR = ""
    @State private var nameEN = ""
    @State private var muscle: ExerciseMuscleGroup = .chest
    @State private var equipment: ExerciseEquipment = .dumbbells
    @State private var overview = ""
    @State private var stepsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("اسم التمرين") {
                    TextField("الاسم بالعربي", text: $nameAR)
                    TextField("الاسم بالإنجليزي (اختياري)", text: $nameEN)
                }
                Section("التصنيف") {
                    Picker("العضلة", selection: $muscle) {
                        ForEach(ExerciseMuscleGroup.allCases.filter { $0 != .all }) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("الأداة", selection: $equipment) {
                        ForEach(ExerciseEquipment.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                Section("الشرح") {
                    TextField("وصف مختصر", text: $overview, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("خطوات التنفيذ، كل خطوة في سطر", text: $stepsText, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section {
                    Text("سيُنشئ التطبيق رسمًا توضيحيًا موحدًا حسب العضلة ونوع الحركة، ويظهر التمرين مع مكتبتك وتمارينك القديمة.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("تمرين مخصص")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .disabled(nameAR.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("تم") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
        }
    }

    private func save() {
        let cleanAR = nameAR.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEN = nameEN.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = stepsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let exercise = ExerciseDefinition.custom(
            nameAR: cleanAR,
            nameEN: cleanEN,
            muscle: muscle,
            equipment: equipment,
            overview: overview.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps
        )
        CustomExerciseStore.add(exercise)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved()
        dismiss()
    }
}

// MARK: - Embedded history tab

struct WorkoutHistoryTabView: View {
    @State private var records: [HistoryDay] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("سجل التمارين")
                                .font(.title3.bold())
                            Text("آخر الجلسات والجولات المحفوظة")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        NavigationLink {
                            HistoryView()
                        } label: {
                            Label("السجل الكامل", systemImage: "arrow.up.left.square")
                                .font(.caption.bold())
                        }
                    }
                }
                .padding(.horizontal)

                if loading {
                    LoadingStateView(text: "جاري تحميل السجل")
                } else {
                    ForEach(records.prefix(14)) { day in
                        Card {
                            VStack(alignment: .leading, spacing: 11) {
                                HStack {
                                    Text(day.date).font(.headline)
                                    Spacer()
                                    Text("\(day.exercises.reduce(0) { $0 + $1.sets.count }) جولة")
                                        .font(.caption.bold())
                                        .foregroundStyle(FitTheme.accent)
                                }
                                ForEach(day.exercises) { item in
                                    let definition = ExerciseCatalog.resolved(item.exercise)
                                    HStack(spacing: 10) {
                                        ExerciseArtworkView(exercise: definition, compact: true)
                                            .frame(width: 64, height: 54)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(definition.nameAR).font(.subheadline.bold())
                                            Text(item.sets.map { "\($0.weight.gymFormatted)×\($0.reps)" }.joined(separator: " • "))
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.5))
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 10)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            records = try await APIClient.shared.history()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Personal records tab

struct PersonalRecordsView: View {
    @State private var records: [ExerciseRecord] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.title.bold())
                            .foregroundStyle(FitTheme.warning)
                            .frame(width: 52, height: 52)
                            .background(FitTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("أرقامك الشخصية")
                                .font(.title3.bold())
                            Text("أفضل وزن، عدات و1RM تقديري لكل تمرين")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal)

                if loading {
                    LoadingStateView(text: "جاري حساب الأرقام الشخصية")
                } else {
                    ForEach(records) { record in
                        let definition = ExerciseCatalog.resolved(record.exercise)
                        Card {
                            HStack(spacing: 12) {
                                ExerciseArtworkView(exercise: definition, compact: true)
                                    .frame(width: 84, height: 72)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(definition.nameAR)
                                        .font(.headline)
                                    Text(definition.nameEN)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.45))
                                    HStack(spacing: 12) {
                                        RecordMetric(title: "الوزن", value: "\(record.maxWeight.gymFormatted) كجم")
                                        RecordMetric(title: "العدات", value: "\(record.maxReps)")
                                        RecordMetric(title: "1RM", value: record.estimatedOneRM.gymFormatted)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if records.isEmpty && !loading && errorMessage == nil {
                    Card {
                        Text("بعد تسجيل الجولات ستظهر أرقامك الشخصية هنا تلقائيًا.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage).padding(.horizontal)
                }
            }
            .padding(.vertical, 10)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let history = try await APIClient.shared.history()
            records = ExerciseRecord.make(from: history)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExerciseRecord: Identifiable {
    let exercise: String
    let maxWeight: Double
    let maxReps: Int
    let estimatedOneRM: Double
    var id: String { ExerciseCatalog.normalize(exercise) }

    static func make(from history: [HistoryDay]) -> [ExerciseRecord] {
        var setsByExercise: [String: (name: String, sets: [GymSet])] = [:]
        for day in history {
            for item in day.exercises {
                let key = ExerciseCatalog.normalize(item.exercise)
                var bucket = setsByExercise[key] ?? (name: item.exercise, sets: [])
                bucket.sets.append(contentsOf: item.sets)
                setsByExercise[key] = bucket
            }
        }
        return setsByExercise.values.compactMap { value in
            guard !value.sets.isEmpty else { return nil }
            return ExerciseRecord(
                exercise: value.name,
                maxWeight: value.sets.map(\.weight).max() ?? 0,
                maxReps: value.sets.map(\.reps).max() ?? 0,
                estimatedOneRM: value.sets.map { $0.weight * (1 + Double($0.reps) / 30) }.max() ?? 0
            )
        }
        .sorted { $0.estimatedOneRM > $1.estimatedOneRM }
    }
}

private struct RecordMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(FitTheme.accent)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
        }
    }
}
