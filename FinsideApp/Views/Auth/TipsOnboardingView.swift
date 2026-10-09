import SwiftUI
import UIKit

/// Необязательные подсказки по продукту: выписка, менеджеры, категории,
/// правила. Чисто просветительское — выполняется по «Хорошо» независимо от
/// того, открыл ли пользователь хоть одно видео.
struct TipsOnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                    Text("Пока вы здесь")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Необязательно, но полезно знать — в приложении есть такие вещи.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(OnboardingTip.all) { tip in
                            TipRow(tip: tip)
                        }
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(.background)
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Хорошо")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(.bar)
            }
        }
    }
}

private struct TipRow: View {
    let tip: OnboardingTip

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: tip.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.subheadline.weight(.semibold))
                Text(tip.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let videoURL = tip.videoURL {
                    Button {
                        UIApplication.shared.open(videoURL)
                    } label: {
                        Label("Смотреть на YouTube", systemImage: "play.rectangle.fill")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }
}

#Preview {
    TipsOnboardingView(onDone: {})
}
