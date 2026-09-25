import Combine
import SwiftUI

/// Ввод 4-значного кода, присланного на почту при регистрации.
///
/// После верного кода экран не висит спиннером: сразу показывает галочку, а
/// затем — что происходит дальше. Создание схемы тенанта занимает несколько
/// секунд, и это единственный способ не выглядеть зависшим.
struct OtpVerificationView: View {
    let email: String

    @Environment(AppState.self) private var appState
    @FocusState private var isFocused: Bool

    @State private var stage: Stage = .entering
    @State private var code = ""
    @State private var secondsLeft = 60
    @State private var resendError: String?
    @State private var isResending = false
    @State private var statusMessage = "Создаём рабочее пространство"
    @State private var failureMessage: String?

    private enum Stage {
        case entering
        /// Код принят — галочка.
        case accepted
        /// Готовим рабочее пространство.
        case preparing
        case failed
    }

    private let codeLength = 4
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                switch stage {
                case .entering:
                    entryContent
                case .accepted, .preparing:
                    progressContent
                case .failed:
                    failureContent
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .background(.background)
            .animation(.easeInOut(duration: 0.25), value: stage)
            .onReceive(timer) { _ in
                if stage == .entering, secondsLeft > 0 { secondsLeft -= 1 }
            }
        }
    }

    // MARK: - Ввод кода

    private var entryContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 20)

            Text("Проверьте почту")
                .font(.title.bold())

            Text("Отправили код на \(email)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            codeBoxes
                .padding(.top, 32)

            if let error = resendError ?? appState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }

            if appState.isLoading {
                ProgressView()
                    .padding(.top, 20)
            }

            resendButton
                .padding(.top, 24)

            Button("Изменить почту") {
                appState.startSignUp()
            }
            .font(.subheadline)
            .padding(.top, 12)
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
    }

    // Невидимое поле держит реальный ввод, а рамки — только отображение.
    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $code)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .focused($isFocused)
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    code = String(digits.prefix(codeLength))
                    if code.count == codeLength {
                        submit()
                    }
                }

            HStack(spacing: 12) {
                ForEach(0..<codeLength, id: \.self) { index in
                    Text(character(at: index))
                        .font(.title.monospacedDigit().weight(.semibold))
                        .frame(width: 56, height: 64)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    index == code.count && isFocused
                                        ? Color.accentColor
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var resendButton: some View {
        if secondsLeft > 0 {
            Text("Новый код можно запросить через \(secondsLeft) сек")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Button {
                resend()
            } label: {
                if isResending {
                    ProgressView()
                } else {
                    Text("Отправить код снова")
                        .fontWeight(.medium)
                }
            }
            .disabled(isResending)
        }
    }

    // MARK: - Код принят и подготовка

    private var progressContent: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(stage == .entering ? 0.4 : 1)
            }
            .padding(.bottom, 24)

            Text("Почта подтверждена")
                .font(.title2.bold())

            HStack(spacing: 10) {
                ProgressView()
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)

            Text("Обычно занимает несколько секунд")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .transition(.opacity)
    }

    private var failureContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .padding(.bottom, 20)

            Text("Почта подтверждена")
                .font(.title2.bold())

            Text(failureMessage ?? "Не удалось подготовить рабочее пространство.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Button("Попробовать снова") {
                waitForWorkspace()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 24)
        }
    }

    // MARK: - Действия

    private func character(at index: Int) -> String {
        guard index < code.count else { return "" }
        let position = code.index(code.startIndex, offsetBy: index)
        return String(code[position])
    }

    private func submit() {
        isFocused = false
        Task {
            let accepted = await appState.verifyOtp(email: email, code: code)
            guard accepted else {
                // Код не подошёл — очищаем поле, чтобы не стирать вручную.
                code = ""
                isFocused = true
                return
            }
            stage = .accepted
            waitForWorkspace()
        }
    }

    private func waitForWorkspace() {
        stage = .preparing
        failureMessage = nil
        Task {
            let error = await appState.awaitWorkspaceReady { message in
                statusMessage = message
            }
            if let error {
                failureMessage = error
                stage = .failed
            } else {
                appState.routeAfterAuth()
            }
        }
    }

    private func resend() {
        resendError = nil
        isResending = true
        Task {
            resendError = await appState.resendOtp(email: email)
            isResending = false
            if resendError == nil {
                secondsLeft = 60
                code = ""
                isFocused = true
            }
        }
    }
}

#Preview {
    OtpVerificationView(email: "owner@example.com")
        .environment(AppState())
}
