import SwiftUI

/// Modal grid of face thumbnails. Tapping one switches the face at once; the sheet stays open. Below the grid, the
/// "Engine sounds" switch (specs/engine-clip-toggle R1).
struct FacePickerSheet: View {
    static let soundHeading = String(localized: "Sound")
    static let engineSoundsLabel = String(localized: "Engine sounds")
    static let engineSoundsHint = String(localized: "Plays a short clip when the engine starts. Off stops the microphone.")

    let selected: GaugeFace
    let unit: SpeedUnit
    let engineSoundsOn: Bool
    let onEngineSoundsChange: (Bool) -> Void
    let onSelect: (GaugeFace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gauge style")
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose your instrument cluster appearance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .padding()

            ScrollView {
                VStack(spacing: 24) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(GaugeFace.allCases) { face in
                            thumbnail(face)
                        }
                    }
                    soundSection
                }
                .padding([.horizontal, .bottom])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// A heading, a standard switch and its help line, which is also the switch's hint (R12).
    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.soundHeading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Toggle(Self.engineSoundsLabel, isOn: Binding(get: { engineSoundsOn }, set: onEngineSoundsChange))
                .accessibilityHint(Self.engineSoundsHint)
            // `.primary`, not `.secondary`: `.secondary` measured 3.0:1 over Retro's light sheet (R12 needs 4.5:1).
            Text(Self.engineSoundsHint)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            GlassBackground(
                shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                tint: .white.opacity(0.04),
                colorScheme: colorScheme
            )
        }
    }

    private func thumbnail(_ face: GaugeFace) -> some View {
        let isSelected = face == selected
        let accent = Color(hex: face.theme.accent)
        return Button {
            onSelect(face)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                GaugeDisplay(face: face, reading: .sample(unit: unit), animated: false) {
                    UnitPill(text: unit.symbol, theme: face.theme, compact: true)
                }
                .padding(12)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(face.theme.backgroundGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack {
                    Text(face.displayName)
                        .font(face.theme.font(role: .secondary, textStyle: .subheadline, size: 15))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    if isSelected {
                        // Decorative: the selected trait already says this (specs/ui-redesign R18).
                        Text("Active")
                            .font(Theme.captionFont(textStyle: .caption2, size: 11))
                            .textCase(.uppercase)
                            .kerning(0.8)
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(10)
            .background {
                GlassBackground(
                    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    tint: .white.opacity(0.04),
                    colorScheme: colorScheme
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(hex: face.theme.backgroundEdge), accent)
                        .padding(16)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(face.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Picker") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            FacePickerSheet(selected: .analogSport, unit: .kmh, engineSoundsOn: true, onEngineSoundsChange: { _ in }) { _ in }
        }
}

#Preview("Picker, engine sounds off") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            FacePickerSheet(selected: .retro, unit: .kmh, engineSoundsOn: false, onEngineSoundsChange: { _ in }) { _ in }
        }
}

#Preview("Picker, largest text") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            FacePickerSheet(selected: .minimalRing, unit: .kmh, engineSoundsOn: true, onEngineSoundsChange: { _ in }) { _ in }
                .environment(\.dynamicTypeSize, .accessibility3)
        }
}

#Preview("Picker, landscape", traits: .landscapeLeft) {
    Color.black
        .sheet(isPresented: .constant(true)) {
            FacePickerSheet(selected: .digitalHUD, unit: .mph, engineSoundsOn: true, onEngineSoundsChange: { _ in }) { _ in }
        }
}
