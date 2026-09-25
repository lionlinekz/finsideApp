import SwiftUI

/// Экран после успешной оплаты: что делать дальше в первые минуты.
struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    private var brandName: String {
        appState.user?.brandName ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 24)

            Text(brandName.isEmpty ? "Всё готово" : "\(brandName) во Finside")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Мы отправили письмо со стартовыми шагами на вашу почту.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 10)

            VStack(spacing: 14) {
                StepRow(number: 1, text: "Добавьте банковские счета компании")
                StepRow(number: 2, text: "Загрузите выписку — категории проставятся сами")
                StepRow(number: 3, text: "Пригласите команду и раздайте роли")
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)

            Spacer()

            Button {
                appState.finishWelcome()
            } label: {
                Text("Начать")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: .circle)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
}
