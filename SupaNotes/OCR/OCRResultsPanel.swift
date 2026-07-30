import SwiftUI

struct OCRResultsPanel: View {
    let blocks: [RecognizedBlock]
    let isReady: Bool

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

            if blocks.isEmpty {
                Text("Write something to see recognition results")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(blocks) { block in
                            BlockResultView(block: block)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

private struct BlockResultView: View {
    let block: RecognizedBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(block.kind.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(block.kind == .math ? Color.blue : Color.green)
                Text(String(format: "%.0f%%", block.confidence * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(block.content)
                .font(.system(.body, design: block.kind == .math ? .monospaced : .default))
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }
}
