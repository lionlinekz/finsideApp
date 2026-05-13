import SwiftUI

struct PinSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var isConfirming = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.bottom, 12)

            Text(isConfirming ? "Подтвердите PIN" : "Создайте PIN")
                .font(.title2.bold())
                .padding(.bottom, 8)

            Text(isConfirming
                 ? "Введите тот же PIN ещё раз"
                 : "Задайте 4-значный PIN для защиты приложения")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(currentPin.count > i ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.bottom, 8)

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }

            Spacer()

            PinPadView(pin: isConfirming ? $confirmPin : $pin) {
                handleComplete()
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .ignoresSafeArea(edges: .bottom)
    }

    private var currentPin: String {
        isConfirming ? confirmPin : pin
    }

    private func handleComplete() {
        if !isConfirming {
            withAnimation { isConfirming = true }
        } else {
            if pin == confirmPin {
                appState.setPin(pin)
            } else {
                error = "PIN не совпадают. Попробуйте снова."
                confirmPin = ""
                withAnimation { isConfirming = false }
                pin = ""
            }
        }
    }
}

// MARK: - Number Pad

struct PinPadView: View {
    @Binding var pin: String
    var onComplete: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    private let buttons: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "delete"],
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 72, height: 72)
                        } else if key == "delete" {
                            Button {
                                if !pin.isEmpty { pin.removeLast() }
                            } label: {
                                Image(systemName: "delete.left")
                                    .font(.title2)
                                    .frame(width: 72, height: 72)
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Button {
                                guard pin.count < 4 else { return }
                                pin.append(key)
                                if pin.count == 4 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        onComplete()
                                    }
                                }
                            } label: {
                                Text(key)
                                    .font(.title)
                                    .fontWeight(.medium)
                                    .frame(width: 72, height: 72)
                                    .background(.regularMaterial, in: .circle)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PinSetupView()
        .environment(AppState())
}
