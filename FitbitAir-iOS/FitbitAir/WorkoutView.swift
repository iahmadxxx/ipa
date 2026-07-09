import SwiftUI

struct WorkoutView: View {
    @State private var days: [WorkoutDay] = []
    @State private var errorMessage: String?
    @State private var showAddExercise = false

    var body: some View {
        List {
            ForEach(days) { day in
                Section(day.label) {
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, exercise in
                        NavigationLink {
                            ExerciseSessionView(day: day, index: index, exercise: exercise)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 28, height: 28)
                                    .background(Color.cyan.opacity(0.15), in: Circle())

                                Text(exercise)
                                    .lineLimit(2)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await APIClient.shared.deleteExercise(day: day.key, name: exercise)
                                        await load()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showAddExercise = true
                    } label: {
                        Label("إضافة تمرين", systemImage: "plus.circle.fill")
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("التمارين")
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .foregroundStyle(.white)
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseView(days: days) {
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

struct AddExerciseView: View {
    let days: [WorkoutDay]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay = ""
    @State private var name = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("اليوم", selection: $selectedDay) {
                    ForEach(days) { day in
                        Text(day.label).tag(day.key)
                    }
                }

                TextField("اسم التمرين", text: $name)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("إضافة تمرين")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || saving)
                }
            }
        }
        .onAppear {
            if selectedDay.isEmpty {
                selectedDay = days.first?.key ?? "d1"
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        saving = true
        defer { saving = false }

        do {
            try await APIClient.shared.addExercise(day: selectedDay, name: trimmedName)
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    Text(exercise)
                        .font(.title3.bold())
                    Text(day.label)
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let context {
                    if let recommendation = context.recommendation?.text,
                       !recommendation.isEmpty {
                        Card {
                            Label("الاقتراح القادم", systemImage: "brain.head.profile")
                                .font(.headline)
                            Text(recommendation)
                                .padding(.top, 4)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("الوزن", text: $weight)
                            .keyboardType(.decimalPad)
                            .padding(14)
                            .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        TextField("العدات", text: $reps)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        Task { await saveSet() }
                    } label: {
                        Label("حفظ الجولة", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(PrimaryButtonStyle())

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
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSet() async {
        guard let parsedReps = Int(reps), let parsedWeight = Double(weight) else {
            errorMessage = "تأكد من الوزن والعدات"
            return
        }

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

            reps = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TodaySetsCard: View {
    let sets: [GymSet]
    let onEdit: (GymSet) -> Void

    var body: some View {
        Card {
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
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}

private struct LastSessionCard: View {
    let session: LastSession

    var body: some View {
        Card {
            Text("آخر جلسة — \(session.date)")
                .font(.headline)

            ForEach(session.sets) { set in
                Text("جولة \(set.setNumber): \(set.weight.gymFormatted) كجم × \(set.reps)")
            }
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
