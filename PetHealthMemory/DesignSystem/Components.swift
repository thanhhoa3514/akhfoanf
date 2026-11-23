import SwiftUI

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = AppTheme.Spacing.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.bgSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .strokeBorder(AppTheme.Colors.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = AppTheme.Spacing.lg) -> some View { modifier(CardModifier(padding: padding)) }

    /// Canvas background that never paints system bars (keeps iOS 26 Liquid Glass / macOS toolbars native).
    func canvasBackground() -> some View {
        background(AppTheme.Colors.bgCanvas.ignoresSafeArea())
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    #if os(macOS)
    static let font = Font.body.weight(.semibold)
    #else
    static let font = Font.headline
    #endif

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Self.font)
            .foregroundStyle(isEnabled ? AppTheme.Colors.onBrandPrimary : AppTheme.Colors.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Size.button)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(
                isEnabled ? AppTheme.Colors.brandPrimary : AppTheme.Colors.bgElevated,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.input, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(AppTheme.Motion.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PrimaryButtonStyle.font)
            .foregroundStyle(AppTheme.Colors.brandText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Size.button)
            .padding(.horizontal, AppTheme.Spacing.md)
            .background(AppTheme.Colors.brandPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.Radius.input, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Icon above a single-line title, for equal-width action tiles (Home capture card).
struct TileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            configuration.icon.font(.title3)
            configuration.title
                .font(.appSubheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Pills & badges

/// Small capsule label. Never relies on colour alone — always pairs an icon + text.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = AppTheme.Colors.brandPrimary
    var textColor: Color = AppTheme.Colors.brandText

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text).lineLimit(1)
        }
        .font(.appCaption.weight(.semibold))
        .foregroundStyle(textColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Provenance badge linking a record to its original document (DESIGN.md — Source traceability).
struct SourceBadge: View {
    let title: String

    var body: some View {
        Pill(
            text: title,
            systemImage: "doc.text.magnifyingglass",
            tint: AppTheme.Colors.statusSource,
            textColor: AppTheme.Colors.sourceText
        )
        .accessibilityLabel(Text("Source document: \(title)"))
    }
}

/// AI-uncertain marker. Amber + dashed stroke + question icon + "Check" label (distinct from due-soon amber).
struct NeedsCheckBadge: View {
    var text: String = String(localized: "Check")

    var body: some View {
        Pill(
            text: text,
            systemImage: "questionmark.circle.fill",
            tint: AppTheme.Colors.statusWarning,
            textColor: AppTheme.Colors.warningText
        )
        .accessibilityLabel("Needs your check")
    }
}

struct DueBadge: View {
    let date: Date
    var isCompleted = false
    /// Days ahead that count as "due soon". Vaccines get a longer runway (book the vet).
    var soonWindow = DueState.defaultSoonWindow

    var body: some View {
        let state = DueState(date: date, isCompleted: isCompleted, soonWindow: soonWindow)
        Pill(text: state.label, systemImage: state.symbol, tint: state.fill, textColor: state.text)
    }
}

/// Shared due-date semantics: overdue (danger) / soon ≤7d (warning, clock icon) / later (secondary).
struct DueState {
    let label: String
    let symbol: String
    let fill: Color
    let text: Color

    static let defaultSoonWindow = 7
    static let vaccineSoonWindow = 30

    init(date: Date, isCompleted: Bool = false, soonWindow: Int = DueState.defaultSoonWindow, now: Date = .now) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if isCompleted {
            label = String(localized: "Done"); symbol = "checkmark"; fill = AppTheme.Colors.statusSuccess; text = AppTheme.Colors.successText
        } else if date < now && days < 0 {
            label = days == -1 ? String(localized: "Overdue · yesterday") : String(localized: "Overdue · \(-days)d")
            symbol = "exclamationmark.circle.fill"; fill = AppTheme.Colors.statusDanger; text = AppTheme.Colors.dangerText
        } else if days == 0 {
            label = String(localized: "Today"); symbol = "clock.fill"; fill = AppTheme.Colors.statusWarning; text = AppTheme.Colors.warningText
        } else if days <= soonWindow {
            label = days == 1 ? String(localized: "Due tomorrow") : String(localized: "Due in \(days) days")
            symbol = "clock"; fill = AppTheme.Colors.statusWarning; text = AppTheme.Colors.warningText
        } else {
            // Always say what the date means — a bare date chip was ambiguous (given? due?).
            label = String(localized: "Due \(date.formatted(.dateTime.day().month(.abbreviated).year()))")
            symbol = "calendar"; fill = AppTheme.Colors.textSecondary; text = AppTheme.Colors.textSecondary
        }
    }
}

// MARK: - Icons & avatars

/// Tinted circular icon used for event types / document rows.
struct TypeIcon: View {
    let systemImage: String
    var tint: Color = AppTheme.Colors.brandPrimary
    var size: CGFloat = AppTheme.Size.rowIcon

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

struct PetAvatar: View {
    let pet: PetModel?
    var size: CGFloat = 56
    @Environment(AppContainer.self) private var container

    var body: some View {
        Group {
            if let path = pet?.photoPath,
               let image = PlatformImage(contentsOfFile: container.fileStorage.resolveURL(relativePath: path).path) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: pet?.speciesSymbol ?? "pawprint.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.Colors.brandAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(AppTheme.Colors.bgSurface, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.brandText)
                    .frame(minHeight: AppTheme.Size.minTouch)
            }
        }
    }
}

// MARK: - Filter pills (matchedGeometryEffect sliding selection)

struct FilterPillBar<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(options) { option in
                    let isSelected = option == selection
                    Button {
                        withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                            selection = option
                        }
                    } label: {
                        Text(title(option))
                            .font(.appSubheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? AppTheme.Colors.onBrandPrimary : AppTheme.Colors.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(AppTheme.Colors.brandPrimary)
                                        .matchedGeometryEffect(id: "pill", in: pillNamespace)
                                } else {
                                    Capsule().fill(AppTheme.Colors.bgElevated)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
    }
}

// MARK: - Processing scanline (OCR / AI)

/// Soft scanline sweeping over a thumbnail while processing. Static tint under Reduce Motion —
/// the step checklist next to it carries the actual meaning.
struct ScanlineOverlay: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    if reduceMotion {
                        AppTheme.Colors.brandPrimary.opacity(0.08)
                    } else {
                        GeometryReader { proxy in
                            LinearGradient(
                                colors: [.clear, AppTheme.Colors.brandPrimary.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: proxy.size.height * 0.25)
                            .offset(y: phase * proxy.size.height * 1.25 - proxy.size.height * 0.25)
                        }
                        .clipped()
                        .onAppear {
                            phase = 0
                            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                                phase = 1
                            }
                        }
                    }
                }
            }
            .allowsHitTesting(!isActive)
    }
}

extension View {
    func scanline(isActive: Bool) -> some View { modifier(ScanlineOverlay(isActive: isActive)) }
}

// MARK: - Info rows

struct InfoRow: View {
    let label: String
    let value: String
    var systemImage: String?
    var verbatim = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.appCaption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .textSelection(.enabled)
                if verbatim {
                    Label("As written on the document", systemImage: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Footer reminding users the app organizes records but is not a veterinary authority (PRD §5.10).
struct MedicalDisclaimer: View {
    var body: some View {
        Label("Pet Health Memory organizes your records. It doesn't give medical advice — always follow your vet.", systemImage: "stethoscope")
            .font(.footnote)
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
