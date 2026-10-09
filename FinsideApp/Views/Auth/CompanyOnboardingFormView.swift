import PhotosUI
import SwiftUI

/// Задача онбординга «компания»: ИИН/БИН подтягивает имя и адрес из реестра,
/// логотип и индустрию пользователь задаёт сам. Сохраняет через уже
/// существующий `addCompany` (тот же путь, что и «Настройки → Филиалы»).
struct CompanyOnboardingFormView: View {
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var bin = ""
    @State private var companyType = "TOO"
    @State private var name = ""
    @State private var address = ""
    @State private var industry: CompanyIndustry?
    @State private var taxMode = ""

    @State private var logoPickerItem: PhotosPickerItem?
    @State private var logoImage: UIImage?
    @State private var logoJPEG: Data?

    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var didLookUp = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: CompanyOnboardingField?

    private var trimmedBin: String { bin.filter(\.isNumber) }
    private var isBinValid: Bool { trimmedBin.count == 12 }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        isBinValid && !trimmedName.isEmpty && !trimmedAddress.isEmpty && industry != nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 8)

                        Text("Расскажите о компании")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("Укажите ИИН или БИН — подтянем название и адрес")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)

                        logoPicker
                            .padding(.top, 24)

                        binField
                            .padding(.top, 24)

                        if didLookUp {
                            fetchedFields
                                .padding(.top, 14)
                                .transition(.opacity)

                            taxModePicker
                                .padding(.top, 14)
                                .transition(.opacity)
                        }

                        industryPicker
                            .padding(.top, 14)

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
                    .animation(.easeInOut(duration: 0.2), value: didLookUp)
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
        .onChange(of: logoPickerItem) { _, item in
            loadLogo(item)
        }
    }

    // MARK: - Логотип

    private var logoPicker: some View {
        PhotosPicker(selection: $logoPickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let logoImage {
                        Image(uiImage: logoImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.12)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(.separator, lineWidth: 1)
                }

                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 30, height: 30)
                    Image(systemName: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().strokeBorder(.background, lineWidth: 2)
                }
                .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Text("Логотип · опционально")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .offset(y: 20)
        }
        .padding(.bottom, 16)
    }

    private func loadLogo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else { return }
            let resized = original.finsideResized(maxDimension: 1024)
            await MainActor.run {
                logoImage = resized
                logoJPEG = resized.jpegData(compressionQuality: 0.85)
            }
        }
    }

    // MARK: - ИИН/БИН

    private var binField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CompanyField(
                    placeholder: "ИИН или БИН (12 цифр)",
                    text: $bin,
                    field: .bin,
                    focus: $focusedField,
                    keyboard: .numberPad,
                    submitLabel: .search,
                    onSubmit: lookUp
                )
                .onChange(of: bin) { _, newValue in
                    bin = String(newValue.filter(\.isNumber).prefix(12))
                }

                Button {
                    lookUp()
                } label: {
                    if isLookingUp {
                        ProgressView()
                            .frame(width: 54, height: 54)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                            .frame(width: 54, height: 54)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isBinValid || isLookingUp)
            }

            if let lookupError {
                Text(lookupError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func lookUp() {
        guard isBinValid else { return }
        focusedField = nil
        lookupError = nil
        isLookingUp = true
        Task {
            do {
                let result = try await APIService.shared.binLookup(bin: trimmedBin)
                name = result.name
                address = result.address
                companyType = result.companyType
                withAnimation { didLookUp = true }
            } catch {
                lookupError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    // MARK: - Подтянутые поля

    private var fetchedFields: some View {
        VStack(spacing: 14) {
            CompanyField(
                placeholder: "Название компании",
                text: $name,
                field: .name,
                focus: $focusedField,
                submitLabel: .next,
                onSubmit: { focusedField = .address }
            )

            CompanyField(
                placeholder: "Адрес",
                text: $address,
                field: .address,
                focus: $focusedField,
                submitLabel: .done,
                onSubmit: { focusedField = nil }
            )
        }
    }

    // MARK: - Налоговый режим

    /// Патент недоступен для ТОО — как в веб-форме и «Настройки → Филиалы».
    private var availableTaxModes: [(value: String, label: String)] {
        var options = [("", "Не указан"), ("USN", "Упрощённый (3%)"), ("OUR", "Общий (10%)")]
        if companyType != "TOO" {
            options.insert(("PATENT", "Патент (1%)"), at: 1)
        }
        return options
    }

    private var taxModeLabel: String {
        availableTaxModes.first { $0.value == taxMode }?.label ?? "Не указан"
    }

    private var taxModePicker: some View {
        Menu {
            ForEach(availableTaxModes, id: \.value) { option in
                Button(option.label) { taxMode = option.value }
            }
        } label: {
            HStack {
                Text("Налоговый режим: \(taxModeLabel)")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onChange(of: companyType) { _, newValue in
            if newValue == "TOO" && taxMode == "PATENT" { taxMode = "" }
        }
    }

    // MARK: - Индустрия

    private var industryPicker: some View {
        Menu {
            ForEach(CompanyIndustry.allCases) { option in
                Button(option.rawValue) { industry = option }
            }
        } label: {
            HStack {
                Text(industry?.rawValue ?? "Индустрия")
                    .foregroundStyle(industry == nil ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Сохранение

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
        guard let industry else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                let company = try await APIService.shared.addCompany(
                    name: trimmedName,
                    bin: trimmedBin,
                    companyType: companyType,
                    direction: industry.rawValue,
                    taxMode: taxMode,
                    address: trimmedAddress
                )
                if let logoJPEG {
                    try? await APIService.shared.uploadCompanyLogo(
                        companyId: company.id,
                        data: logoJPEG,
                        fileName: "logo.jpg",
                        mimeType: "image/jpeg"
                    )
                }
                isSaving = false
                onDone()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

/// Тег поля вынесен из `CompanyOnboardingFormView`: `FocusState.Binding`
/// нельзя параметризовать вложенным приватным типом (см. `SignUpFieldTag`).
private enum CompanyOnboardingField: Hashable {
    case bin, name, address
}

/// Поле ввода в стиле форм авторизации. Отдельная копия `AuthField` /
/// `ProfileField` — те типы приватны для своих файлов.
private struct CompanyField: View {
    let placeholder: String
    @Binding var text: String
    let field: CompanyOnboardingField
    var focus: FocusState<CompanyOnboardingField?>.Binding
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.body)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
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
    CompanyOnboardingFormView(onDone: {})
}
