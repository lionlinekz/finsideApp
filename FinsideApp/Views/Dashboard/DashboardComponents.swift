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
}

/// Акценты главного дашборда: спокойная насыщенность, общая палитра без «радуги».
enum DashboardPalette {
    /// Поступления — тёплый янтарь (не чистый жёлтый).
    static let receipts = Color(red: 0.96, green: 0.73, blue: 0.24)
    /// Расход — красный в духе SF, чуть приглушённый.
    static let expense = Color(red: 0.94, green: 0.28, blue: 0.32)
    /// Остаток и положительный поток — мятный зелёный (не неон).
    static let income = Color(red: 0.21, green: 0.71, blue: 0.54)
    /// Продажи — спокойный синий (рядом с SF Blue, без «электрического» cyan).
    static let sales = Color(red: 0.26, green: 0.55, blue: 0.93)
    /// Налог — приглушённая терракота (отдельно от красного расхода).
    static let tax = Color(red: 0.74, green: 0.44, blue: 0.36)
    /// Точки и тёмные акценты выручки.
    static let revenue = Color(red: 0.12, green: 0.48, blue: 0.38)
    static let transfer = Color(red: 0.55, green: 0.55, blue: 0.58)
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
    @Environment(\.colorScheme) private var colorScheme

    let bankName: String
    var fallbackSystemName: String = "building.columns.fill"
    var fallbackTint: Color = .secondary
    var size: CGFloat = 24

    /// Монохромные PNG — в тёмной теме белые, в светлой — тёмные (читаемость на карточке).
    private var catalogTemplateColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.14, green: 0.14, blue: 0.16)
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
