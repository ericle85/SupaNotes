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
                // Push CGContext onto UIGraphics stack so UIBezierPath.stroke()/fill() work.
                UIGraphicsPushContext(cgContext)
                defer { UIGraphicsPopContext() }
                StrokeRenderer.drawStroke(stroke, in: cgContext)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    // Euler spiral (Fresnel integrals) from t = -√π to 0, then cos(x) - 1
    // from x = 0 to 3π/2. Joined at origin with matching tangent (1, 0).
    private static func syntheticStroke(in size: CGSize) -> [ExcalidrawPagePoint] {
        var raw: [(x: CGFloat, y: CGFloat)] = []

        // Part 1: Euler spiral entry via Fresnel integrals.
        let tMax = sqrt(CGFloat.pi)
        let spiralN = 20
        for i in 0 ..< spiralN {
            let t = -tMax + CGFloat(i) / CGFloat(spiralN - 1) * tMax
            let (c, s) = fresnel(t)
            raw.append((x: c, y: s))
        }

        // Part 2: cos(x) - 1 from x = 0 to 3π/2 (starts at (0,0), tangent (1,0)).
        let cosN = 30
        let xEnd = 1.5 * CGFloat.pi
        for i in 1 ... cosN {
            let x = CGFloat(i) / CGFloat(cosN) * xEnd
            raw.append((x: x, y: cos(x) - 1))
        }

        // Scale and center into the preview rect.
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
            // Pressure peaks mid-stroke, tapers at ends.
            let t = CGFloat(i) / CGFloat(total - 1)
            let pressure = 0.15 + 0.85 * sin(t * .pi)
            return ExcalidrawPagePoint(CGPoint(x: x, y: y), pressure: pressure)
        }
    }

    // Numerical Fresnel integrals: C(t) = ∫₀ᵗ cos(s²)ds, S(t) = ∫₀ᵗ sin(s²)ds.
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
