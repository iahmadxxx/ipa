import SwiftUI

enum FitTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let accent = Color.cyan
    static let gradient = LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}
struct Card<Content: View>: View { @ViewBuilder let content: Content; var body: some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(FitTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous)) } }
struct MetricCard: View { let icon, title, value: String; var body: some View { Card { HStack(spacing: 12) { Text(icon).font(.title2); VStack(alignment:.leading, spacing:4){ Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.bold()) } } } } }
