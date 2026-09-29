import SwiftUI

// MARK: - Coach tab

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "How is my recovery trending?",
        "Should I train hard today?",
        "Why might my HRV be low?",
        "How can I fix my sleep debt?",
        "Am I eating enough protein?",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if model.coachReady {
                    chat
                } else {
                    ScrollView {
                        CoachSetupCard()
                            .padding(16)
                    }
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                if model.coachReady && !model.coachMessages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.clearCoachChat()
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityLabel("Clear conversation")
                    }
                }
            }
        }
    }

    // MARK: Chat

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        if model.coachMessages.isEmpty {
                            intro
                        }
                        ForEach(model.coachMessages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if model.coachBusy {
                            HStack {
                                ProgressView().tint(Theme.teal)
                                Text("Thinking…").font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .id("busy")
                        }
                        if let error = model.coachError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.coachMessages.count) { _, _ in
                    withAnimation {
                        if let last = model.coachMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: model.coachBusy) { _, busy in
                    if busy { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                }
            }
            inputBar
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(Theme.teal)
                Text("Ask about your data")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("I can see your last two weeks of recovery, sleep, strain, stress, workouts and nutrition, and I'll answer with your actual numbers.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    HStack {
                        Text(suggestion).font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardElevated))
                    .foregroundStyle(Theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            Text(privacyNote)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var privacyNote: String {
        switch model.coachEngine {
        case .apple:
            return "\(model.coachStatus) Not medical advice."
        case .claude:
            return "Your recent metrics are sent to Anthropic when you chat. Not medical advice."
        }
    }

    private func bubble(_ message: CoachMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 48) }
            Text(markdown(message.text))
                .font(.subheadline)
                .foregroundStyle(isUser ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isUser ? Theme.teal : Theme.card)
                )
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.cardElevated))
                .foregroundStyle(Theme.textPrimary)
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? Theme.teal : Theme.textSecondary.opacity(0.5))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.coachBusy
    }

    private func send(_ text: String) {
        let message = text
        draft = ""
        Task { await model.sendCoach(message) }
    }
}

// MARK: - API key setup

struct CoachSetupCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionCard("Set up your AI coach") {
            CoachEnginePicker()
            if model.coachEngine == .claude {
                Text("Claude runs through your own Anthropic API key, stored only in this iPhone's Keychain.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                CoachKeyEditor()
                Text("Create a key at console.anthropic.com. Usage is billed to your Anthropic account. When you chat or estimate a meal, the relevant data (recent metrics, your message, or the photo) is sent to Anthropic's API.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Engine choice + status, used by the Coach tab and by More → AI Coach.
struct CoachEnginePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Picker("Engine", selection: $model.coachEngine) {
                ForEach(CoachEngine.allCases) { engine in
                    Text(engine.label).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            Label(model.coachStatus, systemImage: model.coachReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(model.coachReady ? Theme.green : Theme.yellow)
            if model.coachEngine == .apple {
                Text("Free, private and needs no key. It's Apple's on-device model — smaller than Claude, so answers are shorter and use a one-week data summary. Photo meal estimates need Claude.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Key entry + model field, used by the Coach tab and by More → AI Coach.
struct CoachKeyEditor: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            if model.coachKeyPresent {
                HStack {
                    Label("API key saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.green)
                        .font(.subheadline)
                    Spacer()
                    Button("Remove", role: .destructive) { model.clearCoachKey() }
                        .font(.subheadline)
                }
            } else {
                SecureField("sk-ant-…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
                    .foregroundStyle(Theme.textPrimary)
                Button {
                    if model.setCoachKey(key) { key = "" }
                } label: {
                    Text("Save key")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.teal))
                        .foregroundStyle(Color.black)
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.caption2).foregroundStyle(Theme.textSecondary)
                TextField("Model ID", text: $model.coachModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardElevated))
                    .foregroundStyle(Theme.textPrimary)
                Text("Default \(CoachClient.defaultModel). Cheaper option: claude-sonnet-5-5.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
