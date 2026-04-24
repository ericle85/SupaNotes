import SwiftUI

// Pen settings panel: style picker, tip sharpness slider, pressure sensitivity slider,
// and a live stroke preview rendered with the current settings.
struct PenCustomizationView: View {
    @Binding var settings: WritingInstrumentSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                strokePreview
                // Floating island: dropdown + conditional sliders in one card.
                VStack(alignment: .leading, spacing: 16) {
                    penStylePicker
                    if settings.penStyle == .fountain {
                        Divider()
                        tipSharpnessSlider
                        pressureSensitivitySlider
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut(duration: 0.2), value: settings.penStyle)
            }
            .padding(20)
        }
    }

    // MARK: - Stroke Preview

    // Fixed preview width so strokes are always clearly visible regardless of user's pen width.
    private static let previewStrokeWidth: CGFloat = 6

    // Single stroke preview for the currently selected pen style,
    // updating in real time as tip sharpness and pressure sensitivity change.
    private var strokePreview: some View {
        Canvas { context, size in
            let midY = size.height * 0.5
            let points = Self.syntheticStroke(in: size, midY: midY, amplitude: size.height * 0.25)

            let stroke = ExcalidrawPageStroke(
                id: UUID(),
                tool: .pen,
                color: CodableColor(color: .white),
                width: Self.previewStrokeWidth,
                points: points,
                penStyle: settings.penStyle,
                tipSharpness: settings.tipSharpness,
                pressureSensitivity: settings.pressureSensitivity
            )

            context.withCGContext { cgContext in
                cgContext.setStrokeColor(UIColor.white.cgColor)
                cgContext.setFillColor(UIColor.white.cgColor)
                StrokeRenderer.drawStroke(stroke, in: cgContext)
            }
        }
        .drawingGroup()
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    // Build sample points along a wave with simulated pressure ramp.
    private static func syntheticStroke(
        in size: CGSize,
        midY: CGFloat,
        amplitude: CGFloat
    ) -> [ExcalidrawPagePoint] {
        let count = 30
        let margin: CGFloat = 24
        let usableWidth = size.width - margin * 2
        return (0 ..< count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            let x = margin + t * usableWidth
            // S-curve via sine wave.
            let y = midY - sin(t * .pi * 2) * amplitude
            // Pressure ramps up then tapers: peak in the middle.
            let pressure = 0.15 + 0.85 * sin(t * .pi)
            return ExcalidrawPagePoint(CGPoint(x: x, y: y), pressure: pressure)
        }
    }

    // MARK: - Pen Style Picker

    private var penStylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PEN STYLE")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tracking(1)
            Picker("Pen Style", selection: $settings.penStyle) {
                ForEach(PenStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.iconName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tip Sharpness

    private var tipSharpnessSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TIP SHARPNESS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Text("\(Int(settings.tipSharpness * 100))%")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Slider(value: $settings.tipSharpness, in: 0 ... 1, step: 0.05)
        }
    }

    // MARK: - Pressure Sensitivity

    private var pressureSensitivitySlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PRESSURE SENSITIVITY")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Text(settings.pressureSensitivity >= 0.99 ? "Max" : "\(Int(settings.pressureSensitivity * 100))%")
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Slider(value: $settings.pressureSensitivity, in: 0 ... 1, step: 0.05)
        }
    }
}
