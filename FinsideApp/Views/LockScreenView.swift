import SwiftUI

struct LockScreenView: View {
    @Environment(AppState.self) private var appState
    @State private var pin = ""
    @State private var shake = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .padding(.bottom, 12)

            Text("Введите PIN")
                .font(.title2.bold())
                .padding(.bottom, 8)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(pin.count > i ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 16, height: 16)
                }
            }
            .offset(x: shake ? -10 : 0)
            .padding(.bottom, 8)

            Spacer()

            if BiometricService.isAvailable {
                Button {
                    Task { await appState.unlockWithBiometrics() }
                } label: {
                    Label(
                        BiometricService.availableType == .faceID ? "Face ID" : "Touch ID",
                        systemImage: BiometricService.availableType == .faceID
                            ? "faceid" : "touchid"
                    )
                    .font(.body.weight(.medium))
                }
                .padding(.bottom, 16)
            }

            PinPadView(pin: $pin) {
                handlePinEntered()
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            if BiometricService.isAvailable {
                Task { await appState.unlockWithBiometrics() }
            }
        }
    }

    private func handlePinEntered() {
        // Разблокировка, лимит попыток и проверка подписки — в AppState.
        if !appState.unlockWithPin(pin), appState.currentScreen == .lockScreen {
            withAnimation(.default.speed(3).repeatCount(3, autoreverses: true)) {
                shake = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                shake = false
                pin = ""
            }
        }
    }
}

#Preview {
    LockScreenView()
        .environment(AppState())
}
