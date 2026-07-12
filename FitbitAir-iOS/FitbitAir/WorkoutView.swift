import SwiftUI

struct WorkoutView: View {
    @State private var days: [WorkoutDay] = []
    @State private var errorMessage: String?
    @State private var showManager = false
    @State private var selectedTab: WorkoutHubTab = .plan

    var body: some View {
        VStack(spacing: 10) {
            header
            WorkoutHubPicker(selection: $selectedTab)

            Group {
                switch selectedTab {
                case .plan:
                    planContent
                case .library:
                    ExerciseLibraryRootView(days: days) {
                        Task { await load() }
                    }
                case .activities:
                    ActivityHubView()
                case .history:
                    WorkoutHistoryTabView()
                case .records:
                    PersonalRecordsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .navigationTitle("التمارين")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showManager) {
            ProgramManagerView {
                Task { await load() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab == .plan ? "برنامجك" : selectedTab.rawValue)
                    .font(.largeTitle.bold())
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if selectedTab == .plan {
                Button {
                    selectedTab = .library
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.bold())
                        .frame(width: 48, height: 48)
                        .background(FitTheme.accent, in: Circle())
                        .foregroundStyle(.black.opacity(0.82))
                }
                .accessibilityLabel("إضافة تمرين من المكتبة")

                Button {
                    showManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.bold())
                        .frame(width: 48, height: 48)
                        .background(FitTheme.cardStrong, in: Circle())
                }
                .accessibilityLabel("إدارة البرنامج")
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .plan: return "تمارينك القديمة والجديدة في مكان واحد"
        case .library: return "صور، شرح، أخطاء شائعة وخطة مقترحة"
        case .activities: return "ابدأ أي نشاط وادمج بيانات Fitbit بعد المزامنة"
        case .history: return "راجع الجولات وعدّل السجل القديم"
        case .records: return "أفضل أوزانك وتطور قوتك"
        }
    }

    private var planContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if !days.isEmpty {
                    Card {
                        HStack(spacing: 13) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.title2.bold())
                                .foregroundStyle(FitTheme.accent)
                                .frame(width: 50, height: 50)
                                .background(FitTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(days.count) أقسام • \(days.reduce(0) { $0 + $1.exercises.count }) تمارين")
                                    .font(.headline)
                                Text("اضغط صورة المعلومات لفتح شرح الحركة والأخطاء الشائعة")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }

                ForEach(days) { day in
                    WorkoutSectionCard(day: day, allDays: days) {
                        Task { await load() }
                    }
                }

                if days.isEmpty && errorMessage == nil {
                    Card {
                        VStack(spacing: 10) {
                            Image(systemName: "dumbbell")
                                .font(.system(size: 34))
                                .foregroundStyle(.cyan)
                            Text("ما عندك أقسام تمارين بعد")
                                .font(.headline)
                            Text("افتح إدارة البرنامج وأضف أول قسم")
                                .foregroundStyle(.secondary)
                            Button("إدارة البرنامج") { showManager = true }
                                .buttonStyle(.borderedProminent)
                                .tint(FitTheme.accent)
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 6)
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            days = try await APIClient.shared.plan()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkoutSectionCard: View {
    let day: WorkoutDay
    let allDays: [WorkoutDay]
    let onPlanChanged: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.label)
                            .font(.title3.bold())
                        Text("اسحب الإدارة للتعديل والحذف")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    Spacer()
                    Text("\(day.exercises.count) تمارين")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.12), in: Capsule())
                }

                if day.exercises.isEmpty {
                    Text("لا توجد تمارين داخل هذا القسم")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, exerciseName in
                        let exercise = ExerciseCatalog.resolved(exerciseName)
                        let prescription = ExercisePrescriptionStore.value(dayKey: day.key, exerciseName: exerciseName, fallback: exercise)

                        HStack(spacing: 10) {
                            NavigationLink {
                                ExerciseSessionView(day: day, index: index, exercise: exerciseName)
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseArtworkView(exercise: exercise, compact: true)
                                        .frame(width: 82, height: 70)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.nameAR)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text(exercise.nameEN)
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.44))
                                            .lineLimit(1)
                                        Text(prescription.summary)
                                            .font(.caption2)
                                            .foregroundStyle(FitTheme.accent)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 2)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                ExerciseDetailView(exercise: exercise, days: allDays, onPlanChanged: onPlanChanged)
                            } label: {
                                Image(systemName: "info.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(FitTheme.accentBlue)
                                    .frame(width: 36, height: 52)
                            }
                            .accessibilityLabel("شرح تمرين \(exercise.displayName)")
                        }

                        if index < day.exercises.count - 1 {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ExerciseSessionView: View {
    let day: WorkoutDay
    let index: Int
    let exercise: String

    @State private var context: WorkoutContext?
    @State private var weight = ""
    @State private var reps = ""
    @State private var editingSet: GymSet?
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var restSeconds = 0
    @State private var restTask: Task<Void, Never>?
    @State private var rpe = 7.0
    @State private var pain = 0.0
    @State private var feedbackNote = ""
    @State private var alternatives: String?
    @State private var alternativesLoading = false
    @State private var sessionStartedAt: Date?
    @State private var sessionSeconds = 0
    @State private var sessionTask: Task<Void, Never>?

    private var definition: ExerciseDefinition { ExerciseCatalog.resolved(exercise) }
    private var prescription: ExercisePrescription {
        ExercisePrescriptionStore.value(dayKey: day.key, exerciseName: exercise, fallback: definition)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 13) {
                            ExerciseArtworkView(exercise: definition, compact: true)
                                .frame(width: 112, height: 96)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(definition.nameAR).font(.title3.bold())
                                Text(definition.nameEN).font(.caption).foregroundStyle(.white.opacity(0.48))
                                Text(day.label).font(.caption).foregroundStyle(FitTheme.accent)
                                Text(prescription.summary).font(.caption2).foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("مدة الجلسة").font(.caption2).foregroundStyle(.white.opacity(0.5))
                                Text(sessionClock).font(.headline.monospacedDigit()).foregroundStyle(FitTheme.accent)
                            }
                        }

                        HStack(spacing: 8) {
                            NavigationLink {
                                ExerciseDetailView(exercise: definition, days: [], onPlanChanged: {})
                            } label: {
                                Label("شرح الحركة", systemImage: "book.fill")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task { await loadAlternatives() }
                            } label: {
                                Label(alternativesLoading ? "جاري البحث" : "البدائل", systemImage: "arrow.triangle.branch")
                            }
                            .buttonStyle(.bordered)
                            .disabled(alternativesLoading)

                            Spacer()

                            Button("إنهاء") {
                                Task { await finishSession() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(FitTheme.accent)
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let alternatives, !alternatives.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("بدائل مناسبة", systemImage: "sparkles").font(.headline).foregroundStyle(FitTheme.accent)
                            Text(alternatives).font(.subheadline).foregroundStyle(.white.opacity(0.78)).textSelection(.enabled)
                        }
                    }
                }

                if let context {
                    if let recommendation = context.recommendation?.text,
                       !recommendation.isEmpty {
                        Card {
                            Label("الاقتراح القادم", systemImage: "brain.head.profile")
                                .font(.headline)
                            Text(recommendation)
                                .padding(.top, 4)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    HStack(spacing: 10) {
                        NumberEntryCard(title: "الوزن", suffix: "كجم", text: $weight, keyboard: .decimalPad)
                        NumberEntryCard(title: "العدات", suffix: "عدة", text: $reps, keyboard: .numberPad)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("صعوبة الجولة RPE").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(rpe))/10").font(.headline.monospacedDigit()).foregroundStyle(FitTheme.accent)
                            }
                            Slider(value: $rpe, in: 1...10, step: 1).tint(FitTheme.accent)
                            HStack {
                                Text("الألم").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(pain))/10").font(.headline.monospacedDigit()).foregroundStyle(pain >= 5 ? FitTheme.danger : FitTheme.positive)
                            }
                            Slider(value: $pain, in: 0...10, step: 1).tint(pain >= 5 ? FitTheme.danger : FitTheme.positive)
                            TextField("ملاحظة اختيارية: تعب، ألم، جودة الحركة...", text: $feedbackNote, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button {
                        Task { await saveSet() }
                    } label: {
                        HStack {
                            if saving {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(saving ? "جاري الحفظ..." : "حفظ الجولة")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)

                    RestTimerCard(seconds: restSeconds) { duration in
                        startRestTimer(duration)
                    } onStop: {
                        restTask?.cancel()
                        LocalNotificationManager.shared.cancelRest()
                        restSeconds = 0
                    }

                    TodaySetsCard(sets: context.todaySets) { set in
                        editingSet = set
                    }

                    if let lastSession = context.lastSession {
                        LastSessionCard(session: lastSession)
                    }
                } else if errorMessage == nil {
                    ProgressView()
                        .padding(.top, 30)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("تسجيل تمرين")
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
                .task {
            startSessionTimerIfNeeded()
            await load()
        }
        .onDisappear { sessionTask?.cancel() }
        .refreshable { await load() }
        .sheet(item: $editingSet) { set in
            EditSetView(set: set) { newReps, newWeight in
                Task {
                    do {
                        _ = try await APIClient.shared.editTodaySet(
                            day: day.key,
                            idx: index,
                            id: set.id,
                            set: set.setNumber,
                            reps: newReps,
                            weight: newWeight
                        )
                        await load()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            context = try await APIClient.shared.workoutContext(day: day.key, idx: index)
            if weight.isEmpty, let lastWeight = context?.todaySets.last?.weight ?? context?.lastSession?.sets.last?.weight {
                weight = lastWeight.gymFormatted
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSet() async {
        guard !saving else { return }
        guard let parsedReps = Int(reps), let parsedWeight = Double(weight) else {
            errorMessage = "تأكد من الوزن والعدات"
            return
        }

        saving = true
        defer { saving = false }

        do {
            let response = try await APIClient.shared.saveSet(
                day: day.key,
                idx: index,
                reps: parsedReps,
                weight: parsedWeight,
                rpe: Int(rpe),
                pain: pain >= 5,
                note: feedbackNote
            )

            context = WorkoutContext(
                ok: true,
                dayLabel: day.label,
                exercise: exercise,
                todaySets: response.todaySets,
                lastSession: context?.lastSession,
                recommendation: context?.recommendation
            )

            feedbackNote = ""

            // الجولة الجديدة مستقلة: نبقي الوزن لتسهيل التسجيل ونمسح العدات فقط.
            weight = parsedWeight.gymFormatted
            reps = ""
            errorMessage = nil
            startRestTimer(prescription.restSeconds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var sessionClock: String {
        String(format: "%02d:%02d", sessionSeconds / 60, sessionSeconds % 60)
    }

    private func startSessionTimerIfNeeded() {
        guard sessionStartedAt == nil else { return }
        sessionStartedAt = Date()
        sessionSeconds = 0
        sessionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { await MainActor.run { sessionSeconds += 1 } }
            }
        }
    }

    @MainActor
    private func finishSession() async {
        guard sessionSeconds > 0 else { return }
        do {
            let formatter = ISO8601DateFormatter()
            try await APIClient.shared.saveWorkoutSession(
                dayKey: day.key,
                durationSeconds: sessionSeconds,
                startedAt: sessionStartedAt.map { formatter.string(from: $0) }
            )
            sessionTask?.cancel()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadAlternatives() async {
        guard !alternativesLoading else { return }
        alternativesLoading = true
        defer { alternativesLoading = false }
        do {
            alternatives = try await APIClient.shared.workoutAlternatives(exercise: exercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRestTimer(_ duration: Int) {
        restTask?.cancel()
        LocalNotificationManager.shared.cancelRest()
        restSeconds = duration
        if UserDefaults.standard.object(forKey: "notifications.rest.enabled") == nil || UserDefaults.standard.bool(forKey: "notifications.rest.enabled") {
            LocalNotificationManager.shared.scheduleRest(after: duration, exercise: exercise)
        }
        restTask = Task {
            while !Task.isCancelled && restSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !Task.isCancelled { await MainActor.run { restSeconds = max(0, restSeconds - 1) } }
            }
            if !Task.isCancelled && restSeconds == 0 {
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
}

private struct RestTimerCard: View {
    let seconds: Int
    let onStart: (Int) -> Void
    let onStop: () -> Void
    var body: some View {
        Card {
            VStack(spacing: 10) {
                HStack {
                    Label("راحة بين الجولات", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(seconds > 0 ? .cyan : .white.opacity(0.55))
                }
                HStack(spacing: 8) {
                    ForEach([60, 90, 120], id: \.self) { value in
                        Button("\(value)ث") { onStart(value) }
                            .buttonStyle(.bordered)
                    }
                    if seconds > 0 {
                        Button("إيقاف", role: .destructive) { onStop() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

private struct NumberEntryCard: View {
    let title: String
    let suffix: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("0", text: $text)
                    .keyboardType(keyboard)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodaySetsCard: View {
    let sets: [GymSet]
    let onEdit: (GymSet) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("جولات اليوم")
                    .font(.headline)

                if sets.isEmpty {
                    Text("لا توجد جولات بعد")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sets) { set in
                        HStack {
                            Text("جولة \(set.setNumber)")
                            Spacer()
                            Text("\(set.weight.gymFormatted) كجم × \(set.reps)")
                                .fontWeight(.semibold)

                            Button {
                                onEdit(set)
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }
}

private struct LastSessionCard: View {
    let session: LastSession

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("آخر جلسة — \(session.date)")
                    .font(.headline)

                ForEach(session.sets) { set in
                    Text("جولة \(set.setNumber): \(set.weight.gymFormatted) كجم × \(set.reps)")
                }
            }
        }
    }
}

// MARK: - Program Manager

struct ProgramManagerView: View {
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var days: [WorkoutDay] = []
    @State private var action: ManagerAction?
    @State private var confirmDelete: DeleteTarget?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        action = .addSection
                    } label: {
                        Label("إضافة قسم جديد", systemImage: "plus.rectangle.on.folder")
                    }
                }

                ForEach(days) { day in
                    Section {
                        ForEach(Array(day.exercises.enumerated()), id: \.element) { _, exercise in
                            let definition = ExerciseCatalog.resolved(exercise)
                            HStack(spacing: 10) {
                                ExerciseArtworkView(exercise: definition, compact: true)
                                    .frame(width: 54, height: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.nameAR)
                                        .font(.subheadline.weight(.semibold))
                                    Text(definition.nameEN)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button {
                                        action = .renameExercise(day: day, exercise: exercise)
                                    } label: {
                                        Label("تغيير الاسم", systemImage: "pencil")
                                    }

                                    if days.count > 1 {
                                        Menu("نقل إلى قسم", systemImage: "arrowshape.turn.up.right") {
                                            ForEach(days.filter { $0.key != day.key }) { target in
                                                Button(target.label) {
                                                    Task { await move(exercise: exercise, from: day, to: target) }
                                                }
                                            }
                                        }
                                    }

                                    Button(role: .destructive) {
                                        confirmDelete = .exercise(day: day, name: exercise)
                                    } label: {
                                        Label("حذف التمرين", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            Task { await reorder(day: day, offsets: offsets, destination: destination) }
                        }

                        Button {
                            action = .addExercise(day: day)
                        } label: {
                            Label("إضافة تمرين", systemImage: "plus.circle")
                        }
                    } header: {
                        HStack {
                            Text(day.label)
                            Spacer()
                            Menu {
                                Button {
                                    action = .renameSection(day: day)
                                } label: {
                                    Label("تغيير اسم القسم", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    confirmDelete = .section(day: day)
                                } label: {
                                    Label("حذف القسم", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("إدارة البرنامج")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") {
                        onChanged()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    EditButton()
                }
            }
            .task { await load() }
            .sheet(item: $action) { action in
                ManagerTextEditor(action: action) {
                    Task { await load() }
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("حذف", role: .destructive) {
                    guard let target = confirmDelete else { return }
                    Task { await delete(target) }
                }
                Button("إلغاء", role: .cancel) {
                    confirmDelete = nil
                }
            } message: {
                Text(deleteMessage)
            }
        }
    }

    private var deleteTitle: String {
        switch confirmDelete {
        case .exercise: return "حذف التمرين؟"
        case .section: return "حذف القسم؟"
        case nil: return ""
        }
    }

    private var deleteMessage: String {
        switch confirmDelete {
        case .exercise:
            return "سيختفي التمرين من برنامجك الحالي، لكن سجلك القديم يبقى محفوظًا للذكاء الاصطناعي."
        case .section:
            return "سيختفي القسم وتمارينه من برنامجك الحالي. السجل القديم لن يُحذف."
        case nil:
            return ""
        }
    }

    private func load() async {
        do {
            days = try await APIClient.shared.plan()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ target: DeleteTarget) async {
        do {
            switch target {
            case let .exercise(day, name):
                try await APIClient.shared.deleteExercise(day: day.key, name: name)
            case let .section(day):
                try await APIClient.shared.deleteSection(day: day.key)
            }
            confirmDelete = nil
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    @MainActor
    private func reorder(day: WorkoutDay, offsets: IndexSet, destination: Int) async {
        var names = day.exercises
        names.move(fromOffsets: offsets, toOffset: destination)
        do {
            try await APIClient.shared.reorderExercises(day: day.key, exercises: names)
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }

    @MainActor
    private func move(exercise: String, from source: WorkoutDay, to target: WorkoutDay) async {
        do {
            let savedPrescription = ExercisePrescriptionStore.value(
                dayKey: source.key,
                exerciseName: exercise,
                fallback: ExerciseCatalog.resolved(exercise)
            )
            try await APIClient.shared.moveExercise(sourceDay: source.key, targetDay: target.key, name: exercise)
            ExercisePrescriptionStore.save(savedPrescription, dayKey: target.key, exerciseName: exercise)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DeleteTarget: Identifiable {
    case exercise(day: WorkoutDay, name: String)
    case section(day: WorkoutDay)

    var id: String {
        switch self {
        case let .exercise(day, name): return "exercise-\(day.key)-\(name)"
        case let .section(day): return "section-\(day.key)"
        }
    }
}

private enum ManagerAction: Identifiable {
    case addSection
    case renameSection(day: WorkoutDay)
    case addExercise(day: WorkoutDay)
    case renameExercise(day: WorkoutDay, exercise: String)

    var id: String {
        switch self {
        case .addSection: return "add-section"
        case let .renameSection(day): return "rename-section-\(day.key)"
        case let .addExercise(day): return "add-exercise-\(day.key)"
        case let .renameExercise(day, exercise): return "rename-exercise-\(day.key)-\(exercise)"
        }
    }

    var title: String {
        switch self {
        case .addSection: return "إضافة قسم"
        case .renameSection: return "تغيير اسم القسم"
        case .addExercise: return "إضافة تمرين"
        case .renameExercise: return "تغيير اسم التمرين"
        }
    }

    var placeholder: String {
        switch self {
        case .addSection, .renameSection: return "اسم القسم"
        case .addExercise, .renameExercise: return "اسم التمرين"
        }
    }

    var initialValue: String {
        switch self {
        case .addSection, .addExercise: return ""
        case let .renameSection(day): return day.label
        case let .renameExercise(_, exercise): return exercise
        }
    }
}

private struct ManagerTextEditor: View {
    let action: ManagerAction
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(action: ManagerAction, onDone: @escaping () -> Void) {
        self.action = action
        self.onDone = onDone
        _value = State(initialValue: action.initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(action.placeholder, text: $value)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(action.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        Task { await save() }
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || saving)
                }
            }
        }
    }

    private func save() async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        saving = true
        defer { saving = false }

        do {
            switch action {
            case .addSection:
                try await APIClient.shared.addSection(label: trimmed)
            case let .renameSection(day):
                try await APIClient.shared.renameSection(day: day.key, label: trimmed)
            case let .addExercise(day):
                try await APIClient.shared.addExercise(day: day.key, name: trimmed)
            case let .renameExercise(day, exercise):
                let savedPrescription = ExercisePrescriptionStore.value(
                    dayKey: day.key,
                    exerciseName: exercise,
                    fallback: ExerciseCatalog.resolved(exercise)
                )
                try await APIClient.shared.renameExercise(day: day.key, oldName: exercise, newName: trimmed)
                ExercisePrescriptionStore.save(savedPrescription, dayKey: day.key, exerciseName: trimmed)
            }
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Double {
    var gymFormatted: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct EditSetView: View {
    let set: GymSet
    let onSave: (Int, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reps = ""
    @State private var weight = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("الوزن", text: $weight)
                    .keyboardType(.decimalPad)
                TextField("العدات", text: $reps)
                    .keyboardType(.numberPad)
            }
            .navigationTitle("تعديل الجولة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        guard let parsedReps = Int(reps),
                              let parsedWeight = Double(weight) else { return }
                        onSave(parsedReps, parsedWeight)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            reps = String(set.reps)
            weight = set.weight.gymFormatted
        }
    }
}
