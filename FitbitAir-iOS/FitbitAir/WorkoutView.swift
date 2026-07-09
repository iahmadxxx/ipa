import SwiftUI

struct WorkoutView: View {
    @State private var days: [WorkoutDay] = []
    @State private var errorMessage: String?
    @State private var showManager = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("برنامجك")
                            .font(.largeTitle.bold())
                        Text("اختر القسم ثم التمرين")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
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
                .padding(.horizontal)

                ForEach(days) { day in
                    WorkoutSectionCard(day: day)
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
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(AppBackground())
        .navigationTitle("التمرين")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showManager) {
            ProgramManagerView {
                Task { await load() }
            }
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
}

private struct WorkoutSectionCard: View {
    let day: WorkoutDay

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(day.label)
                        .font(.title3.bold())
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
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, exercise in
                        NavigationLink {
                            ExerciseSessionView(day: day, index: index, exercise: exercise)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 30, height: 30)
                                    .background(Color.cyan.opacity(0.14), in: Circle())

                                Text(exercise)
                                    .foregroundStyle(.white)
                                    .lineLimit(2)

                                Spacer()

                                Image(systemName: "chevron.left")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(.vertical, 5)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise)
                            .font(.title3.bold())
                        Text(day.label)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .task { await load() }
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
                weight: parsedWeight
            )

            context = WorkoutContext(
                ok: true,
                dayLabel: day.label,
                exercise: exercise,
                todaySets: response.todaySets,
                lastSession: context?.lastSession,
                recommendation: context?.recommendation
            )

            // الجولة الجديدة مستقلة: نبقي الوزن لتسهيل التسجيل ونمسح العدات فقط.
            weight = parsedWeight.gymFormatted
            reps = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
                        ForEach(day.exercises, id: \.self) { exercise in
                            HStack {
                                Image(systemName: "dumbbell")
                                    .foregroundStyle(.cyan)
                                Text(exercise)
                                Spacer()
                                Menu {
                                    Button {
                                        action = .renameExercise(day: day, exercise: exercise)
                                    } label: {
                                        Label("تغيير الاسم", systemImage: "pencil")
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
                try await APIClient.shared.renameExercise(day: day.key, oldName: exercise, newName: trimmed)
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
