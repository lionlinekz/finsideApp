import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum DashboardHaptics {
    static func lightImpact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

/// Акценты главного дашборда: спокойная насыщенность, общая палитра без «радуги».
enum DashboardPalette {
    /// Поступления — золото.
    static let receipts = Color(red: 0.80, green: 0.63, blue: 0.13)
    /// Расход — красный.
    static let expense = Color(red: 1.0, green: 0.0, blue: 0.0)
    /// Остаток и положительный поток — изумрудный (#4CAE85).
    static let income = Color(red: 76 / 255, green: 174 / 255, blue: 133 / 255)
    /// Продажи — #1863DC.
    static let sales = Color(red: 24 / 255, green: 99 / 255, blue: 220 / 255)
    /// Налог — приглушённая терракота (отдельно от красного расхода).
    static let tax = Color(red: 0.74, green: 0.44, blue: 0.36)
    /// Точки и акценты выручки — как `DashboardPalette.income`.
    static let revenue = DashboardPalette.income
    static let transfer = Color(red: 0.55, green: 0.55, blue: 0.58)
}

/// Цикл из 5 цветов колец на главной (снаружи → внутрь):
/// синий → зелёный → красный → золото → серебро.
enum DashboardRingPalette {
    /// 1. Продажи — #1863DC.
    static let revenue = DashboardPalette.sales

    /// 2. Остаток — #4CAE85.
    static let balance = DashboardPalette.income

    /// 3. Расходы — красный.
    static let expense = DashboardPalette.expense

    /// 4. Поступления — золото.
    static let receipts = DashboardPalette.receipts

    /// 5. Налоги — серебро / графит.
    static func tax(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.82, green: 0.84, blue: 0.88)
            : Color(red: 0.52, green: 0.54, blue: 0.60)
    }
}

// Логотипы `BankLogoKaspi` / `BankLogoHalyk` в Assets (из TrackApp).
enum BankBrandAsset {
    /// Имя картинки в каталоге ассетов или `nil`, если использовать SF Symbol.
    static func catalogImageName(for bankName: String) -> String? {
        let s = bankName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("kaspi") { return "BankLogoKaspi" }
        if s.contains("halyk") || s.contains("халык") { return "BankLogoHalyk" }
        return nil
    }
}

/// Марка банка: логотип из ассетов (Kaspi / Halyk) или запасной SF Symbol.
struct BankLogoMark: View {
    let bankName: String
    var fallbackSystemName: String = "building.columns.fill"
    var fallbackTint: Color = .secondary
    var size: CGFloat = 24

    /// Монохромные PNG — template tint по семантическому `primary`.
    private var catalogTemplateColor: Color {
        .primary
    }

    var body: some View {
        Group {
            if let asset = BankBrandAsset.catalogImageName(for: bankName) {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundStyle(catalogTemplateColor)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: fallbackSystemName)
                    .font(.system(size: max(11, size * 0.46), weight: .semibold))
                    .foregroundStyle(fallbackTint)
                    .frame(width: size, height: size)
            }
        }
    }
}

enum DashboardMoney {
    static func formatTenge(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        return "\(f.string(from: NSNumber(value: v)) ?? "0") ₸"
    }

    static func formatOptionalTenge(_ v: Double?) -> String {
        guard let v else { return "нет данных" }
        return formatTenge(v)
    }

    static func formatShortTenge(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "%.1fM ₸", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "%.0fK ₸", v / 1_000) }
        return String(format: "%.0f ₸", v)
    }

    static func formatCompact(_ v: Double) -> String {
        if abs(v) >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if abs(v) >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    static func percent(_ v: Double, of total: Double) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", (v / total) * 100)
    }

    static func shortDateLabel(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return String(iso.suffix(5)) }
        let o = DateFormatter()
        o.locale = Locale(identifier: "ru_RU")
        o.dateFormat = "dd.MM"
        return o.string(from: d)
    }

    static func longDateLabel(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter()
        o.locale = Locale(identifier: "ru_RU")
        o.dateStyle = .long
        o.timeStyle = .none
        return o.string(from: d)
    }
}

/// Лёгкое подтверждение нажатия — пружина и едва заметный масштаб (ближе к системным контролам).
struct DashboardPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.987 : 1, anchor: .center)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DashboardPressableStyle {
    static var dashboardPressable: DashboardPressableStyle { DashboardPressableStyle() }
}

// MARK: - Liquid Glass

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.45),
                                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.10),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.50),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.15),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.40 : 0.08),
                radius: 16, y: 8
            )
    }
}

struct LiquidGlassChipModifier: ViewModifier {
    var isSelected: Bool = false
    var tint: Color = .accentColor
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(tint)
                } else {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if !isSelected {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10),
                            lineWidth: 0.5
                        )
                }
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.22 : 0.05),
                radius: isSelected ? 6 : 4, y: 2
            )
    }
}

struct LiquidGlassBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 1)
                    }
            }
    }
}

// MARK: - Dynamics chart

struct DashboardDynamicsChart: View {
    let points: [ChartPoint]
    var onSelectDay: ((ChartPoint) -> Void)?

    private let plotHeight: CGFloat = 152
    private let barWidth: CGFloat = 8
    private let segmentGap: CGFloat = 3
    private let xLabelHeight: CGFloat = 34
    private let scrollThreshold = 10

    private var axisMaximum: Double {
        Self.niceUpperBound(points.map { $0.income + $0.expense }.max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                legendItem(color: DashboardPalette.income, title: "Доход")
                legendItem(color: DashboardPalette.expense, title: "Расход")
            }

            chartPlot
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chartPlot: some View {
        if points.count > scrollThreshold {
            ScrollView(.horizontal, showsIndicators: false) {
                chartColumns(evenlyDistributed: false)
                    .padding(.horizontal, 2)
            }
            .frame(height: plotHeight + xLabelHeight)
        } else {
            chartColumns(evenlyDistributed: true)
                .frame(height: plotHeight + xLabelHeight)
        }
    }

    private func chartColumns(evenlyDistributed: Bool) -> some View {
        HStack(alignment: .bottom, spacing: evenlyDistributed ? 0 : 10) {
            ForEach(points) { point in
                dayColumn(point)
                    .frame(maxWidth: evenlyDistributed ? .infinity : nil)
            }
        }
    }

    private func dayColumn(_ point: ChartPoint) -> some View {
        let incomeHeight = segmentHeight(point.income)
        let expenseHeight = segmentHeight(point.expense)
        let hasData = point.income > 0 || point.expense > 0
        let stackHeight = max(
            incomeHeight + expenseHeight + (incomeHeight > 0 && expenseHeight > 0 ? segmentGap : 0),
            hasData ? 8 : 3
        )

        return Button {
            DashboardHaptics.lightImpact()
            onSelectDay?(point)
        } label: {
            VStack(spacing: 6) {
                Spacer(minLength: 0)

                VStack(spacing: segmentGap) {
                    if expenseHeight > 0 {
                        matchstick(color: DashboardPalette.expense, height: expenseHeight)
                    }
                    if incomeHeight > 0 {
                        matchstick(color: DashboardPalette.income, height: incomeHeight)
                    }
                    if !hasData {
                        matchstick(color: Color(.quaternaryLabel), height: 3)
                            .opacity(0.35)
                    }
                }
                .frame(height: stackHeight, alignment: .bottom)

                Text(DashboardMoney.shortDateLabel(point.date))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: barWidth, height: xLabelHeight)
            }
            .frame(minWidth: max(barWidth + 4, 22), maxHeight: .infinity, alignment: .bottom)
            .contentShape(.rect)
        }
        .buttonStyle(.dashboardPressable)
        .accessibilityLabel(dayAccessibilityLabel(point))
    }

    private func matchstick(color: Color, height: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: barWidth, height: height)
    }

    private func segmentHeight(_ value: Double) -> CGFloat {
        guard value > 0, axisMaximum > 0 else { return 0 }
        return max(4, CGFloat(value / axisMaximum) * plotHeight)
    }

    private func dayAccessibilityLabel(_ point: ChartPoint) -> String {
        let date = DashboardMoney.shortDateLabel(point.date)
        return "День \(date), доход \(DashboardMoney.formatTenge(point.income)), расход \(DashboardMoney.formatTenge(point.expense))"
    }

    private static func niceUpperBound(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let scale = pow(10.0, exponent)
        let normalized = value / scale
        let niceNormalized: Double
        if normalized <= 1 { niceNormalized = 1 }
        else if normalized <= 2 { niceNormalized = 2 }
        else if normalized <= 5 { niceNormalized = 5 }
        else { niceNormalized = 10 }
        return niceNormalized * scale
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassChip(isSelected: Bool = false, tint: Color = .accentColor) -> some View {
        modifier(LiquidGlassChipModifier(isSelected: isSelected, tint: tint))
    }

    func liquidGlassBar() -> some View {
        modifier(LiquidGlassBarModifier())
    }
}
