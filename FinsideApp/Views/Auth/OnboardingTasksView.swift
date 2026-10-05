import SwiftUI

/// Обязательные задачи после оплаты. Показывается вместо главной, пока не
/// выполнены все пункты — см. `AppState.onboardingTasksCompleted`.
struct OnboardingTasksView: View {
    @Environment(AppState.self) private var appState
    @State private var activeTask: OnboardingTask?

    private var doneCount: Int {
        OnboardingTask.all.filter { appState.completedOnboardingTaskIds.contains($0.id) }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Image(systemName: "checklist")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.bottom, 20)

                Text("Ещё пара шагов")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text("Выполните короткий список, чтобы открыть доступ к приложению.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 8)

                progressBar
                    .padding(.horizontal, 32)
                    .padding(.top, 24)

                VStack(spacing: 12) {
                    ForEach(OnboardingTask.all) { task in
                        TaskRow(
                            task: task,
                            isDone: appState.completedOnboardingTaskIds.contains(task.id)
                        ) {
                            activeTask = task
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                Spacer(minLength: 24)

                Button("Выйти") {
                    appState.logout()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(item: $activeTask) { task in
            switch task.kind {
            case .acknowledgment:
                OnboardingTaskModal(task: task) {
                    appState.completeOnboardingTask(task.id)
                    activeTask = nil
                }
            case .profileForm:
                ProfileOnboardingFormView {
                    appState.completeOnboardingTask(task.id)
                    activeTask = nil
                }
            }
        }
    }

    private var progressBar: some View {
        let total = OnboardingTask.all.count
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat(doneCount) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 6)

            Text("\(doneCount) из \(total)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.25), value: doneCount)
    }
}

private struct TaskRow: View {
    let task: OnboardingTask
    let isDone: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: isDone ? "checkmark" : task.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .strikethrough(isDone)
                        .multilineTextAlignment(.leading)

                    Text(task.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
                    .font(isDone ? .title3 : .footnote)
                    .foregroundStyle(isDone ? Color.accentColor : Color(.tertiaryLabel))
            }
            .padding(14)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isDone ? Color.accentColor.opacity(0.25) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .opacity(isDone ? 0.7 : 1)
    }
}

/// Модалка задачи-уведомления: описание, опциональная ссылка и «Хорошо».
/// Задача считается выполненной по нажатию «Хорошо» независимо от того,
/// открыл ли пользователь ссылку.
private struct OnboardingTaskModal: View {
    let task: OnboardingTask
    let onDone: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 20)

            Text(task.modalTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(task.modalMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            if let linkURL = task.linkURL, let linkLabel = task.linkLabel {
                Button {
                    openURL(linkURL)
                } label: {
                    Text(linkLabel)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }

            Spacer()

            Button(action: onDone) {
                Text("Хорошо")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .presentationDetents([.medium])
    }
}

#Preview {
    OnboardingTasksView()
        .environment(AppState())
}
