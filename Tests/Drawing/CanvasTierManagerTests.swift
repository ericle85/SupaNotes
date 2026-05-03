@testable import SupaNotes
import Testing

// Pure-function tests for the 3-tier canvas policy.
// No UIKit, no SwiftData — just (inputs) → (expected assignment).
struct CanvasTierManagerTests {

    // MARK: - assignTiers

    @Test("single visible page gets live + one adjacent")
    func singleVisible() {
        let result = CanvasTierManager.assignTiers(visible: [3], pageCount: 10)
        #expect(result.live == [3])
        #expect(result.adjacent == [2, 4])
    }

    @Test("first page has no left adjacent")
    func firstPage() {
        let result = CanvasTierManager.assignTiers(visible: [0], pageCount: 5)
        #expect(result.live == [0])
        #expect(result.adjacent == [1])
    }

    @Test("last page has no right adjacent")
    func lastPage() {
        let result = CanvasTierManager.assignTiers(visible: [4], pageCount: 5)
        #expect(result.live == [4])
        #expect(result.adjacent == [3])
    }

    @Test("contiguous visible range gets adjacent at edges only")
    func contiguousRange() {
        let result = CanvasTierManager.assignTiers(visible: [2, 3, 4], pageCount: 10)
        #expect(result.live == [2, 3, 4])
        #expect(result.adjacent == [1, 5])
    }

    @Test("empty visible returns empty assignment")
    func emptyVisible() {
        let result = CanvasTierManager.assignTiers(visible: [], pageCount: 10)
        #expect(result == TierAssignment(live: [], adjacent: []))
    }

    @Test("zero pages returns empty assignment")
    func zeroPages() {
        let result = CanvasTierManager.assignTiers(visible: [0], pageCount: 0)
        #expect(result == TierAssignment(live: [], adjacent: []))
    }

    @Test("single-page document has no adjacent")
    func singlePageDocument() {
        let result = CanvasTierManager.assignTiers(visible: [0], pageCount: 1)
        #expect(result.live == [0])
        #expect(result.adjacent.isEmpty)
    }

    // MARK: - evictionTargets

    @Test("evicts live canvases that scrolled out of view")
    func evictLive() {
        let result = CanvasTierManager.evictionTargets(
            visible: [5, 6],
            mountedLive: [3, 4, 5, 6],
            mountedAdjacent: []
        )
        #expect(result.live == [3, 4])
        #expect(result.adjacent.isEmpty)
    }

    @Test("keeps adjacent within ±1 of visible")
    func keepNearbyAdjacent() {
        let result = CanvasTierManager.evictionTargets(
            visible: [5],
            mountedLive: [5],
            mountedAdjacent: [4, 6, 1]
        )
        #expect(result.live.isEmpty)
        // Index 1 is far from visible 5, so it should be evicted.
        #expect(result.adjacent == [1])
    }

    @Test("no evictions when everything is in view")
    func noEvictions() {
        let result = CanvasTierManager.evictionTargets(
            visible: [2, 3],
            mountedLive: [2, 3],
            mountedAdjacent: [1, 4]
        )
        #expect(result == EvictionPlan(live: [], adjacent: []))
    }

    // MARK: - bitmapsToClear

    @Test("clears off-screen bitmaps without canvases")
    func clearOffScreenBitmaps() {
        let bitmapSlots: Set<Int> = [0, 1, 5, 8]
        let result = CanvasTierManager.bitmapsToClear(
            visible: [3, 4],
            canvasIndices: [3, 4, 5],
            slotCount: 10,
            hasBitmap: { bitmapSlots.contains($0) }
        )
        // Slots 0, 1, 8 have bitmaps, are off-screen, and have no canvas.
        // Slot 5 has a bitmap but also has a canvas — keep it.
        #expect(result == [0, 1, 8])
    }

    @Test("keeps bitmaps for visible slots")
    func keepVisibleBitmaps() {
        let result = CanvasTierManager.bitmapsToClear(
            visible: [0, 1],
            canvasIndices: [],
            slotCount: 3,
            hasBitmap: { _ in true }
        )
        // Slot 2 is off-screen with no canvas — clear it.
        #expect(result == [2])
    }
}
