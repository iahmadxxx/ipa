import SwiftUI

struct CoachView: View {
    @State private var messages: [ChatMessage] = [
        .init(role: .assistant, text: "هلا أحمد 👋 أنا أقرأ نومك، نبضك، جاهزيتك وتمارينك. اسألني أي شيء عن وضعك اليوم.")
    ]
    @State private var input = ""
    @State private var loading = false
    @FocusState private var isInputFocused: Bool

    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private let quickPrompts = [
        "شرايك في تمريني اليوم؟",
        "هل أزيد الأوزان؟",
        "أتمرن اليوم ولا أريح؟"
    ]

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                coachHeader
                messagesArea
                inputBar
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var coachHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(FitTheme.gradient).frame(width: 48, height: 48)
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.78))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("مدرب أحمد الذكي")
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Circle().fill(FitTheme.positive).frame(width: 7, height: 7)
                    Text("متصل ببياناتك الحالية")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(FitTheme.accent)
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.08))
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 13) {
                    if messages.count == 1 {
                        quickPromptStrip
                    }

                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if loading {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in scrollToLatest(using: proxy) }
            .onChange(of: loading) { _, _ in
                withAnimation {
                    if loading {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    } else if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var quickPromptStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("اقتراحات سريعة")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.42))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            input = prompt
                            Task { await send() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(FitTheme.card, in: Capsule())
                        .overlay(Capsule().stroke(FitTheme.stroke))
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("اسأل مدربك الذكي…", text: $input, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(FitTheme.cardStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FitTheme.stroke))
                .submitLabel(.send)
                .onSubmit { Task { await send() } }

            Button {
                Task { await send() }
            } label: {
                ZStack {
                    Circle()
                        .fill(trimmedInput.isEmpty || loading ? Color.white.opacity(0.10) : FitTheme.accent)
                        .frame(width: 46, height: 46)
                    Image(systemName: loading ? "hourglass" : "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(trimmedInput.isEmpty || loading ? .white.opacity(0.35) : Color.black.opacity(0.82))
                }
            }
            .disabled(trimmedInput.isEmpty || loading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial.opacity(0.9))
        .overlay(alignment: .top) { Divider().opacity(0.15) }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
    }

    private func send() async {
        let question = trimmedInput
        guard !question.isEmpty, !loading else { return }
        input = ""
        isInputFocused = false
        messages.append(.init(role: .user, text: question))
        loading = true
        do {
            let answer = try await APIClient.shared.ask(question)
            messages.append(.init(role: .assistant, text: answer))
        } catch {
            messages.append(.init(role: .assistant, text: "تعذر الرد: \(error.localizedDescription)"))
        }
        loading = false
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                ZStack {
                    Circle().fill(FitTheme.accent.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: "brain.head.profile")
                        .font(.caption.bold())
                        .foregroundStyle(FitTheme.accent)
                }
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    isUser ? AnyShapeStyle(FitTheme.gradient) : AnyShapeStyle(FitTheme.cardStrong),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
                .overlay {
                    if !isUser {
                        RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(FitTheme.stroke)
                    }
                }
                .frame(maxWidth: 310, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 32) }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(FitTheme.accent.opacity(0.15)).frame(width: 30, height: 30)
                Image(systemName: "brain.head.profile")
                    .font(.caption.bold())
                    .foregroundStyle(FitTheme.accent)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(FitTheme.accent)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.15 : 0.65)
                        .animation(.easeInOut(duration: 0.55).repeatForever().delay(Double(index) * 0.14), value: pulse)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(FitTheme.cardStrong, in: Capsule())
            Spacer()
        }
        .onAppear { pulse = true }
    }
}
