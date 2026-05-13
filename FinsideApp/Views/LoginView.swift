import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        @Bindable var state = appState

        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                Text("Finside")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .padding(.bottom, 36)

                VStack(spacing: 16) {
                    TextField("Электронная почта", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Button {
                    Task {
                        await appState.login(email: email, password: password)
                    }
                } label: {
                    if appState.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 22)
                    } else {
                        Text("Войти")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 22)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .disabled(email.isEmpty || password.isEmpty || appState.isLoading)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
