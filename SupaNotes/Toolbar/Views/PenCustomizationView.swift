import SwiftUI

// PenCustomizationView commented out — pen customization removed, ballpoint only.
// Re-enable by uncommenting and restoring PenStyle + related fields in WritingInstrumentSettings,
// ExcalidrawPageStroke, ExcalidrawToolStyle, and StrokeRenderer.
/*
struct PenCustomizationView: View {
    @Binding var settings: WritingInstrumentSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                strokePreview
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

    private static let previewStrokeWidth: CGFloat = 6

    private var strokePreview: some View {
        let penStyle = settings.penStyle
        let tipSharpness = settings.tipSharpness
        let pressureSensitivity = settings.pressureSensitivity
        return Canvas { context, size in
            let points = Self.syntheticStroke(in: size)
            let stroke = ExcalidrawPageStroke(
                id: UUID(),
                tool: .pen,
                color: CodableColor(color: .white),
                width: Self.previewStrokeWidth,
                points: points,
                penStyle: penStyle,
                tipSharpness: tipSharpness,
                pressureSensitivity: pressureSensitivity
            )
            context.withCGContext { cgContext in
                UIGraphicsPushContext(cgContext)
                defer { UIGraphicsPopContext() }
                StrokeRenderer.drawStroke(stroke, in: cgContext)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private static func syntheticStroke(in size: CGSize) -> [ExcalidrawPagePoint] {
        var raw: [(x: CGFloat, y: CGFloat)] = []
        let tMax = sqrt(CGFloat.pi)
        let spiralN = 20
        for i in 0 ..< spiralN {
            let t = -tMax + CGFloat(i) / CGFloat(spiralN - 1) * tMax
            let (c, s) = fresnel(t)
            raw.append((x: c, y: s))
        }
        let cosN = 30
        let xEnd = 1.5 * CGFloat.pi
        for i in 1 ... cosN {
            let x = CGFloat(i) / CGFloat(cosN) * xEnd
            raw.append((x: x, y: cos(x) - 1))
        }
        let xs = raw.map(\.x)
        let ys = raw.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let pad: CGFloat = 24
        let scale = min((size.width - pad * 2) / max(maxX - minX, 0.001),
                        (size.height - pad * 2) / max(maxY - minY, 0.001))
        let cx = size.width * 0.5
        let cy = size.height * 0.5
        let midRawX = (minX + maxX) * 0.5
        let midRawY = (minY + maxY) * 0.5
        let total = raw.count
        return raw.enumerated().map { i, pt in
            let x = cx + (pt.x - midRawX) * scale
            let y = cy + (pt.y - midRawY) * scale
            let t = CGFloat(i) / CGFloat(total - 1)
            let pressure = 0.15 + 0.85 * sin(t * .pi)
            return ExcalidrawPagePoint(CGPoint(x: x, y: y), pressure: pressure)
        }
    }

    private static func fresnel(_ t: CGFloat) -> (c: CGFloat, s: CGFloat) {
        let n = 100
        let dt = t / CGFloat(n)
        var c: CGFloat = 0
        var s: CGFloat = 0
        for i in 0 ..< n {
            let u = (CGFloat(i) + 0.5) * dt
            c += cos(u * u) * dt
            s += sin(u * u) * dt
        }
        return (c, s)
    }

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
*/
