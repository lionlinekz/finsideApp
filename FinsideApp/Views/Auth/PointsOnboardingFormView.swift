import SwiftUI

/// Задача онбординга «точки»: есть ли физический адрес, и сколько их.
/// Каждая точка — просто название/адрес, без лишних полей.
struct PointsOnboardingFormView: View {
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case loadingCompany
        case noCompany
        case askPhysical
        case addingPoint
        case askMore
    }

    @State private var stage: Stage = .loadingCompany
    @State private var company: BranchCompany?
    @State private var pointName = ""
    @State private var addedPoints: [BranchPoint] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                switch stage {
                case .loadingCompany:
                    ProgressView()
                case .noCompany:
                    noCompanyContent
                case .askPhysical:
                    askContent(
                        question: "У вас есть физический адрес или точка продаж?",
                        subtitle: "Например, офис, магазин, склад или пункт выдачи",
                        onYes: { withAnimation { stage = .addingPoint } },
                        onNo: onDone
                    )
                case .addingPoint:
                    addingPointContent
                case .askMore:
                    askContent(
                        question: "Есть ещё точки?",
                        subtitle: "Можно добавить сколько угодно — сейчас или позже в настройках",
                        onYes: { withAnimation { pointName = ""; stage = .addingPoint } },
                        onNo: onDone
                    )
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .background(.background)
            .animation(.easeInOut(duration: 0.2), value: stage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .task { await loadCompany() }
    }

    // MARK: - Нет компании

    private var noCompanyContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Сначала заполните данные компании")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Точки привязываются к компании — сначала выполните предыдущую задачу чек-листа.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Да/Нет шаги

    @ViewBuilder
    private func askContent(
        question: String,
        subtitle: String,
        onYes: @escaping () -> Void,
        onNo: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 20)

            if !addedPoints.isEmpty {
                addedPointsList
                    .padding(.bottom, 16)
            }

            Text(question)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button("Нет", action: onNo)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Да", action: onYes)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 28)
        }
    }

    // MARK: - Добавление точки

    private var addingPointContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 16)

            Text("Как назвать точку?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("Например: «Главный офис» или «Магазин на Абая»")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            TextField("Название или адрес точки", text: $pointName)
                .font(.body)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(addPoint)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(.top, 28)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }

            Button {
                addPoint()
            } label: {
                ZStack {
                    Text("Добавить").opacity(isSaving ? 0 : 1)
                    if isSaving { ProgressView() }
                }
                .frame(maxWidth: .infinity, minHeight: 22)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .disabled(isSaving || pointName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { isFocused = true }
    }

    private var addedPointsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(addedPoints) { point in
                Label(point.address, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    // MARK: - Действия

    private func loadCompany() async {
        do {
            let companies = try await APIService.shared.branches()
            company = companies.first
            stage = company == nil ? .noCompany : .askPhysical
        } catch {
            stage = .noCompany
        }
    }

    private func addPoint() {
        let name = pointName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let companyId = company?.id else { return }
        isFocused = false
        errorMessage = nil
        isSaving = true
        Task {
            do {
                let point = try await APIService.shared.addPoint(companyId: companyId, address: name)
                addedPoints.append(point)
                withAnimation { stage = .askMore }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    PointsOnboardingFormView(onDone: {})
}
