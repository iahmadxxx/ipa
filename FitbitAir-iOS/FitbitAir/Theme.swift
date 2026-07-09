import SwiftUI

// MARK: - FitbitAir visual system

enum FitTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let backgroundSoft = Color(red: 0.05, green: 0.065, blue: 0.095)
    static let card = Color.white.opacity(0.075)
    static let cardStrong = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.15, green: 0.91, blue: 0.84)
    static let accentBlue = Color(red: 0.22, green: 0.55, blue: 1.0)
    static let accentPurple = Color(red: 0.58, green: 0.42, blue: 1.0)
    static let positive = Color(red: 0.28, green: 0.88, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let danger = Color(red: 1.0, green: 0.35, blue: 0.45)

    static let gradient = LinearGradient(
        colors: [accent, accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [background, Color(red: 0.055, green: 0.075, blue: 0.12)],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            FitTheme.backgroundGradient
            Circle()
                .fill(FitTheme.accent.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 160, y: -260)
            Circle()
                .fill(FitTheme.accentPurple.opacity(0.08))
                .frame(width: 330, height: 330)
                .blur(radius: 90)
                .offset(x: -170, y: 320)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(FitTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(FitTheme.stroke, lineWidth: 1)
                    )
            )
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { GlassCard(content: { content }) }
}

struct MetricCard: View {
    let systemIcon: String
    let title: String
    let value: String
    let tint: Color
    var subtitle: String? = nil

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tint.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: systemIcon)
                            .foregroundStyle(tint)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accent)
            }
        }
    }
}

struct LoadingStateView: View {
    let text: String
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(FitTheme.accent).scaleEffect(1.15)
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FitTheme.warning)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
        .padding(14)
        .background(FitTheme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FitTheme.danger.opacity(0.22)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(FitTheme.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct CompactIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(FitTheme.cardStrong, in: Circle())
                .overlay(Circle().stroke(FitTheme.stroke))
        }
    }
}
