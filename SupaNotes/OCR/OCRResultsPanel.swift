import SwiftUI

struct OCRResultsPanel: View {
    let blocks: [RecognizedBlock]
    let isReady: Bool
    @Binding var selectedBlockID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OCR Results")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(isReady ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding()

            Divider()

            OCRInferencesList(blocks: blocks, selectedBlockID: $selectedBlockID)

            Divider()

            SpatialPageText(blocks: blocks)
        }
        .background(Color(.systemBackground))
    }
}

private struct OCRInferencesList: View {
    let blocks: [RecognizedBlock]
    @Binding var selectedBlockID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OCR inferences")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 10)

            if blocks.isEmpty {
                Text("no replayed OCR yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding()
                Spacer()
                    .frame(height: 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(blocks) { block in
                            OCRInferenceRow(
                                block: block,
                                isSelected: selectedBlockID == block.id
                            ) {
                                selectedBlockID = selectedBlockID == block.id ? nil : block.id
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

private struct OCRInferenceRow: View {
    let block: RecognizedBlock
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2fs", block.recognizedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Text(block.content.isEmpty ? "(empty CTC output)" : block.content)
                    .font(.system(.caption, design: block.kind == .math ? .monospaced : .default))
                    .lineLimit(2)
                    .foregroundStyle(block.content.isEmpty ? Color.secondary : Color.primary)

                Spacer(minLength: 0)

                Text(block.kind.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(kindBadgeColor.opacity(0.15))
                    .foregroundStyle(kindBadgeColor)
                    .clipShape(Capsule())
            }
            .padding(6)
            .background(isSelected ? kindBadgeColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? kindBadgeColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var kindBadgeColor: Color {
        if block.kind == .math { return Color.blue }
        if block.kind == .text { return Color.green }
        return Color.gray
    }
}

private struct SpatialPageText: View {
    let blocks: [RecognizedBlock]

    private let pageWidth = LetterPageSize.width
    private let pageHeight = LetterPageSize.height

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spatial page text")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)
                .padding(.top, 10)

            GeometryReader { geometry in
                let size = aspectFitSize(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .border(Color(.separator), width: 1)

                    ForEach(blocks) { block in
                        let content = block.content
                        if !content.isEmpty {
                            positionedText(for: block, in: size)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .aspectRatio(pageWidth / pageHeight, contentMode: .fit)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func aspectFitSize(in container: CGSize) -> CGSize {
        let scale = min(container.width / pageWidth, container.height / pageHeight)
        return CGSize(width: pageWidth * scale, height: pageHeight * scale)
    }

    private func positionedText(for block: RecognizedBlock, in size: CGSize) -> some View {
        let centerX = block.bbox.midX / pageWidth
        let centerY = block.bbox.midY / pageHeight
        let color = block.kind == .math ? Color.blue : Color.green

        return Text(content(for: block))
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .position(x: centerX * size.width, y: centerY * size.height)
    }

    private func content(for block: RecognizedBlock) -> String {
        if block.kind == .math { return block.content }
        return block.content
    }
}
