import SwiftUI

/// Modal grid of face thumbnails. Tapping one switches the face at once; the sheet stays open.
struct FacePickerSheet: View {
    let selected: GaugeFace
    let unit: SpeedUnit
    let onSelect: (GaugeFace) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gauge style")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .padding()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(GaugeFace.allCases) { face in
                        thumbnail(face)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func thumbnail(_ face: GaugeFace) -> some View {
        let isSelected = face == selected
        let accent = Color(hex: face.theme.accent)
        return Button {
            onSelect(face)
        } label: {
            VStack(spacing: 8) {
                GaugeDisplay(face: face, reading: .sample(unit: unit), animated: false) {
                    UnitPill(text: unit.symbol, theme: face.theme, compact: true)
                }
                .padding(12)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(face.theme.backgroundGradient, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isSelected ? accent : .clear, lineWidth: 3)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(accent, Color(hex: face.theme.backgroundEdge))
                            .padding(8)
                    }
                }
                Text(face.displayName)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
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
            FacePickerSheet(selected: .analogSport, unit: .kmh) { _ in }
        }
}
