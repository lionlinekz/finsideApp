import SwiftUI

struct SignUpView: View {
    @Environment(AppState.self) private var appState

    @State private var brandName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var agree = false
    @State private var agreePrivacy = false
    @State private var showPassword = false
    /// Ошибки полей показываем только после первой попытки отправки,
    /// чтобы форма не краснела, пока человек ещё печатает.
    @State private var didAttemptSubmit = false
    @State private var localError: String?

    @FocusState private var focusedField: SignUpFieldTag?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        Text("Создать аккаунт")
                            .font(.largeTitle.bold())
                            .padding(.bottom, 32)

                        fields
                        agreements
                        errorBanner
                        submitButton
                        loginLink

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    // Короткая форма стоит по центру, длинная — прокручивается.
                    .frame(minHeight: proxy.size.height - 48)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(.background)
        }
    }

    // MARK: - Блоки

    private var fields: some View {
        VStack(spacing: 14) {
            AuthField(
                placeholder: "Название компании",
                text: $brandName,
                field: .brand,
                focus: $focusedField,
                error: didAttemptSubmit && trimmedBrand.isEmpty ? "Укажите название" : nil,
                contentType: .organizationName,
                submitLabel: .next,
                onSubmit: { focusedField = .email }
            )

            AuthField(
                placeholder: "Электронная почта",
                text: $email,
                field: .email,
                focus: $focusedField,
                error: didAttemptSubmit && !isEmailValid ? "Проверьте адрес почты" : nil,
                contentType: .emailAddress,
                keyboard: .emailAddress,
                submitLabel: .next,
                onSubmit: { focusedField = .password }
            )

            AuthField(
                placeholder: "Пароль",
                text: $password,
                field: .password,
                focus: $focusedField,
                error: didAttemptSubmit && !isPasswordLongEnough ? "Минимум 8 символов" : nil,
                isSecure: !showPassword,
                trailing: {
                    AnyView(
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    )
                },
                contentType: .newPassword,
                submitLabel: .next,
                onSubmit: { focusedField = .passwordConfirm }
            )

            AuthField(
                placeholder: "Повторите пароль",
                text: $passwordConfirm,
                field: .passwordConfirm,
                focus: $focusedField,
                error: shouldShowMismatch ? "Пароли не совпадают" : nil,
                isSecure: !showPassword,
                contentType: .newPassword,
                submitLabel: .go,
                onSubmit: submit
            )
        }
    }

    private var agreements: some View {
        VStack(spacing: 12) {
            AgreementRow(
                isOn: $agree,
                text: "Принимаю условия использования",
                url: AuthLinks.terms
            )
            AgreementRow(
                isOn: $agreePrivacy,
                text: "Принимаю политику конфиденциальности",
                url: AuthLinks.privacy
            )
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = localError ?? appState.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            if appState.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 22)
            } else {
                Text("Продолжить")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 24)
        .disabled(!isComplete || appState.isLoading)
    }

    private var loginLink: some View {
        HStack(spacing: 4) {
            Text("Уже есть аккаунт?")
                .foregroundStyle(.secondary)
            Button("Войти") {
                appState.backToLogin()
            }
            .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.top, 20)
    }

    // MARK: - Валидация

    private var trimmedBrand: String {
        brandName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = value.firstIndex(of: "@") else { return false }
        let domain = value[value.index(after: at)...]
        return at != value.startIndex && domain.contains(".") && !domain.hasSuffix(".")
    }

    private var isPasswordLongEnough: Bool {
        password.count >= 8
    }

    private var shouldShowMismatch: Bool {
        guard !passwordConfirm.isEmpty else { return false }
        return password != passwordConfirm
    }

    /// Кнопка загорается, только когда форму действительно можно отправить —
    /// как на экране входа.
    private var isComplete: Bool {
        firstProblem == nil
    }

    /// Первое, чего не хватает для отправки.
    private var firstProblem: (message: String, field: SignUpFieldTag?)? {
        if trimmedBrand.isEmpty { return ("Укажите название компании", .brand) }
        if !isEmailValid { return ("Проверьте адрес электронной почты", .email) }
        if !isPasswordLongEnough { return ("Пароль должен быть не короче 8 символов", .password) }
        if password != passwordConfirm { return ("Пароли не совпадают", .passwordConfirm) }
        if !agree { return ("Отметьте согласие с условиями использования", nil) }
        if !agreePrivacy { return ("Отметьте согласие с политикой конфиденциальности", nil) }
        return nil
    }

    private func submit() {
        didAttemptSubmit = true
        localError = nil

        if let problem = firstProblem {
            localError = problem.message
            focusedField = problem.field
            return
        }

        focusedField = nil
        Task {
            _ = await appState.signUp(
                brandName: brandName,
                email: email,
                password: password,
                passwordConfirm: passwordConfirm
            )
        }
    }
}

/// Ссылки, которых требует App Review на экранах регистрации и оплаты.
enum AuthLinks {
    static let terms = URL(string: "https://finside.pro/terms/")!
    static let privacy = URL(string: "https://finside.pro/static/docs/privacy_policy.pdf")!
}

// MARK: - Поле ввода

/// Поле с крупной областью нажатия.
///
/// `.padding()` на самом `TextField` оставлял активной только тонкую строку
/// текста, и в поле приходилось попадать с нескольких попыток. Здесь тап ловит
/// вся карточка и переводит фокус сама.
private struct AuthField: View {
    let placeholder: String
    @Binding var text: String
    let field: SignUpFieldTag
    var focus: FocusState<SignUpFieldTag?>.Binding
    var error: String?
    var isSecure: Bool = false
    var trailing: (() -> AnyView)?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                input
                    .font(.body)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                    .focused(focus, equals: field)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)

                if let trailing {
                    trailing()
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(error != nil ? .red : .clear, lineWidth: 1.5)
            }
            // Тап ловит вся карточка, а не только строка текста.
            .contentShape(.rect(cornerRadius: 12))
            .onTapGesture { focus.wrappedValue = field }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

/// Тег поля вынесен из SignUpView: FocusState.Binding нельзя параметризовать
/// вложенным приватным типом.
enum SignUpFieldTag: Hashable {
    case brand, email, password, passwordConfirm
}

// MARK: - Согласия

private struct AgreementRow: View {
    @Binding var isOn: Bool
    let text: String
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Link(destination: url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture { isOn.toggle() }
    }
}

#Preview {
    SignUpView()
        .environment(AppState())
}
