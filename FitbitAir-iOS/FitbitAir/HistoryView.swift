import SwiftUI

struct HistoryView: View {
    @State private var records: [HistoryDay] = []
    @State private var search = ""
    @State private var editingSet: GymSet?
    @State private var errorMessage: String?

    private var filteredRecords: [HistoryDay] {
        guard !search.isEmpty else { return records }

        return records.compactMap { day in
            let matchingExercises = day.exercises.filter { exercise in
                exercise.exercise.localizedCaseInsensitiveContains(search)
                    || day.date.localizedCaseInsensitiveContains(search)
            }

            guard !matchingExercises.isEmpty else { return nil }
            return HistoryDay(date: day.date, exercises: matchingExercises)
        }
    }

    var body: some View {
        List {
            ForEach(filteredRecords) { day in
                Section(day.date) {
                    ForEach(day.exercises) { exercise in
                        ExerciseHistoryDisclosure(
                            exercise: exercise,
                            onEdit: { set in
                                editingSet = set
                            },
                            onDelete: { set in
                                await delete(set)
                            }
                        )
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("سجل التمارين")
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .foregroundStyle(.white)
        .searchable(text: $search, prompt: "ابحث بالتمرين أو التاريخ")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingSet) { set in
            EditSetView(set: set) { reps, weight in
                Task {
                    guard let id = set.id else { return }
                    do {
                        try await APIClient.shared.editHistory(id: id, reps: reps, weight: weight)
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
            records = try await APIClient.shared.history()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ set: GymSet) async {
        guard let id = set.id else { return }

        do {
            try await APIClient.shared.deleteHistory(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExerciseHistoryDisclosure: View {
    let exercise: HistoryExercise
    let onEdit: (GymSet) -> Void
    let onDelete: (GymSet) async -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(exercise.sets) { set in
                HStack(spacing: 10) {
                    Text("جولة \(set.setNumber)")
                    Spacer()
                    Text("\(set.weight.gymFormatted) كجم × \(set.reps)")
                        .fontWeight(.semibold)

                    Button {
                        onEdit(set)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive) {
                        Task { await onDelete(set) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.exercise)
                    .fontWeight(.semibold)
                Text(exercise.dayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
