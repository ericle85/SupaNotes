import SwiftUI
import UIKit
import PencilKit

struct DrawingToolbar: View {
    @Binding var selectedColor: Color
    @Binding var penWidth: CGFloat
    @Binding var eraserWidth: CGFloat
    @Binding var isErasing: Bool
    var undoManager: UndoManager?

    @State private var showColorPicker = false
    @State private var showPenSlider = false
    @State private var showEraserSlider = false

    private let presetColors: [(Color, String)] = [
        (.primary, "Black"),
        (.red, "Red"),
        (.blue, "Blue"),
        (.green, "Green"),
    ]

    var currentTool: PKTool {
        if isErasing {
            return PKEraserTool(.bitmap, width: eraserWidth)
        } else {
            return PKInkingTool(.pen, color: UIColor(selectedColor), width: penWidth)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Undo / Redo
            Button { undoManager?.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            Button { undoManager?.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }

            Divider().frame(width: 28)

            // Pen
            Button {
                if !isErasing {
                    showPenSlider.toggle()
                } else {
                    isErasing = false
                }
                showEraserSlider = false
            } label: {
                Image(systemName: "pencil.tip")
                    .fontWeight(!isErasing ? .bold : .regular)
            }
            .foregroundStyle(!isErasing ? selectedColor : .secondary)
            .popover(isPresented: $showPenSlider, arrowEdge: .trailing) {
                VStack(spacing: 16) {
                    Circle()
                        .fill(selectedColor)
                        .frame(width: max(penWidth, 6), height: max(penWidth, 6))
                        .frame(width: 50, height: 50)

                    Slider(value: $penWidth, in: 1...50)
                        .frame(width: 200)

                    Text("\(Int(penWidth)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .presentationCompactAdaptation(.popover)
            }

            // Eraser
            Button {
                if isErasing {
                    showEraserSlider.toggle()
                } else {
                    isErasing = true
                }
                showPenSlider = false
            } label: {
                Image(systemName: "eraser.fill")
                    .fontWeight(isErasing ? .bold : .regular)
            }
            .foregroundStyle(isErasing ? .primary : .secondary)
            .popover(isPresented: $showEraserSlider, arrowEdge: .trailing) {
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: max(eraserWidth * 0.5, 6), height: max(eraserWidth * 0.5, 6))
                        .frame(width: 50, height: 50)

                    Slider(value: $eraserWidth, in: 10...150)
                        .frame(width: 200)

                    Text("\(Int(eraserWidth)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .presentationCompactAdaptation(.popover)
            }

            Divider().frame(width: 28)

            // Color presets
            ForEach(presetColors, id: \.1) { color, name in
                Button {
                    selectedColor = color
                    isErasing = false
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selectedColor == color && !isErasing {
                                Image(systemName: "checkmark")
                                    .font(.caption2.bold())
                                    .foregroundStyle(color == .primary ? Color.secondary : .white)
                            }
                        }
                        .overlay {
                            Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                        }
                }
                .accessibilityLabel(name)
            }

            // Rainbow color picker button
            Button {
                showColorPicker = true
                isErasing = false
            } label: {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            center: .center
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1)
                    }
            }
            .popover(isPresented: $showColorPicker) {
                ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .padding()
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        }
    }
}
