import SwiftUI
import SwiftData
import PencilKit

struct NoteEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ToolbarState.self) private var toolbar
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    @State private var canvasUndoManager: UndoManager?
    @State private var isWriting: Bool = false
    @State private var currentPageIndex: Int = 0

    private var note: Note? { notes.first }

    init(noteID: UUID) {
        _notes = Query(filter: #Predicate<Note> { note in
            note.id == noteID
        })
    }

    private var currentTool: PKTool {
        switch toolbar.activeTool {
        case .pen:
            return PKInkingTool(.pen, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .pencil))
        case .eraser:
            return PKEraserTool(.bitmap, width: toolbar.instrumentWidth(for: .eraser))
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(toolbar.selectedColor), width: toolbar.instrumentWidth(for: .highlighter))
        case .lasso:
            return PKLassoTool()
        }
    }

    var body: some View {
        if let note {
            noteContent(note)
        } else {
            ContentUnavailableView("Note not found", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private func noteContent(_ note: Note) -> some View {
        @Bindable var toolbar = toolbar

        ZStack {
            // Canvas
            PagedCanvasContainer(
                pages: Binding(
                    get: { note.sortedPages },
                    set: { _ in }
                ),
                tool: currentTool,
                onUndoManagerReady: { canvasUndoManager = $0 },
                onPencilDoubleTap: { toolbar.switchToPreviousTool() },
                onWritingStateChanged: { isWriting = $0 },
                onCurrentPageChanged: { currentPageIndex = $0 },
                addPage: {
                    let newIndex = note.pages.count
                    let page = Page(orderIndex: newIndex)
                    page.note = note
                    modelContext.insert(page)
                    note.updatedAt = .now
                }
            )
            .ignoresSafeArea()

            // Home button - top left
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color("ToolbarBackground"))
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                    .padding(.leading, 16)
                    .padding(.top, 12)

                    Spacer()
                }
                Spacer()
            }
            .opacity(isWriting ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isWriting)

            // Toolbar
            DrawingToolbar(
                toolbarIcons: $toolbar.toolbarIcons,
                selectedColor: $toolbar.selectedColor,
                activeTool: $toolbar.activeTool,
                undoManager: canvasUndoManager
            )
            .opacity(1)
            .animation(.easeInOut(duration: 0.2), value: isWriting)

            VStack {
                Spacer()
                HStack {
                    PageCounterView(currentPage: currentPageIndex, totalPages: note.pages.count)
                        .padding(.leading, 20)
                        .padding(.bottom, 20)
                    Spacer()
                }
            }
            .opacity(isWriting ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isWriting)
        }
        .navigationBarHidden(true)
        .onChange(of: toolbar.selectedColor) {
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.activeTool) { oldValue, newValue in
            if oldValue != newValue {
                toolbar.previousTool = oldValue
            }
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) {
            toolbar.save(colorScheme: colorScheme)
        }
    }
}
