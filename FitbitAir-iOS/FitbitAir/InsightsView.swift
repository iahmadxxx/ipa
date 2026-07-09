import SwiftUI

struct InsightsView: View {
    @State private var data: InsightsResponse?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let data {
                    InsightCard(icon: "⚡️", title: "الجاهزية", text: data.readiness)
                    InsightCard(icon: "🎯", title: "خطة اليوم", text: data.todayPlan)
                    InsightCard(icon: "🚀", title: "التقدم", text: data.progress)
                    InsightCard(icon: "⚖️", title: "توازن العضلات", text: data.balance)
                    InsightCard(icon: "🧠", title: "اقتراح الأوزان", text: data.nextWeights)
                    InsightCard(icon: "📈", title: "التقرير الأسبوعي", text: data.weeklyReport)
                } else if errorMessage == nil {
                    ProgressView("جاري التحليل…")
                        .padding(.top, 70)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("التحليلات")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            data = try await APIClient.shared.insights()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InsightCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        Card {
            HStack(spacing: 10) {
                Text(icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
            }

            Text(text)
                .font(.subheadline)
                .padding(.top, 5)
                .textSelection(.enabled)
        }
    }
}
