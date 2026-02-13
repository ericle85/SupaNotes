import SwiftUI

struct InstrumentPopoverView: View {
    @Binding var settings: WritingInstrumentSettings
    let sliderRange: ClosedRange<CGFloat>
    let displayColor: Color
    let colorOpacity: Double

    @State private var selectedPresetIndex: Int?

    var body: some View {
        VStack(spacing: 16) {
            // Size preview
            Circle()
                .fill(displayColor.opacity(colorOpacity))
                .frame(
                    width: max(settings.width * previewScale, 6),
                    height: max(settings.width * previewScale, 6)
                )
                .frame(width: 50, height: 50)

            // Width slider
            Slider(value: $settings.width, in: sliderRange)
                .frame(width: 200)

            Text("\(Int(settings.width)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Preset buttons (tap to recall)
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        selectedPresetIndex = index
                        settings.width = settings.presets[index]
                    } label: {
                        let isActive = selectedPresetIndex == index
                        Circle()
                            .fill(displayColor.opacity(colorOpacity))
                            .frame(
                                width: max(settings.presets[index] * previewScale, 4),
                                height: max(settings.presets[index] * previewScale, 4)
                            )
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .stroke(
                                        isActive ? displayColor : Color.secondary.opacity(0.3),
                                        lineWidth: isActive ? 2 : 1
                                    )
                            }
                    }
                }
            }
        }
        .padding(20)
        .presentationCompactAdaptation(.popover)
        .onAppear {
            // Determine initially selected preset
            selectedPresetIndex = settings.presets.firstIndex(where: {
                abs(settings.width - $0) < 0.5
            })
        }
        .onChange(of: settings.width) {
            // Update the selected preset's value when the slider moves
            if let index = selectedPresetIndex {
                settings.presets[index] = settings.width
            }
        }
    }

    private var previewScale: CGFloat {
        // Scale down large previews (eraser) so they fit the 50pt frame
        let maxWidth = sliderRange.upperBound
        return maxWidth > 50 ? 0.5 : 1.0
    }
}
