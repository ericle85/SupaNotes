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
        let pageManager = PageManager(modelContext: modelContext)

        ZStack {
            PagedCanvasContainer(
                pages: Binding(
                    get: { note.sortedPages },
                    set: { _ in }
                ),
                tool: toolbar.currentPKTool,
                onUndoManagerReady: { canvasUndoManager = $0 },
                onPencilDoubleTap: { toolbar.switchToPreviousTool() },
                onWritingStateChanged: { isWriting = $0 },
                onCurrentPageChanged: { currentPageIndex = $0 },
                addPage: { pageManager.addPage(to: note) },
                addPageAbove: { pageManager.addPageAbove(in: note) }
            )
            .ignoresSafeArea()

            // Home button
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: Design.FontSize.headerIcon, weight: .semibold))
                            .foregroundStyle(.primary)
                            .floatingButton()
                    }
                    .padding(.leading, Design.Spacing.headerHorizontal)
                    .padding(.top, 12)
                    Spacer()
                }
                Spacer()
            }
            .opacity(isWriting ? 0 : 1)
            .animation(.easeInOut(duration: Design.Animation.writingFadeDuration), value: isWriting)

            DrawingToolbar(
                toolbarIcons: $toolbar.toolbarIcons,
                selectedColor: $toolbar.selectedColor,
                activeTool: $toolbar.activeTool,
                undoManager: canvasUndoManager
            )
            .animation(.easeInOut(duration: Design.Animation.writingFadeDuration), value: isWriting)

            VStack {
                Spacer()
                HStack {
                    PageCounterView(currentPage: currentPageIndex, totalPages: note.pages.count)
                        .padding(.leading, Design.Spacing.pageCounterLeading)
                        .padding(.bottom, Design.Spacing.pageCounterBottom)
                    Spacer()
                }
            }
            .opacity(isWriting ? 0 : 1)
            .animation(.easeInOut(duration: Design.Animation.writingFadeDuration), value: isWriting)
        }
        .navigationBarHidden(true)
        .onChange(of: toolbar.selectedColor) { toolbar.save(colorScheme: colorScheme) }
        .onChange(of: toolbar.activeTool) { oldValue, newValue in
            if oldValue != newValue { toolbar.previousTool = oldValue }
            toolbar.save(colorScheme: colorScheme)
        }
        .onChange(of: toolbar.toolbarIcons) { toolbar.save(colorScheme: colorScheme) }
    }
}
