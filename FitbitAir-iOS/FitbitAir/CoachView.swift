import SwiftUI

struct CoachView: View {
    @State private var messages: [ChatMessage] = [
        .init(
            role: .assistant,
            text: "هلا أحمد 👋 اسألني عن تمرينك، نومك، جاهزيتك أو تقدمك."
        )
    ]
    @State private var input = ""
    @State private var loading = false

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if loading {
                            HStack {
                                ProgressView()
                                Text("المدرب يفكر…")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    scrollToLatest(using: proxy)
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("اكتب للمدرب الذكي…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(trimmedInput.isEmpty || loading)
            }
            .padding()
        }
        .navigationTitle("المدرب الذكي")
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let id = messages.last?.id else { return }
        withAnimation {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func send() async {
        let question = trimmedInput
        guard !question.isEmpty else { return }

        input = ""
        messages.append(.init(role: .user, text: question))
        loading = true

        do {
            let answer = try await APIClient.shared.ask(question)
            messages.append(.init(role: .assistant, text: answer))
        } catch {
            messages.append(
                .init(
                    role: .assistant,
                    text: "تعذر الرد: \(error.localizedDescription)"
                )
            )
        }

        loading = false
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 50) }

            Text(message.text)
                .padding(12)
                .background(
                    isUser ? Color.cyan.opacity(0.2) : FitTheme.card,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .frame(
                    maxWidth: 300,
                    alignment: isUser ? .trailing : .leading
                )

            if !isUser { Spacer(minLength: 50) }
        }
    }
}
