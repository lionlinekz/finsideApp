import PhotosUI
import SwiftUI

/// Задача онбординга «кто ты»: имя, фамилия, опциональное селфи и телефон.
/// Сохраняется на сервер; по успеху вызывает `onDone`, который отмечает
/// задачу выполненной в `AppState`.
struct ProfileOnboardingFormView: View {
    let onDone: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""

    @State private var selfiePickerItem: PhotosPickerItem?
    @State private var selfieImage: UIImage?
    @State private var selfieJPEG: Data?

    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: ProfileOnboardingField?

    private var canSubmit: Bool {
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty && !trimmedPhone.isEmpty
    }

    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespaces) }
    private var trimmedLastName: String { lastName.trimmingCharacters(in: .whitespaces) }
    private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)

                        Text("Расскажите о себе")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("Это поможет команде Finside узнавать вас")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)

                        selfiePicker
                            .padding(.top, 28)

                        fields
                            .padding(.top, 28)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 14)
                        }

                        Spacer(minLength: 24)

                        submitButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(minHeight: proxy.size.height - 48)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: selfiePickerItem) { _, item in
            loadSelfie(item)
        }
    }

    // MARK: - Селфи

    private var selfiePicker: some View {
        PhotosPicker(selection: $selfiePickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let selfieImage {
                        Image(uiImage: selfieImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(Color.secondary.opacity(0.12))
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 104, height: 104)
                .clipShape(.circle)
                .overlay {
                    Circle().strokeBorder(.separator, lineWidth: 1)
                }

                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 32, height: 32)
                    Image(systemName: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().strokeBorder(.background, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Text("Селфи · опционально")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .offset(y: 118)
        }
        .padding(.bottom, 16)
    }

    private func loadSelfie(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else { return }
            let resized = original.finsideResized(maxDimension: 1024)
            await MainActor.run {
                selfieImage = resized
                selfieJPEG = resized.jpegData(compressionQuality: 0.85)
            }
        }
    }

    // MARK: - Поля

    private var fields: some View {
        VStack(spacing: 14) {
            ProfileField(
                placeholder: "Имя",
                text: $firstName,
                field: .firstName,
                focus: $focusedField,
                contentType: .givenName,
                submitLabel: .next,
                onSubmit: { focusedField = .lastName }
            )

            ProfileField(
                placeholder: "Фамилия",
                text: $lastName,
                field: .lastName,
                focus: $focusedField,
                contentType: .familyName,
                submitLabel: .next,
                onSubmit: { focusedField = .phone }
            )

            ProfileField(
                placeholder: "Телефон",
                text: $phone,
                field: .phone,
                focus: $focusedField,
                contentType: .telephoneNumber,
                keyboard: .phonePad,
                submitLabel: .done,
                onSubmit: { focusedField = nil }
            )
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 22)
            } else {
                Text("Сохранить")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit || isSaving)
    }

    private func submit() {
        errorMessage = nil
        isSaving = true
        let selfie = selfieJPEG.map { (data: $0, fileName: "selfie.jpg", mimeType: "image/jpeg") }
        Task {
            do {
                let user = try await APIService.shared.updateProfile(
                    firstName: trimmedFirstName,
                    lastName: trimmedLastName,
                    phone: trimmedPhone,
                    selfie: selfie
                )
                appState.user = user
                isSaving = false
                onDone()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

/// Тег поля вынесен из `ProfileOnboardingFormView`: `FocusState.Binding`
/// нельзя параметризовать вложенным приватным типом (см. `SignUpFieldTag`).
private enum ProfileOnboardingField: Hashable {
    case firstName, lastName, phone
}

/// Поле ввода в стиле форм авторизации: крупная область нажатия, рамка
/// материалом карточки. Отдельная копия `AuthField` из `SignUpView` — тот
/// тип приватен для своего файла.
private struct ProfileField: View {
    let placeholder: String
    @Binding var text: String
    let field: ProfileOnboardingField
    var focus: FocusState<ProfileOnboardingField?>.Binding
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .focused(focus, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .onTapGesture { focus.wrappedValue = field }
    }
}

#Preview {
    ProfileOnboardingFormView(onDone: {})
        .environment(AppState())
}
