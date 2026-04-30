import Testing
import Foundation
import SwiftData
import SwiftUI
import CoreGraphics
@testable import SupaNotes

// Tests for the drawing brain — stroke creation, erasing, undo, redo.
@MainActor
struct StrokeEngineTests {

    // MARK: - Helpers

    // Bundle that keeps the ModelContainer alive alongside the engine.
    private struct EngineContext {
        let container: ModelContainer
        let engine: StrokeEngine
    }

    // In-memory SwiftData container so Page can be instantiated without a real database.
    private func makeEngineContext(
        tool: ActiveTool = .pen,
        penWidth: CGFloat = 3,
        eraserWidth: CGFloat = 20
    ) throws -> EngineContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Note.self, Page.self, Folder.self, configurations: config)
        let context = container.mainContext
        let page = Page(orderIndex: 0)
        context.insert(page)
        let style = ExcalidrawToolStyle(
            selectedTool: tool,
            selectedColor: .black,
            penWidth: penWidth,
            eraserWidth: eraserWidth
        )
        let engine = StrokeEngine(page: page, toolStyle: style, onPageMutated: {})
        return EngineContext(container: container, engine: engine)
    }

    // Simulate a full stroke: several moved points then a lift.
    private func drawStroke(
        on engine: StrokeEngine,
        points: [(CGFloat, CGFloat)] = [(10, 10), (20, 20), (30, 30), (40, 40)]
    ) {
        for pt in points {
            engine.handleChanged(at: CGPoint(x: pt.0, y: pt.1), pressure: 0.5)
        }
        if let last = points.last {
            engine.handleEnded(at: CGPoint(x: last.0, y: last.1), pressure: 0.5)
        }
    }

    // MARK: - Drawing

    // 3.1 — Touch, move, lift → stroke saved.
    @Test func drawStroke_commitsToDocument() throws {
        let ctx = try makeEngineContext()
        drawStroke(on: ctx.engine)
        #expect(ctx.engine.document.strokes.count == 1)
    }

    // 3.3 — Preview exists during drawing, gone after.
    @Test func activeStroke_existsDuringDrawing_nilAfter() throws {
        let ctx = try makeEngineContext()

        // First point alone doesn't produce a preview (need >1 point).
        ctx.engine.handleChanged(at: CGPoint(x: 10, y: 10), pressure: 0.5)
        // Second point creates preview.
        ctx.engine.handleChanged(at: CGPoint(x: 20, y: 20), pressure: 0.5)
        #expect(ctx.engine.activeStroke != nil)

        // Lifting clears the preview.
        ctx.engine.handleEnded(at: CGPoint(x: 30, y: 30), pressure: 0.5)
        #expect(ctx.engine.activeStroke == nil)
    }

    // 3.4 — Stroke uses current tool settings.
    @Test func drawStroke_usesToolSettings() throws {
        let ctx = try makeEngineContext(penWidth: 8)
        drawStroke(on: ctx.engine)
        #expect(ctx.engine.document.strokes[0].width == 8)
    }

    // MARK: - Undo / Redo

    // 3.5 — Undo removes the last stroke.
    @Test func undo_removesLastStroke() throws {
        let ctx = try makeEngineContext()
        drawStroke(on: ctx.engine)
        #expect(ctx.engine.document.strokes.count == 1)

        ctx.engine.undoManager.undo()
        #expect(ctx.engine.document.strokes.isEmpty)
    }

    // 3.6 — Redo brings back an undone stroke.
    @Test func redo_restoresUndoneStroke() throws {
        let ctx = try makeEngineContext()
        drawStroke(on: ctx.engine)
        ctx.engine.undoManager.undo()
        #expect(ctx.engine.document.strokes.isEmpty)

        ctx.engine.undoManager.redo()
        #expect(ctx.engine.document.strokes.count == 1)
    }

    // 3.7 — Multiple strokes: undo removes only the last.
    @Test func undo_multipleStrokes_removesOnlyLast() throws {
        let ctx = try makeEngineContext()
        let um = ctx.engine.undoManager
        // Disable auto-grouping so each manual group is a separate undo step
        // (in the real app, strokes happen on separate run loop iterations).
        um.groupsByEvent = false

        um.beginUndoGrouping()
        drawStroke(on: ctx.engine, points: [(10, 10), (20, 20), (30, 30)])
        um.endUndoGrouping()

        um.beginUndoGrouping()
        drawStroke(on: ctx.engine, points: [(100, 100), (200, 200), (300, 300)])
        um.endUndoGrouping()

        um.beginUndoGrouping()
        drawStroke(on: ctx.engine, points: [(500, 500), (600, 600), (700, 700)])
        um.endUndoGrouping()

        #expect(ctx.engine.document.strokes.count == 3)

        um.undo()
        #expect(ctx.engine.document.strokes.count == 2)
        // First two strokes still intact.
        #expect(ctx.engine.document.strokes[0].points[0].pointX == 10)
        #expect(ctx.engine.document.strokes[1].points[0].pointX == 100)
    }

    // MARK: - Erasing

    // 3.8 — Eraser removes strokes it touches, leaves others.
    @Test func eraser_removesNearStrokes_leavesDistant() throws {
        let ctx = try makeEngineContext()

        // Draw a stroke near the origin.
        drawStroke(on: ctx.engine, points: [(10, 10), (20, 20), (30, 30)])
        // Draw a stroke far away.
        drawStroke(on: ctx.engine, points: [(500, 500), (510, 510), (520, 520)])
        #expect(ctx.engine.document.strokes.count == 2)

        // Switch to eraser and wipe over the first stroke.
        ctx.engine.updateToolStyle(ExcalidrawToolStyle(
            selectedTool: .eraser, selectedColor: .black, penWidth: 3, eraserWidth: 40
        ))
        ctx.engine.handleChanged(at: CGPoint(x: 15, y: 15), pressure: 0)
        ctx.engine.handleEnded(at: CGPoint(x: 25, y: 25), pressure: 0)

        // Only the far stroke survives.
        #expect(ctx.engine.document.strokes.count == 1)
        #expect(ctx.engine.document.strokes[0].points[0].pointX == 500)
    }

    // 3.9 — Undo restores erased strokes.
    @Test func eraser_undo_restoresErasedStrokes() throws {
        let ctx = try makeEngineContext()
        let um = ctx.engine.undoManager
        um.groupsByEvent = false

        um.beginUndoGrouping()
        drawStroke(on: ctx.engine, points: [(10, 10), (20, 20), (30, 30)])
        um.endUndoGrouping()
        #expect(ctx.engine.document.strokes.count == 1)

        // Erase.
        ctx.engine.updateToolStyle(ExcalidrawToolStyle(
            selectedTool: .eraser, selectedColor: .black, penWidth: 3, eraserWidth: 40
        ))
        um.beginUndoGrouping()
        ctx.engine.handleChanged(at: CGPoint(x: 15, y: 15), pressure: 0)
        ctx.engine.handleEnded(at: CGPoint(x: 25, y: 25), pressure: 0)
        um.endUndoGrouping()
        #expect(ctx.engine.document.strokes.isEmpty)

        // Undo brings erased stroke back.
        um.undo()
        #expect(ctx.engine.document.strokes.count == 1)
    }

    // 3.10 — Eraser cursor visible during erasing, hidden after.
    @Test func eraserCursor_visibleDuringErasing_hiddenAfter() throws {
        let ctx = try makeEngineContext(tool: .eraser)

        ctx.engine.handleChanged(at: CGPoint(x: 50, y: 50), pressure: 0)
        #expect(ctx.engine.eraserCursorCenter != nil)

        ctx.engine.handleEnded(at: CGPoint(x: 60, y: 60), pressure: 0)
        #expect(ctx.engine.eraserCursorCenter == nil)
    }

    // 3.11 — Erasing empty space doesn't register an undo entry.
    @Test func eraser_noHits_noUndoEntry() throws {
        let ctx = try makeEngineContext(tool: .eraser)

        // Wave eraser over empty space.
        ctx.engine.handleChanged(at: CGPoint(x: 100, y: 100), pressure: 0)
        ctx.engine.handleEnded(at: CGPoint(x: 200, y: 200), pressure: 0)

        #expect(ctx.engine.undoManager.canUndo == false)
    }
}
