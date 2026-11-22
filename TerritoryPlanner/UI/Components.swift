import SwiftUI

/// Section title used inside panels.
struct PanelSectionHeader: View {
    let title: String
    var systemImage: String?
    var trailing: AnyView?

    init(_ title: String, systemImage: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// Labelled slider with a live value badge.
struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.accent)
        }
    }
}

/// Compact metric tile.
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 12, cornerRadius: 14)
    }
}

/// Primary call-to-action.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Secondary, outlined action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Round icon button for transport controls.
struct CircleIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 44
    var prominent = false
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.38, weight: .bold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surfaceStrong))
            )
            .overlay(Circle().strokeBorder(prominent ? Color.clear : Theme.hairline))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// Thin capsule progress bar with gradient fill.
struct GradientProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.12), value: fraction)
    }
}

/// Circular progress ring.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(
                    AngularGradient(colors: [Theme.accentSecondary, Theme.accent, Theme.accentSecondary], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: fraction)
        }
    }
}

/// Pill-style option chip.
struct Chip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceStrong))
            )
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.hairline))
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: isSelected)
    }
}

/// Row with a toggle and an optional subtitle.
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.92))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .tint(Theme.accent)
    }
}
